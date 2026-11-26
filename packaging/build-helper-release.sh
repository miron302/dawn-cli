#!/usr/bin/env bash
# Builds the release version of dawn's macOS audio helper: ONE file that runs on both Apple Silicon and
# Intel Macs, plus its SHA-256 checksum. Users download this instead of compiling anything.
#
#   packaging/build-helper-release.sh
#
# Output (in dist/):  dawn-audiotap-macos-universal   dawn-audiotap-macos-universal.sha256
# Attach both files to the GitHub release for the same version (v1.8.1 for dawn 1.8.1).
# The GitHub Action in .github/workflows/helper.yml does all of this when you push a version tag.
# Needs a Mac with Apple's Command Line Tools. The Intel half is cross-built, so any Mac will do.

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="dawn/helper/dawn-audiotap.swift"
PLIST="dawn/helper/Info.plist"
NAME="dawn-audiotap-macos-universal"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for arch in arm64 x86_64; do
  echo "==> Building $arch"
  xcrun swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos14.2" -o "$TMP/$arch" "$SRC" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST"
done

mkdir -p dist
rm -f "dist/$NAME" "dist/$NAME.sha256"
lipo -create -output "dist/$NAME" "$TMP/arm64" "$TMP/x86_64"
# lipo breaks signatures, so sign after it. Apple Silicon refuses to run unsigned code; an ad-hoc signature is enough.
codesign --force --sign - "dist/$NAME"
chmod 755 "dist/$NAME"
(cd dist && shasum -a 256 "$NAME" | awk '{print $1}' > "$NAME.sha256")

echo "==> Checking it"
lipo -info "dist/$NAME"
"dist/$NAME" --version
echo "==> Done. Attach these two files to the release:"
ls -l "dist/$NAME" "dist/$NAME.sha256"
