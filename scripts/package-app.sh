#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Footswitch.app"
ENTITLEMENTS="$ROOT/Footswitch.entitlements"
BUILD_FLAGS="-c release --arch arm64 --arch x86_64"
SIGNING_ENV="$ROOT/scripts/signing.env"

# Shared bundle-assembly helpers (build binary + assemble .app incl. .lproj + SHA).
# shellcheck source=lib-bundle.sh
source "$(dirname "$0")/lib-bundle.sh"

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

# Lint before building a release. SwiftLint is optional for local dev, so skip
# cleanly if it isn't installed; when present, any violation fails the build.
if command -v swiftlint >/dev/null 2>&1; then
  echo "Linting with SwiftLint (strict)…"
  swiftlint lint --strict --quiet "$ROOT"
else
  echo "note: swiftlint not found — skipping lint (brew install swiftlint to enable)." >&2
fi

BIN="$(footswitch_build_binary "$ROOT" "$BUILD_FLAGS")"
footswitch_assemble_app "$ROOT" "$BIN" "$APP"

echo "Signing with: $SIGN_IDENTITY (hardened runtime)"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP"

codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP"
echo "Run: open \"$APP\"  (grant Accessibility once; the grant now persists)"
