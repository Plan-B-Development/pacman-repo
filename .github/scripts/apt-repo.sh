#!/bin/bash
# apt-repo.sh <verified-dir> <out-dir>
#   Build the signed flat APT repository (one for Debian 13 and Ubuntu 26.04)
#   from the verified .debs: the .debs, Packages, Packages.xz, Release,
#   InRelease and Release.gpg, all flat in <out-dir>, ready to be served as
#   assets of the `repo` release (`URIs: …/releases/download/repo/`,
#   `Suites: ./`).
#
# Needs apt-ftparchive (apt-utils), gpg + gpg-agent, gpgv and xz, and the
# signing environment of lib.sh (SIGNING_KEY, GPG_PRIVATE_KEY, GPG_PASSPHRASE).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

src=${1:?usage: apt-repo.sh <verified-dir> <out-dir>}
out=${2:?usage: apt-repo.sh <verified-dir> <out-dir>}
mkdir -p "$out"

mapfile -t debs < <(find "$src" -name '*.deb' | sort)
[ "${#debs[@]}" -eq 2 ] || { echo "::error::expected 2 .debs (daemon + gui), found ${#debs[@]}"; exit 1; }
cp "${debs[@]}" "$out/"
cd "$out"

# A flat repository's Filename is relative to the URI, which is the release
# download path; apt-ftparchive writes './name'.
apt-ftparchive packages . | sed 's|^Filename: \./|Filename: |' > Packages
xz -9 -k -f Packages
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=Ventulus \
    -o APT::FTPArchive::Release::Label=Ventulus \
    -o APT::FTPArchive::Release::Architectures="amd64 all" \
    -o APT::FTPArchive::Release::Description="Ventulus packages for Debian 13 and Ubuntu 26.04" \
    release . > Release.new
mv Release.new Release

# The key only now, after apt-ftparchive has read the packages.
import_signing_key
sign --clearsign -o InRelease Release
sign --detach-sign --armor -o Release.gpg Release
forget_signing_key

# Self-check: every index entry names a file that is here, and both signatures
# verify against the published key.
grep '^Filename: ' Packages | cut -d' ' -f2 | while read -r f; do
    [ -f "$f" ] || { echo "::error::Packages names $f, which is not in the repository"; exit 1; }
    case $f in */*|*'~'*) echo "::error::$f cannot be a release asset name"; exit 1 ;; esac
done
[ "$(grep -c '^Package: ' Packages)" -eq 2 ] || { echo "::error::Packages does not list exactly 2 packages"; exit 1; }
verify_published InRelease
verify_published Release.gpg Release
ls -l
