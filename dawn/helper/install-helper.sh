#!/usr/bin/env bash
# Sets up dawn's built-in macOS audio helper (dawn-audiotap) for the audio visualiser.
#
#   dawn --setup-helper            download the ready-made helper (nothing else needed)
#   install-helper.sh --from-source   build it from the Swift source instead (needs Apple's Command Line Tools)
#   install-helper.sh --no-check      don't test it afterwards
#   install-helper.sh --remove        delete the helper again
#
# By default it downloads a small ready-made helper from dawn's GitHub release and checks its checksum.
# Only if that isn't possible does it fall back to building the helper, which needs the Command Line Tools.
# Needs macOS 14.2 or newer. Installs to ~/.local/share/dawn/dawn-audiotap (override: DAWN_HELPER_DIR). No sudo.

set -euo pipefail

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/dawn-audiotap.swift"
PLIST="$HERE/Info.plist"
DEST_DIR="${DAWN_HELPER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dawn}"
DEST="$DEST_DIR/dawn-audiotap"
ASSET="dawn-audiotap-macos-universal"
# dawn passes its own version; the helper for v1.8.1 is published with the v1.8.1 release.
URL="${DAWN_HELPER_URL:-}"
if [ -z "$URL" ] && [ -n "${DAWN_VERSION:-}" ]; then
  URL="https://github.com/miron302/dawn-cli/releases/download/v$DAWN_VERSION/$ASSET"
fi
CHECK=1
FROM_SOURCE=0

for arg in "$@"; do
  case "$arg" in
    --no-check) CHECK=0 ;;
    --from-source) FROM_SOURCE=1 ;;
    --remove)
      rm -f "$DEST"
      say "Removed $DEST"
      exit 0 ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "This helper is only for macOS. On Linux the visualiser uses parec (libpulse)."

# --- macOS 14.2 or newer? -------------------------------------------------------
ver="$(sw_vers -productVersion 2>/dev/null || echo 0)"
major="${ver%%.*}"
minor=0
case "$ver" in *.*) rest="${ver#*.}"; minor="${rest%%.*}" ;; esac
if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "$minor" -lt 2 ]; }; then
  warn "macOS $ver is older than 14.2, which the built-in helper needs."
  warn "dawn can still draw the visualiser from a virtual audio device such as BlackHole: see the README."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi
}

# --- 1. Download the ready-made helper ---------------------------------------------
DL_WHY=""
try_download() {
  if [ -z "$URL" ]; then DL_WHY="I don't know which version to download"; return 1; fi
  command -v curl >/dev/null 2>&1 || { DL_WHY="curl isn't available"; return 1; }
  say "Downloading dawn's audio helper"
  if ! curl -fsSL --retry 2 --connect-timeout 10 -o "$TMP/helper" "$URL" \
     || ! curl -fsSL --retry 2 --connect-timeout 10 -o "$TMP/helper.sha256" "$URL.sha256"; then
    DL_WHY="the download failed (no internet, or this version's helper isn't published yet)"
    return 1
  fi
  local want have
  want="$(awk '{print $1}' "$TMP/helper.sha256" | head -1)"
  have="$(sha256 "$TMP/helper")"
  if [ -z "$want" ] || [ "$want" != "$have" ]; then
    DL_WHY="the download didn't match its checksum, so I threw it away"
    return 1
  fi
  chmod 755 "$TMP/helper"
  xattr -d com.apple.quarantine "$TMP/helper" >/dev/null 2>&1 || true
  if ! "$TMP/helper" --version >/dev/null 2>&1; then
    DL_WHY="the downloaded helper won't run on this Mac"
    return 1
  fi
  return 0
}

