#!/usr/bin/env bash
# Publish (or update) dawn-cli on the AUR.
#
# Before the first run you need an AUR account with your SSH key added to it.
# Then, on an Arch-based system:
#
#   ./aur-publish.sh
#
# Optional settings (environment variables):
#   AUR_NAME / AUR_EMAIL   name and email to put on the AUR commit. The email is PUBLIC.
#   AUR_DIR                where to keep the local AUR clone (default ~/aur/dawn-cli)
#   AUR_YES=1              don't ask for confirmation before pushing
set -euo pipefail

PKG=dawn-cli
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUR_DIR="${AUR_DIR:-$HOME/aur/$PKG}"
AUR_URL="${AUR_URL:-ssh://aur@aur.archlinux.org/$PKG.git}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v makepkg >/dev/null 2>&1 || die "makepkg not found. Run this on an Arch-based system."
command -v git >/dev/null 2>&1 || die "git not found. Install it with: sudo pacman -S git"
[ -f "$HERE/PKGBUILD" ] || die "No PKGBUILD next to this script."

pkgver="$(sed -n 's/^pkgver=//p' "$HERE/PKGBUILD")"

# 1. Check the download and checksum, and generate .SRCINFO, in a scratch folder
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$HERE/PKGBUILD" "$TMP/"
say "Checking the v$pkgver download against the checksum in the PKGBUILD"
( cd "$TMP" && makepkg --verifysource ) || die "The checksum didn't match, or the download failed. Is the v$pkgver tag pushed to GitHub? After a new release, run: updpkgsums"
say "Generating .SRCINFO"
( cd "$TMP" && makepkg --printsrcinfo > .SRCINFO )

# 2. Get a local clone of the AUR repository
if [ ! -d "$AUR_DIR/.git" ]; then
  say "Cloning $AUR_URL"
  mkdir -p "$(dirname "$AUR_DIR")"
  git clone "$AUR_URL" "$AUR_DIR" || die "Couldn't clone. Is your SSH key added to your AUR account? Test with: ssh aur@aur.archlinux.org help"
fi
cd "$AUR_DIR"

# The AUR only accepts the 'master' branch, whatever your git default is
FIRST=0
if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  FIRST=1
  git symbolic-ref HEAD refs/heads/master
fi
[ -n "${AUR_NAME:-}" ] && git config user.name "$AUR_NAME"
[ -n "${AUR_EMAIL:-}" ] && git config user.email "$AUR_EMAIL"

# 3. Commit the files
cp "$HERE/PKGBUILD" PKGBUILD
cp "$TMP/.SRCINFO" .SRCINFO
git add PKGBUILD .SRCINFO
if git diff --cached --quiet; then
  say "Nothing changed since the last publish, so there is nothing to do."
  exit 0
fi

if [ "$FIRST" -eq 1 ]; then MSG="Initial import: $PKG $pkgver"; else MSG="Update to $pkgver"; fi
git commit -q -m "$MSG"
AUTHOR="$(git log -1 --format='%an <%ae>')"

# 4. Push
say "Ready to publish '$MSG' to the AUR as: $AUTHOR"
echo "    (that name and email become public in the AUR's git history)"
if [ "${AUR_YES:-0}" != "1" ]; then
  read -r -p "    Push now? [y/N] " ans </dev/tty
  case "$ans" in
    y | Y | yes | YES) ;;
    *) echo "    Not pushed. Your commit is saved in $AUR_DIR if you want to push it later (git push origin HEAD:master)."; exit 0 ;;
  esac
fi
git push origin HEAD:master
say "Published! See https://aur.archlinux.org/packages/$PKG"
