#!/usr/bin/env bash
# dawn installer for Arch-based Linux, Fedora-based Linux and macOS.
#
#   ./install.sh              install dawn plus the optional audio + now-playing helpers
#   ./install.sh --minimal    install dawn only
#
# Linux: admin rights are only needed to install missing system packages. The
# script uses sudo, doas, run0, pkexec or su (first one found, in that order).
# To pick one yourself:   PRIV_CMD=doas ./install.sh
# macOS: if the Mac already has Python 3.9+ (Apple's Command Line Tools include it), dawn is installed
# with that and no package manager at all. Otherwise it uses MacPorts on Intel Macs (x86_64) and Homebrew
# on Apple Silicon (arm64), picked automatically. To choose yourself:
#   ./install.sh --light        use the Python already on the Mac, no package manager
#   ./install.sh --macports     use MacPorts (asks for your password via sudo)
#   ./install.sh --brew         use Homebrew (never run it with sudo)
set -euo pipefail

REPO="https://github.com/miron302/dawn-cli.git"
MINIMAL=0
MAC_PM=""  # macports or homebrew; empty means pick by CPU
MAC_LIGHT=""  # 1 = use the Mac's own Python and no package manager, 0 = use a package manager, empty = decide automatically

usage() {
  cat <<'EOF'
dawn installer for Arch-based Linux, Fedora-based Linux and macOS.

  install.sh              install dawn plus the optional audio + now-playing helpers
  install.sh --minimal    install dawn only
  PRIV_CMD=doas install.sh   (Linux) force a specific tool for admin rights (sudo, doas, run0, pkexec, su)

On macOS, if the Mac already has Python 3.9+ dawn installs with it and needs no package manager.
Otherwise it picks MacPorts on Intel Macs (x86_64) and Homebrew on Apple Silicon (arm64) by itself.
  install.sh --light      use the Python already on the Mac, no package manager
  install.sh --macports   use MacPorts instead
  install.sh --brew       use Homebrew instead
EOF
}

