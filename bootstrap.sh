#!/usr/bin/env bash
#
# Control-OFC first-install bootstrap (DEC-248).
#
# Does the three things the README asks you to do by hand — trust the signing
# key, add the [control-ofc] repository, install — plus the one step people
# forget afterwards: starting the daemon. Without that last step the packages
# install cleanly and the GUI opens to a "disconnected" screen, which reads as a
# broken install.
#
# The install is a FULL system upgrade (`-Syuw` then `-Su`), never a targeted
# install onto un-upgraded databases, which Arch does not support. That step is
# interactive on purpose: it may upgrade much more than control-ofc, so pacman
# shows the transaction and you confirm it once. The script is therefore not
# suitable for unattended use.
#
# SAFE TO RE-RUN. Every step checks its own end state first, so a run that died
# halfway (dropped network, cancelled sudo) can simply be run again. In
# particular it will not append a second [control-ofc] block to pacman.conf —
# the copy-pasteable `tee -a` in the old README did exactly that on a re-run.
#
# It assumes a working Arch x86_64 system. There is deliberately no distro or
# architecture check: if you are somewhere else, the first step that cannot work
# fails with its own tool's error message, which says more than a guess of ours
# would.
#
# Verify this script before running it — see README.md § Install.

set -euo pipefail

REPO_NAME='control-ofc'
KEY_FPR='4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA'
KEY_URL="https://raw.githubusercontent.com/Plan-B-Development/pacman-repo/main/keys/${REPO_NAME}.gpg"
SERVER_URL='https://github.com/Plan-B-Development/pacman-repo/releases/download/repo'
PACMAN_CONF='/etc/pacman.conf'
PROJECTS=(control-ofc-daemon control-ofc-gui)

if [ "$(id -u)" -eq 0 ]; then
    SUDO=''
else
    SUDO='sudo'
