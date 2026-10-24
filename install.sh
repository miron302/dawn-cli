#!/usr/bin/env bash
# dawn installer for Arch Linux (and friends)
set -euo pipefail

REPO="https://github.com/miron302/dawn-cli.git"

echo "==> Installing dawn"

if ! command -v pipx >/dev/null 2>&1; then
  if command -v pacman >/dev/null 2>&1; then
    echo "==> Installing pipx and git (needs your password)"
    sudo pacman -S --needed --noconfirm python-pipx git
  else
    echo "Please install pipx first: https://pipx.pypa.io" >&2
    exit 1
  fi
fi

# When run from inside a cloned copy, install that; otherwise install from GitHub.
if [ -f "pyproject.toml" ] && grep -q 'name = "dawn-cli"' pyproject.toml 2>/dev/null; then
  pipx install --force .
else
  pipx install --force "git+${REPO}"
fi

pipx ensurepath >/dev/null 2>&1 || true

echo
echo "All done! Open a NEW terminal window and type:  dawn"
