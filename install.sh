#!/usr/bin/env bash
# dawn installer for Arch-based Linux, Fedora-based Linux and macOS.
#
#   ./install.sh              install dawn plus the optional audio + now-playing helpers
#   ./install.sh --minimal    install dawn only
#
# Linux: admin rights are only needed to install missing system packages. The
# script uses sudo, doas, run0, pkexec or su (first one found, in that order).
# To pick one yourself:   PRIV_CMD=doas ./install.sh
# macOS: uses MacPorts on Intel Macs (x86_64) and Homebrew on Apple Silicon (arm64),
# picked automatically. To choose yourself:
#   ./install.sh --macports     use MacPorts (asks for your password via sudo)
#   ./install.sh --brew         use Homebrew (never run it with sudo)
set -euo pipefail

REPO="https://github.com/miron302/dawn-cli.git"
MINIMAL=0
MAC_PM=""  # macports or homebrew; empty means pick by CPU

usage() {
  cat <<'EOF'
dawn installer for Arch-based Linux, Fedora-based Linux and macOS.

  install.sh              install dawn plus the optional audio + now-playing helpers
  install.sh --minimal    install dawn only
  PRIV_CMD=doas install.sh   (Linux) force a specific tool for admin rights (sudo, doas, run0, pkexec, su)

macOS picks MacPorts on Intel Macs (x86_64) and Homebrew on Apple Silicon (arm64) by itself.
  install.sh --macports   use MacPorts instead
  install.sh --brew       use Homebrew instead
EOF
}

for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=1 ;;
    --macports) MAC_PM=macports ;;
    --brew | --homebrew) MAC_PM=homebrew ;;
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

# --- macOS: MacPorts (Intel) or Homebrew (Apple Silicon) --------------------
if [ "$(uname -s)" = "Darwin" ]; then
  say "Installing dawn on macOS"

  # Real hardware, even when this terminal runs under Rosetta
  if [ "$(uname -m)" = "arm64" ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = "1" ]; then
    MAC_ARCH=arm64
  else
    MAC_ARCH=x86_64
  fi

  if [ -z "$MAC_PM" ]; then
    if [ "$MAC_ARCH" = "arm64" ]; then MAC_PM=homebrew; else MAC_PM=macports; fi
    say "Detected an $MAC_ARCH Mac, so I'll use $( [ "$MAC_PM" = macports ] && echo MacPorts || echo Homebrew )"
  else
    say "Using $( [ "$MAC_PM" = macports ] && echo MacPorts || echo Homebrew ) (your choice)"
  fi

  # The package manager may be installed but not on PATH yet
  if [ "$MAC_PM" = "macports" ]; then
    have port || { [ -x /opt/local/bin/port ] && export PATH="/opt/local/bin:/opt/local/sbin:$PATH"; } || true
    if ! have port; then
      msg="MacPorts isn't installed. Install it from https://www.macports.org/install.php (it needs Xcode or the Command Line Tools), open a NEW terminal and run this again."
      if have brew || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
        msg="$msg Homebrew is installed, so you can also run this with --brew."
      fi
      die "$msg"
    fi
  else
    if ! have brew; then
      for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
      done
    fi
    if ! have brew; then
      msg="Homebrew isn't installed. Install it from https://brew.sh, open a NEW terminal and run this again."
      if have port || [ -x /opt/local/bin/port ]; then
        msg="$msg MacPorts is installed, so you can also run this with --macports."
      fi
      die "$msg"
    fi
    if [ "$(id -u)" -eq 0 ]; then
      die "Don't run this as root or with sudo: Homebrew refuses to work that way. Run it as your normal user."
    fi
  fi

  mac_install() {
    if [ "$MAC_PM" = "macports" ]; then as_root port -N install "$@"; else brew install "$@"; fi
  }

  need=()
  have git  || need+=(git)
  have pipx || need+=(pipx)
  if [ "${#need[@]}" -gt 0 ]; then
    say "Installing required packages: ${need[*]}"
    mac_install "${need[@]}" || die "Couldn't install ${need[*]}."
  fi

  if [ "$MINIMAL" -eq 0 ]; then
    extras=()
    have ffmpeg || extras+=(ffmpeg)  # audio visualiser
    # Now Playing for apps besides Spotify and Apple Music. Not every package manager has it.
    if ! have nowplaying-cli; then
      if [ "$MAC_PM" = "macports" ]; then
        port info nowplaying-cli >/dev/null 2>&1 && extras+=(nowplaying-cli)
      else
        extras+=(nowplaying-cli)
      fi
    fi
    if [ "${#extras[@]}" -gt 0 ]; then
      say "Installing optional helpers (audio visualiser + Now Playing): ${extras[*]}"
      [ "$MAC_PM" = "macports" ] && warn "MacPorts may build these from source, which can take a while."
      mac_install "${extras[@]}" || warn "Couldn't install the optional helpers. dawn still works without them."
    fi
  fi

  if [ -f pyproject.toml ] && grep -q 'name = "dawn-cli"' pyproject.toml 2>/dev/null; then
    SOURCE=.
  else
    SOURCE="git+${REPO}"
  fi
  pipx install --force "$SOURCE" || die "pipx failed, so dawn was not installed. That error comes from pipx, not from dawn."
  pipx ensurepath >/dev/null 2>&1 || true

  echo
  say "All done! Open a NEW terminal window and type:  dawn"
  echo "    Try:  dawn --media     (Now Playing tab)    dawn --procs     (process viewer)"
  echo
  warn "Use iTerm2, Ghostty, kitty, WezTerm or Alacritty. The built-in Terminal.app only has 256 colours."
  if [ "$MINIMAL" -eq 0 ]; then
    echo "    Audio visualiser (optional): macOS can't share the sound it is playing, so it needs a virtual"
    echo "    audio device such as BlackHole. Everything else in dawn works without it. If you don't want it,"
    echo "    run:  dawn --no-viz --save     Setup and options: see 'The audio visualiser' in the README."
  fi
  exit 0
fi

if [ -n "$MAC_PM" ]; then
  warn "--macports and --brew only apply to macOS. Ignoring."
fi

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
  # pipx imports 'filelock' when it installs something. On some Arch systems it
  # isn't pulled in, and pipx then crashes with "No module named 'filelock'".
  if [ "$PM" = pacman ] && ! pacman -Qq python-filelock >/dev/null 2>&1; then
    need+=(python-filelock)
  fi
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
  SOURCE=.
else
  SOURCE="git+${REPO}"
fi

if ! pipx install --force "$SOURCE"; then
  echo >&2
  warn "pipx failed, so dawn was not installed. That error comes from pipx, not from dawn."
  warn "If it said \"No module named 'filelock'\", install it and run this again:"
  warn "    Arch-based:   sudo pacman -S python-filelock"
  warn "    Fedora-based: sudo dnf install python3-filelock"
  exit 1
fi

pipx ensurepath >/dev/null 2>&1 || true

echo
say "All done! Open a NEW terminal window and type:  dawn"
echo "    Try:  dawn --media     (Now Playing tab)    dawn --procs     (process viewer)"
