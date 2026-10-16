# Ventulus package repositories

Signed package repositories for [Ventulus](https://github.com/Plan-B-Development/ventulus)
(formerly Control-OFC) — a desktop fan control app (`ventulus`) and its hardware
daemon (`ventulusd`):

| Distribution | Repository | Upgrades with |
| --- | --- | --- |
| Arch Linux, CachyOS, EndeavourOS, Garuda | pacman `[ventulus]` | `sudo pacman -Syu` |
| Debian 13, Ubuntu 26.04 LTS | APT | `sudo apt upgrade` |
| Fedora 44, Fedora 45 | DNF | `sudo dnf upgrade` |

Set one up once and both packages upgrade with the rest of your system.

**Architecture:** `x86_64` only (the daemon is `x86_64`; the GUI is
architecture-independent). Not supported: Manjaro, Debian 12, Ubuntu 24.04 and
the distributions built on it (Linux Mint 22, Pop!_OS 24.04), RHEL/AlmaLinux/Rocky
9–10 and openSUSE Leap 16 — they lack PySide6 or a recent enough numpy or
pyqtgraph, or hold Arch packages back.

Every repository is signed with one key:

```
4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
PlanBDevelopment <chomeop@gmail.com>   ed25519, expires 2028-08-03
```

Every command on this page works as written in bash, zsh and fish.

---

## Arch Linux and derivatives

Two ways. The script does the same four steps as the manual path, checks the
signing key's fingerprint before trusting it, and is safe to re-run.

### Option A — bootstrap script (recommended)

Download it, check its signature, read it, then run it. Deliberately **not** a
`curl … | sh` one-liner: this script edits `/etc/pacman.conf` and installs a
package that runs as a system service, which is not something to pipe unseen
into a shell.

```bash
curl -fsSLO https://github.com/Plan-B-Development/pacman-repo/releases/download/repo/bootstrap.sh
curl -fsSLO https://github.com/Plan-B-Development/pacman-repo/releases/download/repo/bootstrap.sh.sig

# Verify it was signed by this repository's release key
curl -fsSL https://raw.githubusercontent.com/Plan-B-Development/pacman-repo/main/keys/ventulus.gpg | gpg --import
gpg --verify bootstrap.sh.sig bootstrap.sh
```

`gpg --verify` must report a good signature from:

```
4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

Compare that fingerprint character by character. gpg will also warn that the key
is not certified with a trusted signature — that is expected, and the
fingerprint is what settles it. Then read the script and run it:

```bash
less bootstrap.sh
bash ./bootstrap.sh
```

It first prints what it detected — distribution, CPU architecture, init system,
pacman — and stops with exit status 3, having changed nothing, on a machine the
packages cannot work on: a distribution not built on Arch (Debian, Ubuntu and
Fedora are pointed at their sections below), Manjaro (the GUI package installs
into the Python version current Arch ships, and Manjaro's can lag behind it), a
CPU other than x86_64, a system not booted with systemd, or one without pacman
(or without sudo, when not run as root).

Otherwise it trusts the signing key (verifying the fingerprint first), adds the
repository, installs both packages, and enables the daemon. Re-running it is
safe — every step checks its own end state, so an interrupted run can just be
run again.

The install step is a **full system upgrade** (`pacman -Syu`), because installing
into a partially-upgraded system is not something Arch supports. That step is
interactive: pacman lists everything it is about to do and asks you to confirm
once. So the script is not suitable for unattended use, and it may upgrade more
than just Ventulus.

### Option B — by hand

#### 1. Trust the signing key

```bash
curl -fsSL https://raw.githubusercontent.com/Plan-B-Development/pacman-repo/main/keys/ventulus.gpg \
  | sudo pacman-key --add -
sudo pacman-key --lsign-key 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

#### 2. Add the repository

> The `grep -q` guard makes this append nothing when a `[ventulus]` block is
> already there, so a second run does not duplicate it. It also does not
> correct an existing block that is wrong; edit that by hand, or use Option A,
> which checks and rewrites it for you.

```bash
grep -q '^\[ventulus\]' /etc/pacman.conf || printf '%s\n' '' '[ventulus]' \
  'SigLevel = Required' \
  'Server = https://github.com/Plan-B-Development/pacman-repo/releases/download/repo' \
  | sudo tee -a /etc/pacman.conf
```

#### 3. Install

```bash
sudo pacman -Syu ventulus
sudo systemctl enable --now ventulusd
```

`ventulusd` is pulled in automatically as a dependency of the GUI. If you only
want the daemon (headless), `sudo pacman -Syu ventulusd`.

Do not skip `systemctl enable --now` — the GUI talks to the daemon over a Unix
socket and opens to a "disconnected" screen without it.

### Upgrading

```bash
sudo pacman -Syu
```

That's it. There is nothing to re-run and nothing to re-download by hand.

For about two minutes after a new release is published, `pacman -Syu` can stop
with `invalid or corrupted database (PGP signature)` for this repository:
GitHub keeps serving the replaced database and its signature from its cache for
a while, and for a moment one can be new while the other is still old. pacman
refuses the pair and upgrades nothing. Run `sudo pacman -Syu` again a few
minutes later.

### Removing

```bash
sudo pacman -Rns ventulus ventulusd
sudo pacman-key --delete 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

…then delete the `[ventulus]` block from `/etc/pacman.conf`.

`SigLevel = Required` means pacman refuses anything not signed by the key — you
do not need to check by hand. To inspect it anyway:

```bash
pacman-key --list-keys 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

---

## Debian and Ubuntu

Debian 13 and Ubuntu 26.04 LTS. One repository serves both.

#### 1. Trust the signing key

```bash
sudo apt install ca-certificates curl gpg
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://raw.githubusercontent.com/Plan-B-Development/pacman-repo/main/keys/ventulus.gpg \
  | sudo tee /etc/apt/keyrings/ventulus.asc > /dev/null
gpg --show-keys /etc/apt/keyrings/ventulus.asc
```

The fingerprint `gpg --show-keys` prints must be
`4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA`. Keep the `.asc` name: the key
file is armored, and apt expects an armored key file to end in `.asc`.

#### 2. Add the repository and install

```bash
printf '%s\n' 'Types: deb' \
  'URIs: https://github.com/Plan-B-Development/pacman-repo/releases/download/repo/' \
  'Suites: ./' \
  'Signed-By: /etc/apt/keyrings/ventulus.asc' \
  | sudo tee /etc/apt/sources.list.d/ventulus.sources
sudo apt update
sudo apt install ventulus
```

`ventulusd` comes with the GUI, and the daemon is enabled and started on install
(`systemctl status ventulusd`). For the daemon alone, `sudo apt install ventulusd`.
`Signed-By` limits this key to this repository: apt refuses its indexes unless
they are signed by it, and the indexes pin every package's checksum.

### Upgrading

```bash
sudo apt update
sudo apt upgrade
```

For two or three minutes after a new release is published, `apt update` can
report a checksum mismatch ("Hash Sum mismatch" or "File has unexpected size")
for this repository: GitHub keeps serving a replaced index file from its cache
for a while, so apt can get a new index with an old one beside it. apt then
keeps the package lists it had and changes nothing. Run `sudo apt update` again
a few minutes later.

### Removing

```bash
sudo apt remove ventulus ventulusd
sudo rm /etc/apt/sources.list.d/ventulus.sources /etc/apt/keyrings/ventulus.asc
```

`apt purge` instead of `apt remove` also deletes the configuration files the
packages installed under `/etc`, edited or not.

---

## Fedora

Fedora 44 and 45. The repository is built per Fedora release, so a newer
release is served only once a build for it is published. Until then `dnf` skips
the repository with a warning and leaves Ventulus as it is. A `ventulus.repo`
without the line `skip_if_unavailable=True` (fetched before Fedora 45 was
added) stops every `dnf` command instead; fetch it again with the first command
below.

```bash
curl -fsSL https://plan-b-development.github.io/pacman-repo/ventulus.repo \
  | sudo tee /etc/yum.repos.d/ventulus.repo
sudo dnf install ventulus
sudo systemctl enable --now ventulusd
```

On the first install, dnf asks to import the signing key and prints its
fingerprint; it must be `4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA`. dnf
then checks the signature of the repository metadata and of every package.

`ventulusd` comes with the GUI. Fedora leaves a newly installed service
disabled, so `systemctl enable --now` is needed — without it the GUI opens to a
"disconnected" screen. For the daemon alone, `sudo dnf install ventulusd`.

### Upgrading

```bash
sudo dnf upgrade
```

dnf reuses this repository's metadata for up to six hours. If it reports a
missing package or a checksum error right after a new release, its metadata is
older than the release: `sudo dnf upgrade --refresh` fetches it again.

### Removing

```bash
sudo dnf remove ventulus ventulusd
sudo rm /etc/yum.repos.d/ventulus.repo
```

---

## Checking the build provenance

Each upstream Release additionally carries a keyless
[Sigstore](https://www.sigstore.dev/) build-provenance attestation for every
package, verifiable against the source repository:

```bash
gh attestation verify ./ventulus_X.Y.Z-1_all.deb --repo Plan-B-Development/ventulus
```

(`--repo Plan-B-Development/ventulusd` for the daemon). The publish workflow
checks every one of them before it signs anything. The `.rpm` files served by
the DNF repository have a signature added, so their checksums differ from the
Release's and only the Release's copy verifies this way.

---

## Not using a repository

The packages are also attached to every upstream GitHub Release (`.pkg.tar.zst`,
`.deb`, `.rpm` and a tarball), so a one-off install needs nothing from here:

```bash
# Arch
gh release download --repo Plan-B-Development/ventulusd --pattern '*.pkg.tar.zst'
gh release download --repo Plan-B-Development/ventulus  --pattern '*.pkg.tar.zst'
sudo pacman -U ./ventulusd-*.pkg.tar.zst ./ventulus-*-any.pkg.tar.zst
```

```bash
# Debian 13, Ubuntu 26.04
gh release download --repo Plan-B-Development/ventulusd --pattern '*.deb'
gh release download --repo Plan-B-Development/ventulus  --pattern '*.deb'
sudo apt install ./ventulusd_*_amd64.deb ./ventulus_*_all.deb
```

```bash
# Fedora 44 and 45: the GUI .rpm built for this Fedora release
gh release download --repo Plan-B-Development/ventulusd --pattern '*.rpm'
gh release download --repo Plan-B-Development/ventulus  --pattern "*.fc$(rpm -E %fedora).noarch.rpm"
sudo dnf install ./ventulusd-*.x86_64.rpm ./ventulus-*.noarch.rpm
```

The tarballs (`ventulusd-X.Y.Z-x86_64.tar.gz`, `ventulus-X.Y.Z-noarch.tar.gz`)
install on Debian 13, Ubuntu 26.04 and Fedora 44 and 45 without a package manager; the
GUI's [Getting Started](https://github.com/Plan-B-Development/ventulus/blob/main/manual/getting-started.md#the-tarball)
has the steps, and the GUI's update check can download and verify a new one.

Upgrading a release install means repeating those commands. That is the trade
the repositories exist to remove.

---

## Update manifest

The Ventulus GUI's update check (off by default) reads
`https://plan-b-development.github.io/pacman-repo/ventulus-updates.json` and its
detached signature `ventulus-updates.json.sig`, made with the same key. It
lists each component's latest version and Release, the SHA-256 and URL of every
Release asset, the GUI's minimum daemon version and the daemon's API version.
The GUI checks the signature against the key it ships before it reads anything
else.

---

## How the repositories are built

`publish.yml` rebuilds everything from the **current latest release of each
source project** on every run — declarative, not incremental, so re-running it
is always safe and there is no accumulated state to drift.

1. download every asset of each source repo's latest Release, check the set is
   exactly the expected packages and matches the Release's `SHA256SUMS`, and
   verify each asset's build provenance (no key is loaded yet)
2. pacman: detach-sign each package (`.sig` sibling — required by
   `SigLevel = Required`), then `repo-add`, which embeds those signatures into
   the database — run twice, for `ventulus.db` and for the transitional
   `control-ofc.db`, from the same packages; sign the databases and
   `bootstrap.sh`, and replace `repo-add`'s **symlinks** with real copies
   (GitHub Release assets cannot be symlinks)
3. APT: a flat repository — `Packages`, `Release`, and the signed `InRelease`
   and `Release.gpg`
4. DNF: sign each `.rpm`, build `repodata/` per Fedora release, and sign each
   `repomd.xml`
5. write and sign `ventulus-updates.json`
6. upload pacman and APT to the `repo` release in a **deliberate order**:
   packages and their signatures first, then the indexes staged under temporary
   names and swapped in by rename
7. deploy DNF and the manifest to GitHub Pages in one deployment
8. prune the superseded packages from the `repo` release, no sooner than five
   minutes after the swap

Step 6's ordering is the part that is easy to get wrong. The indexes are the
pointers, so they must land *last* — nothing may reference a package that is
not already uploaded. They are swapped in by renaming an already-uploaded asset
rather than deleted-and-re-uploaded, because `gh release upload --clobber`
removes an asset before replacing it: the old arrangement left `control-ofc.db`
genuinely absent for the length of an upload, and a `pacman -Sy` landing in
that window got a 404 from a completely healthy repository. Renaming shrinks
that window to a metadata call. It is *effectively* atomic, not atomic — GitHub
has no transaction across release assets, and it serves a replaced asset from
cache for a while (the window described under [Debian and Ubuntu](#debian-and-ubuntu)).
Pages is deployed after the release, so the manifest never announces a version
pacman and APT do not serve yet. The prune waits out that cache: an old index
still being served names the old packages, so deleting them straight after the
swap would turn every upgrade in those two minutes into a 404.

`verify.yml` then installs from the published result in clean Arch, Debian 13,
Ubuntu 26.04, Fedora 44 and Fedora 45 containers using the commands above, checks the
manifest's signature and contents against the Releases, checks that
`bootstrap.sh` refuses the machines it should, and parses every command on this
page in bash, zsh and fish. It runs daily on a schedule — because these
repositories can break with nobody touching them (expired key, deleted asset),
and the alternative discovery mechanism is a user's upgrade failing.

This repository's Actions secrets hold the only copy of the GPG private key in
any CI system — the source repositories never hold it, they only trigger a
rebuild. A passphrase-protected backup is kept offline in the maintainer's
keyring, which is what makes key loss recoverable; it is deliberately never
placed in a repository or a CI environment.

> **Do not delete the `repo` release.** It is the pacman `Server` and the APT
> `URIs` endpoint — deleting it breaks `pacman -Sy` and `apt update` for every
> existing user.
