#!/bin/bash
# dnf-repo.sh <verified-dir> <site-dir>
#   Build the signed DNF repositories for GitHub Pages from the verified .rpms:
#     <site-dir>/rpm/fedora/<N>/x86_64/   one per Fedora release N with a GUI
#                                         build (ventulus-…fcN.noarch.rpm); the
#                                         daemon .rpm, built once, is in each
#     <site-dir>/ventulus.repo            baseurl …/rpm/fedora/$releasever/$basearch/
#   Every .rpm is signed (rpmsign) and every repodata/repomd.xml carries a
#   detached armored signature (repomd.xml.asc) for repo_gpgcheck.
#
# Signing changes the .rpm bytes, so the files served here no longer match the
# source Release's SHA256SUMS; the update manifest describes the Release assets.
#
# Needs rpm-sign, createrepo_c and gnupg2 (Fedora), and the signing environment
# of lib.sh. PAGES_URL and KEY_URL may be overridden for a local test.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

src=${1:?usage: dnf-repo.sh <verified-dir> <site-dir>}
site=${2:?usage: dnf-repo.sh <verified-dir> <site-dir>}
PAGES_URL=${PAGES_URL:-https://plan-b-development.github.io/pacman-repo}
KEY_URL=${KEY_URL:-https://raw.githubusercontent.com/Plan-B-Development/pacman-repo/main/keys/ventulus.gpg}

mapfile -t daemon < <(find "$src" -name 'ventulusd-*.x86_64.rpm')
mapfile -t gui < <(find "$src" -name 'ventulus-*.fc*.noarch.rpm' | sort)
[ "${#daemon[@]}" -eq 1 ] || { echo "::error::expected 1 daemon .rpm, found ${#daemon[@]}"; exit 1; }
[ "${#gui[@]}" -ge 1 ] || { echo "::error::no GUI .rpm"; exit 1; }

import_signing_key
work=$(mktemp -d)
cp "${daemon[0]}" "${gui[@]}" "$work/"
rpmsign --define "_openpgp_sign_id $SIGNING_KEY" --addsign "$work"/*.rpm

# Check each signed .rpm against the published key alone, in a scratch rpmdb.
rpmdb=$(mktemp -d)
rpmkeys --dbpath "$rpmdb" --import "$PUBLIC_KEY_FILE"
for f in "$work"/*.rpm; do
    rpmkeys --dbpath "$rpmdb" -K "$f" | tee /dev/stderr | grep -q ': digests signatures OK$' \
        || { echo "::error::$(basename "$f") does not verify against the published key"; exit 1; }
done

daemon_signed="$work/$(basename "${daemon[0]}")"
for g in "${gui[@]}"; do
    name=$(basename "$g")
    [[ $name =~ \.fc([0-9]+)\.noarch\.rpm$ ]] || { echo "::error::no Fedora release in $name"; exit 1; }
    dir="$site/rpm/fedora/${BASH_REMATCH[1]}/x86_64"
    mkdir -p "$dir"
    cp "$daemon_signed" "$work/$name" "$dir/"
    createrepo_c --quiet --general-compress-type=zstd "$dir"
    sign --detach-sign --armor -o "$dir/repodata/repomd.xml.asc" "$dir/repodata/repomd.xml"
    verify_published "$dir/repodata/repomd.xml.asc" "$dir/repodata/repomd.xml"
done
forget_signing_key

# Literal $releasever and $basearch: dnf substitutes them on the client.
# Each deployment replaces the whole site, and every run re-signs every .rpm
# (new bytes, same name), so metadata older than the deployment can point at a
# file that is gone or changed. dnf5 keeps metadata 48 h by default; 6 h bounds
# that window (README § Fedora, and `dnf upgrade --refresh` skips it).
# skip_if_unavailable: a Fedora release with no build here (one newer than the
# last Release, or rawhide) gets a 404 for its $releasever directory; dnf5 then
# skips this repository with a warning instead of failing every command. A
# metadata or package signature failure is still a refusal.
cat > "$site/ventulus.repo" <<EOF
[ventulus]
name=Ventulus
baseurl=${PAGES_URL%/}/rpm/fedora/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$KEY_URL
metadata_expire=6h
skip_if_unavailable=True
EOF
find "$site" -type f | sort
