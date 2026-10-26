#!/usr/bin/env bash
# dawn installer for Arch-based and Fedora-based Linux.
#
#   ./install.sh              install dawn plus the optional audio + now-playing helpers
#   ./install.sh --minimal    install dawn only
#
# Admin rights are only needed to install missing system packages. The script
# uses sudo, doas, run0, pkexec or su (first one found, in that order).
# To pick one yourself:   PRIV_CMD=doas ./install.sh
set -euo pipefail

REPO="https://github.com/miron302/dawn-cli.git"
MINIMAL=0

usage() {
  cat <<'EOF'
dawn installer for Arch-based and Fedora-based Linux.

  install.sh              install dawn plus the optional audio + now-playing helpers
  install.sh --minimal    install dawn only
  PRIV_CMD=doas install.sh   force a specific tool for admin rights (sudo, doas, run0, pkexec, su)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=1 ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 1 ;;
  esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- How do we get admin rights? ------------------------------------------
PRIV=()
if [ "$(id -u)" -ne 0 ]; then
  if [ -n "${PRIV_CMD:-}" ]; then
    read -r -a PRIV <<<"$PRIV_CMD"
    have "${PRIV[0]}" || die "PRIV_CMD is '${PRIV_CMD}', but '${PRIV[0]}' isn't installed."
  else
    for tool in sudo doas run0 pkexec su; do
      if have "$tool"; then
        PRIV=("$tool")
        break
      fi
    done
  fi
fi

as_root() {
  if [ "${#PRIV[@]}" -eq 0 ]; then
    if [ "$(id -u)" -eq 0 ]; then
      "$@"
    else
      die "I need admin rights to install packages, but found none of: sudo, doas, run0, pkexec, su."
    fi
  elif [ "${PRIV[0]}" = "su" ]; then
    su -c "$(printf '%q ' "$@")"
  else
    "${PRIV[@]}" "$@"
  fi
}

# --- Which package manager? -------------------------------------------------
PM=""
if have pacman; then
  PM=pacman
elif have dnf; then
  PM=dnf
fi

install_pkgs() {
  case "$PM" in
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    dnf)    as_root dnf install -y "$@" ;;
  esac
}

say "Installing dawn"

if [ -z "$PM" ]; then
  if ! { have git && have pipx; }; then
    die "I can install packages on Arch-based (pacman) and Fedora-based (dnf) systems only. Install git and pipx yourself, then run this again."
  fi
  if [ "$MINIMAL" -eq 0 ]; then
    warn "Skipping the optional helpers. For the audio visualiser install 'parec', and for Now Playing install 'playerctl'."
  fi
else
  case "$PM" in
    pacman) PKG_PIPX=python-pipx; PKG_PAREC=libpulse ;;
    dnf)    PKG_PIPX=pipx;        PKG_PAREC=pulseaudio-utils ;;
  esac

  need=()
  have git  || need+=(git)
  have pipx || need+=("$PKG_PIPX")
  if [ "${#need[@]}" -gt 0 ]; then
    say "Installing required packages: ${need[*]}"
    install_pkgs "${need[@]}"
  fi

  if [ "$MINIMAL" -eq 0 ]; then
    extras=()
    have parec     || extras+=("$PKG_PAREC")
    have playerctl || extras+=(playerctl)
    if [ "${#extras[@]}" -gt 0 ]; then
      say "Installing optional helpers (audio visualiser + Now Playing): ${extras[*]}"
      install_pkgs "${extras[@]}" || warn "Couldn't install the optional helpers. dawn still works without them."
    fi
  fi
fi

# --- Install dawn itself ----------------------------------------------------
# From inside a cloned copy install that, otherwise install from GitHub.
if [ -f pyproject.toml ] && grep -q 'name = "dawn-cli"' pyproject.toml 2>/dev/null; then
  pipx install --force .
else
  pipx install --force "git+${REPO}"
fi

pipx ensurepath >/dev/null 2>&1 || true

echo
say "All done! Open a NEW terminal window and type:  dawn"
echo "    Try:  dawn --media     (Now Playing tab)    dawn --procs     (process viewer)"