for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=1 ;;
    --light) MAC_LIGHT=1 ;;
    --macports) MAC_PM=macports; MAC_LIGHT=0 ;;
    --brew | --homebrew) MAC_PM=homebrew; MAC_LIGHT=0 ;;
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

  # dawn's built-in audio helper needs macOS 14.2 or newer
  mac_ver="$(sw_vers -productVersion 2>/dev/null || echo 0)"
  if awk -v v="$mac_ver" 'BEGIN { split(v, a, "."); exit !(a[1] > 14 || (a[1] == 14 && a[2] >= 2)) }'; then
    MAC_HELPER=1
  else
    MAC_HELPER=0
  fi

  # A usable Python 3.9+ that is already on this Mac. Apple's /usr/bin/python3 is only a stub that pops up
  # an installer when the Command Line Tools are missing, so it only counts if they are installed.
  find_mac_python() {
    local cand path
    for cand in python3.13 python3.12 python3.11 python3.10 python3.9 python3; do
      path="$(command -v "$cand" 2>/dev/null || true)"
      [ -n "$path" ] || continue
      case "$path" in /usr/bin/*) xcode-select -p >/dev/null 2>&1 || continue ;; esac
      if "$path" -c 'import sys, venv, ensurepip; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
        echo "$path"
        return 0
      fi
    done
    return 1
  }

  MAC_PY=""
  if [ "$MAC_LIGHT" != "0" ]; then MAC_PY="$(find_mac_python || true)"; fi
  if [ "$MAC_LIGHT" = "1" ] && [ -z "$MAC_PY" ]; then
    die "--light needs Python 3.9 or newer, and I couldn't find one. Apple's Command Line Tools include it: run  xcode-select --install  and try again. Or leave out --light to use Homebrew or MacPorts."
  fi

  # Lets a new terminal find `dawn` when it lives in ~/.local/bin
  ensure_bin_on_path() {
    case ":$PATH:" in *":$HOME/.local/bin:"*) return 0 ;; esac
    local profile
    case "${SHELL:-}" in
      */zsh)  profile="$HOME/.zprofile" ;;
      */bash) profile="$HOME/.bash_profile" ;;
      *)      profile="$HOME/.profile" ;;
    esac
    if ! grep -qs '\.local/bin' "$profile" 2>/dev/null; then
      printf '\n# added by the dawn installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
      say "Added ~/.local/bin to your PATH in $profile"
    fi
  }

  if [ -n "$MAC_PY" ]; then
    # --- Light install: the Mac's own Python, a private environment, no package manager ---
    MAC_MODE=light
    say "Using the Python already on your Mac ($MAC_PY), so no package manager is needed"
    DAWN_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/dawn"
    VENV="$DAWN_HOME/venv"
    BIN_DIR="$HOME/.local/bin"
    if [ -f pyproject.toml ] && grep -q 'name = "dawn-cli"' pyproject.toml 2>/dev/null; then
      SOURCE=.
    elif have git && { [ "$(command -v git)" != "/usr/bin/git" ] || xcode-select -p >/dev/null 2>&1; }; then
      SOURCE="git+${REPO}"
    else
      SOURCE="${REPO%.git}/archive/refs/heads/main.tar.gz"  # no git needed
    fi
    rm -rf "$VENV"
    mkdir -p "$DAWN_HOME" "$BIN_DIR"
    "$MAC_PY" -m venv "$VENV" || die "I couldn't create dawn's private Python environment in $VENV."
    say "Installing dawn (a small download)"
    # Apple's bundled Python comes with an old pip, so refresh pip inside dawn's own environment first (optional)
    "$VENV/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip >/dev/null 2>&1 || true
    "$VENV/bin/python" -m pip install --disable-pip-version-check --quiet "$SOURCE" \
      || die "pip couldn't install dawn, so dawn was not installed. That error comes from pip, not from dawn."
    ln -sf "$VENV/bin/dawn" "$BIN_DIR/dawn"
    ensure_bin_on_path
  else
    # --- Package manager install: MacPorts (Intel) or Homebrew (Apple Silicon) ---
    MAC_MODE=pm
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
      # ffmpeg is only the old-macOS route to the visualiser (a virtual audio device); 14.2+ uses dawn's own helper
      if [ "$MAC_HELPER" -eq 0 ]; then
        have ffmpeg || extras+=(ffmpeg)
      fi
      # Spotify and Apple Music work in Now Playing with nothing extra, so nowplaying-cli (for other apps, and
      # broken by Apple on macOS 15.4+ anyway) is no longer installed by default.
      if [ "${#extras[@]}" -gt 0 ]; then
        say "Installing optional helpers: ${extras[*]}"
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
  fi

  # dawn's built-in audio helper for the visualiser (a small download)
  HELPER_BUILT=0
  if [ "$MINIMAL" -eq 0 ] && [ "$MAC_HELPER" -eq 1 ]; then
    DAWN_BIN="$(command -v dawn || true)"
    if [ -z "$DAWN_BIN" ]; then
      bindir="$(pipx environment --value PIPX_BIN_DIR 2>/dev/null || true)"
      if [ -n "$bindir" ] && [ -x "$bindir/dawn" ]; then DAWN_BIN="$bindir/dawn"; fi
    fi
    if [ -z "$DAWN_BIN" ] && [ -x "$HOME/.local/bin/dawn" ]; then DAWN_BIN="$HOME/.local/bin/dawn"; fi
    if [ -n "$DAWN_BIN" ]; then
      say "Setting up dawn's built-in audio helper for the visualiser"
      if "$DAWN_BIN" --setup-helper; then
        HELPER_BUILT=1
      else
        warn "The audio helper wasn't set up. dawn works fine without it; run  dawn --setup-helper  to try again."
      fi
    else
      warn "Couldn't find the dawn command to set up the audio helper. Open a new terminal and run:  dawn --setup-helper"
    fi
  fi

  echo
  say "All done! Open a NEW terminal window and type:  dawn"
  echo "    Try:  dawn --media     (Now Playing tab)    dawn --procs     (process viewer)"
  echo
  warn "Use iTerm2, Ghostty, kitty, WezTerm or Alacritty. The built-in Terminal.app only has 256 colours."
  if [ "$MAC_MODE" = "light" ]; then
    echo "    dawn lives in $VENV. To update it later, run this installer again."
  fi
  if [ "$MINIMAL" -eq 1 ]; then
    echo "    Audio visualiser: skipped (--minimal). On macOS 14.2+ run  dawn --setup-helper  to add it."
  elif [ "$MAC_HELPER" -eq 0 ]; then
    echo "    Audio visualiser: macOS $mac_ver is older than 14.2, so dawn's built-in helper can't be used."
    echo "    It can read a virtual audio device such as BlackHole (and ffmpeg) instead: see the README."
  elif [ "$HELPER_BUILT" -eq 1 ]; then
    echo "    Audio visualiser: ready. If the bars stay flat while music plays, allow your terminal under"
    echo "    System Settings > Privacy & Security > Screen & System Audio Recording."
  fi
  exit 0
fi

if [ -n "$MAC_PM" ] || [ -n "$MAC_LIGHT" ]; then
  warn "--light, --macports and --brew only apply to macOS. Ignoring."
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