# --- 2. Or build it from source (needs the Command Line Tools) -------------------------
build_from_source() {
  [ -f "$SRC" ] || die "I can't find $SRC"
  # Ask xcrun, not PATH: without the Command Line Tools /usr/bin/swiftc is only a stub that pops up an installer.
  # To use a different Swift toolchain:   SWIFTC=/path/to/swiftc dawn --setup-helper --from-source
  SWIFTC="${SWIFTC:-$(xcrun --find swiftc 2>/dev/null || true)}"
  if [ -n "$SWIFTC" ] && [ -n "$DL_WHY" ]; then
    warn "Couldn't use the ready-made helper: $DL_WHY. Building it from source instead."
  fi
  if [ -z "$SWIFTC" ]; then
    if [ -n "$DL_WHY" ]; then
      warn "I couldn't download the ready-made helper: $DL_WHY."
      warn "Building it myself needs Apple's Command Line Tools, which aren't installed."
    else
      warn "Building the helper needs Apple's Command Line Tools (they include the Swift compiler)."
    fi
    warn "Either check your internet connection and run  dawn --setup-helper  again, or install them with:"
    warn "    xcode-select --install"
    warn "and then run  dawn --setup-helper  again."
    exit 1
  fi

  # Which macOS SDK to build against. Passing it explicitly avoids the compiler guessing wrong
  # when Xcode and the Command Line Tools are both installed or only partly set up.
  SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"

  try_build() {  # try_build <modes>: any of sdk, target, plist, separated by commas
    local mode="$1"
    local args=(-O -swift-version 5 -o "$TMP/dawn-audiotap" "$SRC")
    case "$mode" in *sdk*)
      if [ -n "$SDK" ]; then args+=(-sdk "$SDK"); fi ;;
    esac
    case "$mode" in *target*)
      args+=(-target "$(uname -m)-apple-macos14.2") ;;
    esac
    case "$mode" in *plist*)
      args+=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST") ;;
    esac
    "$SWIFTC" "${args[@]}" 2>>"$TMP/build.log"
  }

  say "Building dawn's audio helper from source (takes a few seconds)"
  local built=0 mode
  # Most precise first. Each step only runs if the one before it failed. The embedded plist is a nicety
  # (it carries the permission text), so it is the first thing to go.
  for mode in sdk,plist sdk sdk,target plain; do
    echo "--- attempt: $mode" >> "$TMP/build.log"
    if try_build "$mode"; then built=1; break; fi
  done

  if [ "$built" -eq 0 ]; then
    echo >&2
    warn "The helper didn't build. Here is what the Swift compiler said:"
    grep -i "error" "$TMP/build.log" | sort -u | head -6 >&2 || true
    echo >&2
    warn "About your setup (useful if you ask for help):"
    warn "  macOS:         $ver ($(uname -m))"
    warn "  xcode-select:  $(xcode-select -p 2>&1 | head -1)"
    warn "  compiler:      $SWIFTC"
    warn "  version:       $("$SWIFTC" --version 2>&1 | head -1)"
    warn "  SDK:           ${SDK:-not found}"
    if [ -n "$SDK" ] && [ ! -d "$SDK/usr/lib/swift" ]; then
      warn "  The SDK has no Swift standard library (usr/lib/swift is missing)."
    fi
    if grep -q -i "standard library\|SDK\|module 'Swift'\|failed to build module" "$TMP/build.log"; then
      echo >&2
      warn "That means the Swift compiler can't use your macOS SDK. It almost always means Apple's"
      warn "Command Line Tools are damaged or older than your macOS. To fix it:"
      warn "  1. Open System Settings > General > Software Update and install any"
      warn "     'Command Line Tools for Xcode' update that is offered."
      warn "  2. If there isn't one, reinstall them:"
      warn "       sudo rm -rf /Library/Developer/CommandLineTools"
      warn "       xcode-select --install"
      warn "  3. If you use the full Xcode app, make sure it is the active one:"
      warn "       sudo xcode-select -s /Applications/Xcode.app"
      warn "Then run again:   dawn --setup-helper --from-source"
    fi
    die "The helper didn't build."
  fi
  if [ "$mode" != "sdk,plist" ]; then
    say "(Built with the fallback setting '$mode'. That's fine.)"
  fi
  # A locally built helper needs a signature to run on Apple Silicon. An ad-hoc one is enough.
  codesign --force --sign - "$TMP/dawn-audiotap" >/dev/null 2>&1 || true
}

if [ "$FROM_SOURCE" -eq 0 ] && try_download; then
  cp "$TMP/helper" "$TMP/dawn-audiotap"
else
  build_from_source
fi

mkdir -p "$DEST_DIR"
cp "$TMP/dawn-audiotap" "$DEST"
chmod 755 "$DEST"
say "Installed $DEST"

# --- Test it (this is also what makes macOS ask for permission) --------------------
if [ "$CHECK" -eq 1 ]; then
  echo
  say "Testing it. macOS may now ask if your terminal can record system audio: choose Allow."
  if "$DEST" --check; then
    say "All set! Start dawn and play some music."
  else
    warn "The helper is installed but the test failed. Allow your terminal under"
    warn "System Settings > Privacy & Security > Screen & System Audio Recording,"
    warn "then restart your terminal and run:   dawn --setup-helper"
  fi
fi
