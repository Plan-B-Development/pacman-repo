# control-ofc pacman repository

Signed Arch Linux package repository for [Control-OFC](https://github.com/Plan-B-Development/control-ofc-gui)
— a desktop fan control app (`control-ofc-gui`) and its hardware daemon
(`control-ofc-daemon`).

Set it up once and both packages upgrade with your normal `pacman -Syu`.

**Architecture:** `x86_64` only (the daemon is `x86_64`; the GUI is `any`).

---

## Install

### 1. Trust the signing key

```bash
curl -fsSL https://raw.githubusercontent.com/Plan-B-Development/pacman-repo/main/keys/control-ofc.gpg \
  | sudo pacman-key --add -
sudo pacman-key --lsign-key 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

### 2. Add the repository

```bash
sudo tee -a /etc/pacman.conf <<'EOF'

[control-ofc]
SigLevel = Required
Server = https://github.com/Plan-B-Development/pacman-repo/releases/download/repo
EOF
```

### 3. Install

```bash
sudo pacman -Sy control-ofc-gui
sudo systemctl enable --now control-ofc-daemon
```

`control-ofc-daemon` is pulled in automatically as a dependency of the GUI. If
you only want the daemon (headless), `sudo pacman -Sy control-ofc-daemon`.

---

## Upgrading

```bash
sudo pacman -Syu
```

That's it. There is nothing to re-run and nothing to re-download by hand.

## Removing

```bash
sudo pacman -Rns control-ofc-gui control-ofc-daemon
sudo pacman-key --delete 4AAD6D2DE40D0D10773BF770BC27C5EB2831FCDA
```

…then delete the `[control-ofc]` block from `/etc/pacman.conf`.

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
gh attestation verify <pkg>.pkg.tar.zst --repo Plan-B-Development/control-ofc-gui
```

---

## Not using this repository

The packages are also attached to every upstream GitHub Release, so a one-off
install needs nothing from here:

```bash
gh release download --repo Plan-B-Development/control-ofc-daemon --pattern '*.pkg.tar.zst'
gh release download --repo Plan-B-Development/control-ofc-gui    --pattern '*.pkg.tar.zst'
sudo pacman -U ./control-ofc-daemon-*.pkg.tar.zst ./control-ofc-gui-*.pkg.tar.zst
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
3. `repo-add`, which embeds those signatures into the database
4. sign the database, and replace `repo-add`'s **symlinks** with real copies
   (GitHub Release assets cannot be symlinks — this is the classic way this
   setup ships a broken database)
5. upload everything to the rolling `repo` release in one batch, so the database
   never advertises a package that has not been uploaded yet

`verify.yml` then installs from the published result in a clean Arch container
using the exact commands above, and runs daily on a schedule — because this
repository can break with nobody touching it (expired key, deleted asset), and
the alternative discovery mechanism is a user's `pacman -Syu` failing.

The GPG private key exists only in this repository's Actions secrets. The source
repositories never hold it; they only trigger a rebuild.

> **Do not delete the `repo` release.** It is the `Server` endpoint — deleting it
> breaks `pacman -Sy` for every existing user.
