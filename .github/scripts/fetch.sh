#!/bin/bash
# fetch.sh <out-dir>
#   Download every asset of each project's latest Release into <out-dir>/<project>/
#   and prove it before anything is signed:
#     - the asset set is exactly the one release.yml publishes for that version
#       (check_release below), and matches the Release's SHA256SUMS;
#     - every asset, SHA256SUMS included, carries the Sigstore build provenance
#       of that project's release.yml, built from the Release's own tag on a
#       GitHub-hosted runner (DEC-242).
#   Then reads the daemon's API_VERSION at the same tag for the update manifest,
#   and writes <out-dir>/release.env and <out-dir>/verified.sha256, which the
#   signing jobs check before they touch anything.
#
# fetch.sh --check <dir> <project> <version>
#   Run only the offline asset-set check on a directory (local testing).
#
# Holds no key. Fail-closed: any surprise stops the publish while the key is
# still untouched.
set -euo pipefail

OWNER=Plan-B-Development
PROJECTS=(ventulusd ventulus)

die() { echo "::error::$*" >&2; exit 1; }

# check_release <dir> <project> <version>
check_release() {
    local dir=$1 project=$2 v=$3
    local vre=${v//./\\.} line name
    local -a listed present
    [ -f "$dir/SHA256SUMS" ] || die "$project $v: the Release has no SHA256SUMS"

    while IFS= read -r line; do
        [[ $line =~ ^[0-9a-f]{64}\ \ ([A-Za-z0-9._+-]+)$ ]] \
            || die "$project $v: malformed SHA256SUMS line: $line"
        listed+=("${BASH_REMATCH[1]}")
    done < "$dir/SHA256SUMS"
    mapfile -t present < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name SHA256SUMS -printf '%f\n')
    if [ "$(printf '%s\n' "${listed[@]}" | sort)" != "$(printf '%s\n' "${present[@]}" | sort)" ]; then
        echo "SHA256SUMS lists:"; printf '  %s\n' "${listed[@]}"
        echo "the Release has:";  printf '  %s\n' "${present[@]}"
        die "$project $v: the Release's assets are not exactly the files its SHA256SUMS lists"
    fi
    (cd "$dir" && sha256sum --strict --quiet -c SHA256SUMS) \
        || die "$project $v: an asset does not match SHA256SUMS"

    # Exactly the packages release.yml builds, all of this version. GitHub stores
    # '~' in an asset name as '.', so a name the indices would point at could not
    # be fetched; the version regex below already excludes it.
    local pkg deb rpm tar rpm_min=1 rpm_max=1
    case $project in
        ventulusd)
            pkg="^ventulusd-$vre-[0-9]+-x86_64\.pkg\.tar\.zst$"
            deb="^ventulusd_$vre-[0-9]+_amd64\.deb$"
            rpm="^ventulusd-$vre-[0-9]+\.x86_64\.rpm$"
            tar="^ventulusd-$vre-x86_64\.tar\.gz$" ;;
        ventulus)
            pkg="^ventulus-$vre-[0-9]+-any\.pkg\.tar\.zst$"
            deb="^ventulus_$vre-[0-9]+_all\.deb$"
            # One build per Fedora release (python(abi) differs), so one or more.
            rpm="^ventulus-$vre-[0-9]+\.fc[0-9]+\.noarch\.rpm$"
            rpm_max=99
            tar="^ventulus-$vre-noarch\.tar\.gz$" ;;
        *) die "unknown project $project" ;;
    esac
    local n_pkg=0 n_deb=0 n_rpm=0 n_tar=0
    for name in "${listed[@]}"; do
        if   [[ $name =~ $pkg ]]; then n_pkg=$((n_pkg + 1))
        elif [[ $name =~ $deb ]]; then n_deb=$((n_deb + 1))
        elif [[ $name =~ $rpm ]]; then n_rpm=$((n_rpm + 1))
        elif [[ $name =~ $tar ]]; then n_tar=$((n_tar + 1))
        else die "$project $v: unexpected asset $name"
        fi
    done
    [ "$n_pkg" -eq 1 ] || die "$project $v: expected 1 .pkg.tar.zst, found $n_pkg"
    [ "$n_deb" -eq 1 ] || die "$project $v: expected 1 .deb, found $n_deb"
    [ "$n_tar" -eq 1 ] || die "$project $v: expected 1 tarball, found $n_tar"
    if [ "$n_rpm" -lt "$rpm_min" ] || [ "$n_rpm" -gt "$rpm_max" ]; then
        if [ "$rpm_min" -eq "$rpm_max" ]; then
            die "$project $v: expected $rpm_min .rpm, found $n_rpm"
        fi
        die "$project $v: expected $rpm_min to $rpm_max .rpm, found $n_rpm"
    fi
    if [ "$project" = ventulus ]; then
        # Two builds for one Fedora release would be two candidates in one repo.
        local dup
        dup=$(printf '%s\n' "${listed[@]}" | sed -n 's/.*\.\(fc[0-9]*\)\.noarch\.rpm$/\1/p' | sort | uniq -d)
        [ -z "$dup" ] || die "$project $v: more than one .rpm for $dup"
    fi
    echo "ok: $project $v has exactly the expected assets, matching SHA256SUMS"
}

