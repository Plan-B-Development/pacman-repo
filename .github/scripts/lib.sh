# shellcheck shell=bash
# Shared by the repository scripts. Source it; never execute it.
#
# Signing setup. `import_signing_key` imports $GPG_PRIVATE_KEY into a fresh
# GNUPGHOME and hands $GPG_PASSPHRASE to gpg-agent once (gpg-preset-passphrase),
# so every signer started afterwards in the same step signs without a passphrase
# argument: gpg itself, and rpmsign, which runs gpg with arguments of its own and
# has no portable way to pass a loopback passphrase through. The scripts parse
# package payloads before they import the key where the order allows, and stop
# the agent once they have signed.
#
# Every output is then checked against the PUBLISHED key (keys/ventulus.gpg, or
# $PUBLIC_KEY_FILE for a local test), not against the private keyring: a
# signature only counts if the key users were told to trust verifies it.

: "${SIGNING_KEY:?SIGNING_KEY must be the signing key fingerprint}"
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PUBLIC_KEY_FILE=${PUBLIC_KEY_FILE:-$REPO_ROOT/keys/ventulus.gpg}

# The secrets leave the environment as soon as this is sourced, so no child —
# least of all the tools that parse package payloads (apt-ftparchive,
# createrepo_c, tar, dpkg-deb, rpm) — ever inherits them.
_gpg_private_key=${GPG_PRIVATE_KEY-}
_gpg_passphrase=${GPG_PASSPHRASE-}
_gpg_passphrase_set=${GPG_PASSPHRASE+set}
unset GPG_PRIVATE_KEY GPG_PASSPHRASE

import_signing_key() {
    [ -n "$_gpg_private_key" ] || { echo "::error::GPG_PRIVATE_KEY is empty"; return 1; }
    [ -n "$_gpg_passphrase_set" ] || { echo "::error::GPG_PASSPHRASE is unset"; return 1; }
    GNUPGHOME=$(mktemp -d)
    export GNUPGHOME
    chmod 700 "$GNUPGHOME"
    # The agent holds the preset passphrase until it stops; stop it on exit.
    trap 'gpgconf --kill gpg-agent 2>/dev/null || true' EXIT
    # Read when the agent starts, which the secret-key import below does.
    echo allow-preset-passphrase > "$GNUPGHOME/gpg-agent.conf"
    printf '%s\n' "$_gpg_private_key" | gpg --batch --quiet --import
    local preset grips g
    preset="$(gpgconf --list-dirs libexecdir)/gpg-preset-passphrase"
    mapfile -t grips < <(gpg --with-keygrip --with-colons --list-secret-keys "$SIGNING_KEY" \
                           | awk -F: '/^grp:/ {print $10}')
    if [ "${#grips[@]}" -eq 0 ]; then
        echo "::error::GPG_PRIVATE_KEY does not hold the secret key $SIGNING_KEY"
        return 1
    fi
    for g in "${grips[@]}"; do
        printf '%s' "$_gpg_passphrase" | "$preset" --preset "$g"
    done
    unset _gpg_private_key _gpg_passphrase
}

# forget_signing_key: stop the agent, dropping the preset passphrase, once the
# last signature is made.
forget_signing_key() {
    gpgconf --kill gpg-agent
}

# sign <gpg arguments...>: gpg as the repository key, non-interactively.
sign() {
    gpg --batch --yes --local-user "$SIGNING_KEY" "$@"
}

# published_keyring: print the path of a binary keyring holding only the
# published key, made once. gpgv wants a binary keyring; the key file is armored.
published_keyring() {
    if [ -z "${_PUBLISHED_KEYRING:-}" ]; then
        _PUBLISHED_KEYRING=$(mktemp)
        gpg --dearmor < "$PUBLIC_KEY_FILE" > "$_PUBLISHED_KEYRING"
    fi
    printf '%s\n' "$_PUBLISHED_KEYRING"
}

# verify_published <signature> [file]: the signature must verify against the
# published key alone, made by $SIGNING_KEY.
verify_published() {
    local status
    status=$(gpgv --status-fd 1 --keyring "$(published_keyring)" "$@" 2>/dev/null) || {
        echo "::error::$1 does not verify against $PUBLIC_KEY_FILE"
        return 1
    }
    # VALIDSIG's last field is the primary key's fingerprint, whichever key signed.
    if [ "$(awk '$2 == "VALIDSIG" {print $NF}' <<< "$status")" != "$SIGNING_KEY" ]; then
        echo "::error::$1 verifies, but not as $SIGNING_KEY"
        return 1
    fi
    echo "ok: $1 verifies against the published key"
}
