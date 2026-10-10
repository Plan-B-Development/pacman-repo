# Ventulus pacman repository

Signed Arch Linux package repository for [Ventulus](https://github.com/Plan-B-Development/ventulus)
(formerly Control-OFC) — a desktop fan control app (`ventulus`) and its hardware
daemon (`ventulusd`).

Set it up once and both packages upgrade with your normal `pacman -Syu`.

**Architecture:** `x86_64` only (the daemon is `x86_64`; the GUI is `any`).

---

## Install

Two ways. The script does the same four steps as the manual path, checks the
signing key's fingerprint before trusting it, and is safe to re-run.

### Option A — bootstrap script (recommended)

Download it, check its signature, read it, then run it. Deliberately **not** a
`curl … | sh` one-liner: this script edits `/etc/pacman.conf` and installs a
package that runs as a system service, which is not something to pipe unseen
into a shell.

```bash
base=https://github.com/Plan-B-Development/pacman-repo/releases/download/repo
curl -fsSLO "$base/bootstrap.sh"
curl -fsSLO "$base/bootstrap.sh.sig"

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

It trusts the signing key (verifying the fingerprint first), adds the
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

> **Run this once.** `tee -a` appends, so running it a second time adds a
> duplicate `[ventulus]` block and pacman then warns about a redefined
> repository. Check first with `grep -n '^\[ventulus\]' /etc/pacman.conf` — if
> the block is already there, edit it instead of appending, or use Option A,
> which handles this for you.

```bash
grep -q '^\[ventulus\]' /etc/pacman.conf || sudo tee -a /etc/pacman.conf <<'EOF'

[ventulus]
SigLevel = Required
Server = https://github.com/Plan-B-Development/pacman-repo/releases/download/repo
EOF
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

---

## Upgrading

```bash
sudo pacman -Syu
```

That's it. There is nothing to re-run and nothing to re-download by hand.

## Removing

```bash
sudo pacman -Rns ventulus ventulusd
sudo pacman-key --delete 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

…then delete the `[ventulus]` block from `/etc/pacman.conf`.

---

## Verifying what you installed

Every package and the repository database are signed with:

```
4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
PlanBDevelopment <chomeop@gmail.com>   ed25519, expires 2028-08-03
```

`SigLevel = Required` means pacman refuses anything not signed by that key — you
do not need to check by hand. To inspect it anyway:

```bash
pacman-key --list-keys 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

The upstream releases additionally carry a keyless [Sigstore](https://www.sigstore.dev/)
build-provenance attestation, verifiable against the source repository:

```bash
gh attestation verify <pkg>.pkg.tar.zst --repo Plan-B-Development/ventulus   # or ventulusd
```

---

## Not using this repository

The packages are also attached to every upstream GitHub Release, so a one-off
install needs nothing from here:

```bash
gh release download --repo Plan-B-Development/ventulusd --pattern '*.pkg.tar.zst'
gh release download --repo Plan-B-Development/ventulus  --pattern '*.pkg.tar.zst'
sudo pacman -U ./ventulusd-*.pkg.tar.zst ./ventulus-[0-9]*.pkg.tar.zst
```

Upgrading then means repeating those commands. That is the trade this repository
exists to remove.

---

## How this repository is built

`publish.yml` rebuilds the whole repository from the **current latest release of
each source project** on every run — declarative, not incremental, so re-running
it is always safe and there is no accumulated state to drift.

1. download the newest `.pkg.tar.zst` from each source repo's latest Release
2. detach-sign each package (`.sig` sibling — required by `SigLevel = Required`)
3. `repo-add`, which embeds those signatures into the database — run twice, for
   `ventulus.db` and for the transitional `control-ofc.db`, from the same packages
4. sign the database and `bootstrap.sh`, and replace `repo-add`'s **symlinks**
   with real copies (GitHub Release assets cannot be symlinks — this is the
   classic way this setup ships a broken database)
5. upload in a **deliberate order**: packages and their signatures first, then
   the database staged under temporary names and swapped in by rename

Step 5's ordering is the part that is easy to get wrong. The database is the
pointer, so it must land *last* — nothing may reference a package that is not
already uploaded. It is swapped in by renaming an already-uploaded asset rather
than deleted-and-re-uploaded, because `gh release upload --clobber` removes an
asset before replacing it: the old arrangement left `control-ofc.db` genuinely
absent for the length of an upload, and a `pacman -Sy` landing in that window got
a 404 from a completely healthy repository. Renaming shrinks that window to a
metadata call. It is *effectively* atomic, not atomic — GitHub has no
transaction across release assets.

`verify.yml` then installs from the published result in a clean Arch container
using the exact commands above, and runs daily on a schedule — because this
repository can break with nobody touching it (expired key, deleted asset), and
the alternative discovery mechanism is a user's `pacman -Syu` failing.

This repository's Actions secrets hold the only copy of the GPG private key in
any CI system — the source repositories never hold it, they only trigger a
rebuild. A passphrase-protected backup is kept offline in the maintainer's
keyring, which is what makes key loss recoverable; it is deliberately never
placed in a repository or a CI environment.

> **Do not delete the `repo` release.** It is the `Server` endpoint — deleting it
> breaks `pacman -Sy` for every existing user.
