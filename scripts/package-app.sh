#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Footswitch.app"
BIN="$ROOT/.build/release/Footswitch"
ENTITLEMENTS="$ROOT/Footswitch.entitlements"
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

swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Footswitch"
cp "$ROOT/Sources/Footswitch/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/Footswitch/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "Signing with: $SIGN_IDENTITY (hardened runtime)"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP"

codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP"
echo "Run: open \"$APP\"  (grant Accessibility once; the grant now persists)"
