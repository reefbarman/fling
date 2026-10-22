#!/usr/bin/env bash
# Builds a Release copy of Fling and packages it as a zip and a dmg in dist/.
#
#   Scripts/package-release.sh 0.2.0
#
# Signing: ad-hoc by default. Set FLING_SIGN_IDENTITY to a codesigning identity
# (full name or SHA-1) to sign with a real certificate instead. Neither option
# is notarised, so downloaded copies need right-click > Open on first launch.
set -euo pipefail

VERSION="${1:?usage: $0 <version, e.g. 0.2.0>}"
BUILD_NUMBER="${FLING_BUILD_NUMBER:-1}"
IDENTITY="${FLING_SIGN_IDENTITY:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build/ReleaseDerivedData"
APP="$DERIVED/Build/Products/Release/Fling.app"
DIST="dist"
NAME="Fling-$VERSION"

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

xcodegen generate

# Universal (arm64 + x86_64) Release build. Xcode signs ad-hoc here; the real
# signature, if any, is applied below so it covers the final bundle.
xcodebuild \
  -project Fling.xcodeproj \
  -scheme Fling \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

if [ "$IDENTITY" != "-" ]; then
  if [ -n "${FLING_SIGN_KEYCHAIN:-}" ]; then
    codesign --force --sign "$IDENTITY" --keychain "$FLING_SIGN_KEYCHAIN" --timestamp=none "$APP"
  else
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
  fi
fi

codesign --verify --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signature)=' || true
lipo -archs "$APP/Contents/MacOS/Fling"

# zip: ditto keeps the bundle's metadata and symlinks intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

# dmg: the app next to an Applications shortcut for drag-to-install.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Fling $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DIST/$NAME.dmg"

(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt)

echo "Packaged:"
ls -lh "$DIST"
