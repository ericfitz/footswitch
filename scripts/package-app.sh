#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Footswitch.app"
ENTITLEMENTS="$ROOT/Footswitch.entitlements"
BUILD_FLAGS="-c release --arch arm64 --arch x86_64"
SIGNING_ENV="$ROOT/scripts/signing.env"

# Local signing config lives in an untracked scripts/signing.env (created by
# scripts/setup-signing.sh). It must define SIGN_IDENTITY. We sign dev builds
# with a stable "Apple Development" identity so the Accessibility (TCC) grant
# persists across rebuilds and relaunches — ad-hoc signatures have no stable
# identity, so macOS treats every launch as a new app and the grant never sticks.
if [ -f "$SIGNING_ENV" ]; then
  # shellcheck disable=SC1090
  source "$SIGNING_ENV"
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
  echo "error: SIGN_IDENTITY is not set." >&2
  echo "Run scripts/setup-signing.sh to create scripts/signing.env, or export" >&2
  echo "SIGN_IDENTITY=\"Apple Development: Your Name (TEAMID)\" before running." >&2
  exit 1
fi

# shellcheck disable=SC2086
swift build $BUILD_FLAGS --package-path "$ROOT"
# Resolve the product dir from SwiftPM (universal builds live under
# .build/apple/Products/Release, not .build/release).
# shellcheck disable=SC2086
BIN="$(swift build $BUILD_FLAGS --package-path "$ROOT" --show-bin-path)/Footswitch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Footswitch"
cp "$ROOT/Sources/Footswitch/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/Footswitch/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Copy hand-managed localization folders into the app bundle (.lproj live in the
# main bundle's Resources so NSLocalizedString resolves them via Bundle.main).
for lproj in "$ROOT/Sources/Footswitch/Resources/Localizations/"*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done

# Inject the build's git short SHA into the packaged Info.plist's GitCommitHash
# (the source plist ships a 0000000 placeholder for unpackaged dev runs).
GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 0000000)"
/usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_SHA" "$APP/Contents/Info.plist"

echo "Signing with: $SIGN_IDENTITY (hardened runtime)"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP"

codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP"
echo "Run: open \"$APP\"  (grant Accessibility once; the grant now persists)"