fi

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31m==> %s\033[0m\n' "$*" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------------------
# 1. Trust the signing key
# ---------------------------------------------------------------------------
# The fingerprint is checked BEFORE the key is added, never after. `pacman-key
# --add` imports whatever bytes it is handed; with SigLevel = Required the
# imported key then decides what pacman will silently install on every -Syu. A
# substituted key at this step is the whole ballgame, so the check fails closed.
say "Trusting the repository signing key"

if $SUDO pacman-key --list-keys "$KEY_FPR" >/dev/null 2>&1; then
    note "already in the pacman keyring — nothing to do"
else
    curl -fsSL "$KEY_URL" -o "$WORKDIR/${REPO_NAME}.gpg" \
        || die "could not download the signing key from $KEY_URL"

    # Read the fingerprint out of the downloaded file without importing it
    # anywhere. --with-colons gives a stable machine-readable field; the "fpr"
    # record's 10th field is the full fingerprint.
    got="$(gpg --batch --with-colons --import-options show-only --import \
             "$WORKDIR/${REPO_NAME}.gpg" 2>/dev/null \
           | awk -F: '/^fpr:/ {print $10; exit}')"

    [ -n "$got" ] || die "could not read a fingerprint from the downloaded key"

    if [ "$got" != "$KEY_FPR" ]; then
        die "SIGNING KEY FINGERPRINT MISMATCH — refusing to trust it.
    expected: $KEY_FPR
    got:      $got
Do not proceed. Report this at
https://github.com/Plan-B-Development/pacman-repo/issues"
    fi
    note "fingerprint verified: $KEY_FPR"

    $SUDO pacman-key --add "$WORKDIR/${REPO_NAME}.gpg"
    # Local signature is what actually makes pacman trust it. If a run is
    # interrupted between --add and --lsign-key the key is present but
    # untrusted, and this step will be skipped on the next run — the sync in
    # step 3 then fails with pacman's own "unknown trust" error. Recover with
    # `sudo pacman-key --delete $KEY_FPR` and re-run.
    $SUDO pacman-key --lsign-key "$KEY_FPR"
    note "key added and locally signed"
fi

# ---------------------------------------------------------------------------
# 2. Add the [control-ofc] repository
# ---------------------------------------------------------------------------
say "Configuring $PACMAN_CONF"

desired_block="
[$REPO_NAME]
SigLevel = Required
Server = $SERVER_URL"

section_field() {
    # Print one field from inside the [control-ofc] section, ignoring the same
    # key if it appears under any other repository.
    awk -v key="$1" '
        /^\[/                { in_section = ($0 == "['"$REPO_NAME"']") ; next }
        !in_section          { next }
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            print
            exit
        }
    ' "$PACMAN_CONF"
}

if grep -q "^\[$REPO_NAME\]" "$PACMAN_CONF"; then
    if [ "$(section_field Server)" = "$SERVER_URL" ] \
    && [ "$(section_field SigLevel)" = "Required" ]; then
        note "[$REPO_NAME] already configured correctly — leaving it alone"
    else
        note "[$REPO_NAME] exists but does not match — rewriting it"
        $SUDO cp "$PACMAN_CONF" "${PACMAN_CONF}.control-ofc.bak"
        note "previous file saved as ${PACMAN_CONF}.control-ofc.bak"

        # Drop the existing section: skip from its header up to the next
        # section header (which is itself kept) or end of file.
        awk -v name="[$REPO_NAME]" '
            $0 == name { skip = 1; next }
            /^\[/      { skip = 0 }
            !skip
        ' "$PACMAN_CONF" > "$WORKDIR/pacman.conf"

        printf '%s\n' "$desired_block" >> "$WORKDIR/pacman.conf"
        $SUDO cp "$WORKDIR/pacman.conf" "$PACMAN_CONF"
        note "[$REPO_NAME] updated"
    fi
else
    $SUDO cp "$PACMAN_CONF" "${PACMAN_CONF}.control-ofc.bak"
    note "previous file saved as ${PACMAN_CONF}.control-ofc.bak"
    printf '%s\n' "$desired_block" | $SUDO tee -a "$PACMAN_CONF" >/dev/null
    note "[$REPO_NAME] added"
fi

# ---------------------------------------------------------------------------
# 3. Sync, verify provenance, install
# ---------------------------------------------------------------------------
# FULL UPGRADE, NEVER A PARTIAL ONE.
#
# `pacman -Sy` followed by `pacman -S <pkg>` is the classic Arch partial-upgrade
# footgun: it refreshes the databases and then installs a package built against
# whatever is current, onto a system that has not been upgraded to match. Arch
# supports no such state, and the result is missing-library breakage that can
# take out unrelated software.
#
# So the refresh and the download are one `-Syuw` (sync, sysupgrade,
# download-only): it resolves the whole upgrade plus our target and fetches all
# of it without installing anything. That leaves the packages in the cache to be
# checked before they are applied, without ever having touched the system.
say "Refreshing databases and downloading (full system upgrade)"
$SUDO pacman -Syuw --noconfirm control-ofc-gui

# Sigstore build provenance is an EXTRA check on top of the GPG signature pacman
# already enforces. It proves the bytes came from the source project's release
# workflow, not merely that this repository signed them. It needs `gh`, and an
# authenticated one, which a fresh machine usually has neither of — so its
# absence is reported and skipped rather than treated as a failure.
say "Verifying build provenance"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    for project in "${PROJECTS[@]}"; do
        # Newest cached file for this project. Imprecise if several versions are
        # cached, which is why a mismatch is reported rather than fatal.
        pkg="$(ls -t /var/cache/pacman/pkg/"${project}"-[0-9]*.pkg.tar.zst 2>/dev/null | head -1 || true)"
        if [ -z "$pkg" ]; then
            note "$project: no cached package found — skipping"
            continue
        fi
        if gh attestation verify "$pkg" \
              --repo "Plan-B-Development/${project}" \
              --signer-workflow "Plan-B-Development/${project}/.github/workflows/release.yml" \
              >/dev/null 2>&1; then
            note "$project: provenance verified"
        else
            note "$project: provenance could NOT be verified for $(basename "$pkg")"
            note "  the package is still GPG-signed and pacman will enforce that."
            note "  to inspect: gh attestation verify $pkg --repo Plan-B-Development/${project}"
        fi
    done
else
    note "gh is not installed or not authenticated — skipping this optional check."
    note "packages are still signature-checked by pacman (SigLevel = Required)."
fi

# `-Su` (no `-y`: the databases were refreshed moments ago) applies the same full
# upgrade that was just downloaded, with our target in the SAME transaction — so
# there is no window in which control-ofc is installed against an un-upgraded
# system. Everything needed is already cached, so this does not re-download.
#
# Deliberately INTERACTIVE. This is the only step that changes the system, it may
# upgrade far more than control-ofc, and the user should see that transaction and
# agree to it. That makes the script unsuitable for unattended use, which is the
# intended trade.
say "Installing"
note "pacman will list the full transaction and ask you to confirm it."
$SUDO pacman -Su --needed control-ofc-gui

# ---------------------------------------------------------------------------
# 4. Start the daemon
# ---------------------------------------------------------------------------
# The GUI talks to the daemon over a Unix socket and does nothing useful without
# it. Skipping this is the single most common "it installed but does not work".
say "Enabling the daemon"
if systemctl is-enabled --quiet control-ofc-daemon 2>/dev/null \
&& systemctl is-active --quiet control-ofc-daemon 2>/dev/null; then
    note "control-ofc-daemon is already enabled and running"
else
    $SUDO systemctl enable --now control-ofc-daemon
    note "control-ofc-daemon enabled and started"
fi

say "Done"
note "Launch the GUI with:  control-ofc-gui"
note "Try it without hardware:  control-ofc-gui --demo"
note "Upgrades from now on:  sudo pacman -Syu"
