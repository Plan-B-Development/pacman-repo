#!/usr/bin/env bash
# Reads the digest-pinned image each key-holding job of publish.yml runs in from
# .github/images/<name>/Dockerfile and writes `<name>=<ref>` to $GITHUB_OUTPUT.
# Anything but exactly one `FROM <name>:<tag>@sha256:<64 hex>` line fails the
# run before any job that holds the key starts.
set -euo pipefail

for name in archlinux debian fedora; do
  file=".github/images/${name}/Dockerfile"
  [ -f "$file" ] || { echo "::error::${file} is missing"; exit 1; }
  mapfile -t from < <(grep -E '^FROM ' "$file" || true)
  if [ "${#from[@]}" -ne 1 ]; then
    echo "::error::${file} must hold exactly one FROM line"
    exit 1
  fi
  ref=${from[0]#FROM }
  if ! [[ "$ref" =~ ^${name}:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]]; then
    echo "::error::${file}: '${ref}' is not ${name}:<tag>@sha256:<digest>"
    exit 1
  fi
  echo "${name}=${ref}" | tee -a "$GITHUB_OUTPUT"
done
