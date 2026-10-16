#!/bin/bash
# manifest.sh <verified-dir> <out-dir>
#   Write <out-dir>/ventulus-updates.json (manifest.py) and its detached binary
#   signature ventulus-updates.json.sig by the repository key, checked against
#   the published key. Needs python3, tar + zstd, dpkg-deb, rpm, gpg, gpgv and
#   the signing environment of lib.sh.
set -euo pipefail
here=$(dirname "$0")
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

src=${1:?usage: manifest.sh <verified-dir> <out-dir>}
out=${2:?usage: manifest.sh <verified-dir> <out-dir>}
mkdir -p "$out"

python3 "$here/manifest.py" "$src" > "$out/ventulus-updates.json"
import_signing_key
sign --detach-sign -o "$out/ventulus-updates.json.sig" "$out/ventulus-updates.json"
forget_signing_key
verify_published "$out/ventulus-updates.json.sig" "$out/ventulus-updates.json"
cat "$out/ventulus-updates.json"
