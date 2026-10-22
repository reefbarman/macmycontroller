#!/usr/bin/env bash
# Builds build/MacMyController.app from the Swift package.
#
# Signing: set SIGN_IDENTITY to a code-signing identity name to use it. Otherwise the
# first "Apple Development" or "Developer ID Application" identity is used, falling back
# to ad-hoc signing. With ad-hoc signing macOS treats every rebuild as a new app, so the
# Accessibility permission has to be granted again after each build.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/MacMyController.app"
# Extra SwiftPM flags, e.g. SWIFTPM_FLAGS=--disable-sandbox inside another sandbox.
read -r -a EXTRA <<<"${SWIFTPM_FLAGS:-}"

swift build -c "$CONFIG" ${EXTRA[@]+"${EXTRA[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${EXTRA[@]+"${EXTRA[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MacMyController" "$APP/Contents/MacOS/MacMyController"
cp Support/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  # Ad-hoc signatures normally identify the app by its exact binary hash, so every
  # rebuild loses the Accessibility grant. Pin the designated requirement to the bundle
  # ID instead so the grant survives rebuilds. Local development only.
  codesign --force --sign - \
    -r='designated => identifier "com.reefbarman.macmycontroller"' "$APP"
  echo "note: ad-hoc signed with a bundle-ID requirement (local development only)." >&2
fi

echo "Built $APP"