if [ "${1:-}" = --check ]; then
    check_release "$2" "$3" "$4"
    exit 0
fi

out=${1:?usage: fetch.sh <out-dir> | fetch.sh --check <dir> <project> <version>}
: "${GH_TOKEN:?}"
mkdir -p "$out"
: > "$out/release.env"
declare -A tags

for project in "${PROJECTS[@]}"; do
    echo "::group::$project"
    tag=$(gh release view --repo "$OWNER/$project" --json tagName -q .tagName)
    [[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
        || die "$project: the latest Release's tag '$tag' is not a stable vX.Y.Z"
    version=${BASH_REMATCH[1]}
    # "Latest" is a flag anyone who can edit Releases can move. An older,
    # genuinely attested Release marked latest would otherwise be republished
    # and announced as current: refuse anything but the highest stable tag.
    highest=$(gh release list --repo "$OWNER/$project" --exclude-drafts --exclude-pre-releases \
                --limit 1000 --json tagName -q '.[].tagName' \
              | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
    [ "$highest" = "$tag" ] \
        || die "$project: the Release marked latest is $tag, but $highest is a higher stable Release"
    # Download by tag, not "latest", so a Release published mid-run cannot mix
    # two versions into one publish.
    gh release download "$tag" --repo "$OWNER/$project" --dir "$out/$project"
    check_release "$out/$project" "$project" "$version"
    for f in "$out/$project"/*; do
        gh attestation verify "$f" \
            --repo "$OWNER/$project" \
            --signer-workflow "$OWNER/$project/.github/workflows/release.yml" \
            --source-ref "refs/tags/$tag" \
            --deny-self-hosted-runners > /dev/null
        echo "ok: provenance verified for $(basename "$f")"
    done
    printf '%s_tag=%s\n%s_version=%s\n' "$project" "$tag" "$project" "$version" >> "$out/release.env"
    tags[$project]=$tag
    echo "::endgroup::"
done

# The daemon's API_VERSION, read from its source at the same tag. Exactly one
# definition, or the publish stops: a manifest must never guess it.
src=$(gh api -H 'Accept: application/vnd.github.raw' \
        "repos/$OWNER/ventulusd/contents/daemon/src/api/responses.rs?ref=${tags[ventulusd]}")
mapfile -t api < <(sed -n 's/^pub const API_VERSION: u32 = \([0-9][0-9]*\);$/\1/p' <<< "$src")
[ "${#api[@]}" -eq 1 ] \
    || die "ventulusd ${tags[ventulusd]}: expected one 'pub const API_VERSION: u32 = N;' in daemon/src/api/responses.rs, found ${#api[@]}"
echo "ventulusd_api_version=${api[0]}" >> "$out/release.env"
cat "$out/release.env"

(cd "$out" && find . -type f ! -name verified.sha256 -print0 | sort -z | xargs -0 sha256sum) \
    > "$out/verified.sha256"
