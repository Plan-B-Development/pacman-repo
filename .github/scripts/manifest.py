#!/usr/bin/env python3
"""manifest.py <verified-dir>: print ventulus-updates.json for the verified Releases.

The update manifest (DEC-499 decision 3) the GUI's opt-in update check reads,
served beside its detached signature by the repository key. Format 1:

    {
      "schema": 1,
      "generated_at": "2026-10-16T12:00:00Z",
      "components": {
        "ventulusd": {"version", "tag", "release_url", "api_version", "assets"},
        "ventulus":  {"version", "tag", "release_url", "daemon_minimum", "assets"}
      }
    }

Each asset is {"name", "format", "sha256", "size", "url"} (+ "fedora" for an
.rpm), describing the file attached to the source Release, as its SHA256SUMS
lists it. `format` is one of pacman, deb, rpm, tarball.

`daemon_minimum` is the GUI's ventulusd floor, read from the GUI's own
packages; the Arch, Debian and every Fedora package must agree on it, or no
manifest is written. Needs tar with zstd, dpkg-deb and rpm.
"""

from __future__ import annotations

import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

OWNER = "Plan-B-Development"
VERSION = re.compile(r"^\d+\.\d+\.\d+$")


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def read_env(path: Path) -> dict[str, str]:
    env = {}
    for line in path.read_text().splitlines():
        m = re.fullmatch(r"([a-z_]+)=([A-Za-z0-9.]+)", line)
        if not m:
            fail(f"malformed line in {path.name}: {line!r}")
        env[m.group(1)] = m.group(2)
    return env


def run(*cmd: str) -> str:
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def version_key(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.split("."))


def asset_format(name: str) -> str:
    for suffix, fmt in ((".pkg.tar.zst", "pacman"), (".deb", "deb"), (".rpm", "rpm"), (".tar.gz", "tarball")):
        if name.endswith(suffix):
            return fmt
    fail(f"no format for asset {name}")
    raise AssertionError  # unreachable


def assets(project: str, tag: str, folder: Path) -> list[dict]:
    out = []
    for line in (folder / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        entry = {
            "name": name,
            "format": asset_format(name),
            "sha256": digest,
            "size": (folder / name).stat().st_size,
            "url": f"https://github.com/{OWNER}/{project}/releases/download/{tag}/{name}",
        }
        fc = re.search(r"\.fc(\d+)\.noarch\.rpm$", name)
        if fc:
            entry["fedora"] = int(fc.group(1))
        out.append(entry)
    return sorted(out, key=lambda a: a["name"])


def one_floor(source: str, constraints: list[str]) -> str:
    """The single `>= X.Y.Z` constraint on ventulusd one package declares."""
    if len(constraints) != 1 or not VERSION.match(constraints[0]):
        fail(f"{source}: expected one 'ventulusd >= X.Y.Z' dependency, found {constraints!r}")
    return constraints[0]


def daemon_minimum(folder: Path) -> str:
    floors = {}
    for pkg in folder.glob("*.pkg.tar.zst"):
        info = run("tar", "--zstd", "-xOf", str(pkg), ".PKGINFO")
        floors[pkg.name] = one_floor(pkg.name, re.findall(r"^depend = ventulusd(?:>=(\S+)|\s*$)", info, re.M))
    for deb in folder.glob("*.deb"):
        depends = run("dpkg-deb", "-f", str(deb), "Depends")
        found = [m.group(1) or "" for m in re.finditer(r"(?:^|,)\s*ventulusd\b(?:\s*\(>=\s*([^)\s]+)\))?", depends)]
        floors[deb.name] = one_floor(deb.name, found)
    for rpm in folder.glob("*.rpm"):
        requires = run("rpm", "-qp", "--requires", str(rpm))
        floors[rpm.name] = one_floor(rpm.name, re.findall(r"^ventulusd(?:\s*>=\s*(\S+)|\s*$)", requires, re.M))
    if len(floors) < 3:
        fail(f"read the daemon floor from only {sorted(floors)}")
    if len(set(floors.values())) != 1:
        fail(f"the GUI packages disagree on their ventulusd floor: {floors}")
    return next(iter(floors.values()))


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: manifest.py <verified-dir>")
    root = Path(sys.argv[1])
    env = read_env(root / "release.env")
    components = {}
    for project in ("ventulusd", "ventulus"):
        tag, version = env[f"{project}_tag"], env[f"{project}_version"]
        if tag != f"v{version}" or not VERSION.match(version):
            fail(f"{project}: tag {tag} and version {version} disagree")
        components[project] = {
            "version": version,
            "tag": tag,
            "release_url": f"https://github.com/{OWNER}/{project}/releases/tag/{tag}",
            "assets": assets(project, tag, root / project),
        }
    components["ventulusd"]["api_version"] = int(env["ventulusd_api_version"])
    floor = daemon_minimum(root / "ventulus")
    if version_key(floor) > version_key(components["ventulusd"]["version"]):
        fail(f"the GUI needs ventulusd >= {floor}, but the latest daemon is {components['ventulusd']['version']}")
    components["ventulus"]["daemon_minimum"] = floor

    manifest = {
        "schema": 1,
        "generated_at": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "components": components,
    }
    json.dump(manifest, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
