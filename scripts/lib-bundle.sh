#!/usr/bin/env bash
#
# Shared bundle-assembly helpers for the Footswitch packaging scripts.
# Source this from package-app.sh (dev, ad-hoc/Apple Development signing) and
# from the personal release scripts (notarize-release.sh / build-dmg.sh,
# Developer ID + notarization). Keeping the assembly in one place ensures every
# build path embeds the same resources — the localizations (.lproj) and the
# injected git commit hash in particular.
#
# Usage:
#   source "$(dirname "$0")/lib-bundle.sh"
#   ROOT=...; BUILD_FLAGS="-c release --arch arm64 --arch x86_64"
#   BIN="$(footswitch_build_binary "$ROOT" "$BUILD_FLAGS")"
#   footswitch_assemble_app "$ROOT" "$BIN" "$APP"
#   # then sign / notarize as appropriate to the caller.

# Build the universal release binary and echo its path.
# Args: ROOT, BUILD_FLAGS
footswitch_build_binary() {
  local root="$1" flags="$2"
  # shellcheck disable=SC2086
  swift build $flags --package-path "$root" 1>&2
  # Universal builds live under .build/apple/Products/Release; resolve via SwiftPM.
  # shellcheck disable=SC2086
  printf '%s/Footswitch' "$(swift build $flags --package-path "$root" --show-bin-path)"
}

# Assemble a complete, UNSIGNED Footswitch.app bundle: binary, Info.plist, icon,
# all .lproj localizations, and the injected git commit hash. The caller signs.
# Args: ROOT, BIN (path to built executable), APP (output .app path)
footswitch_assemble_app() {
  local root="$1" bin="$2" app="$3"
  local res="$root/Sources/Footswitch/Resources"

  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$bin" "$app/Contents/MacOS/Footswitch"
  cp "$res/Info.plist" "$app/Contents/Info.plist"
  cp "$res/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

  # Hand-managed localization folders live in the main bundle's Resources so
  # NSLocalizedString resolves them via Bundle.main.
  local lproj
  for lproj in "$res/Localizations/"*.lproj; do
    [ -e "$lproj" ] || continue
    cp -R "$lproj" "$app/Contents/Resources/"
  done

  # Inject the build's git short SHA into the packaged Info.plist's GitCommitHash
  # (the source plist ships a 0000000 placeholder for unpackaged dev runs).
  local sha
  sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo 0000000)"
  /usr/libexec/PlistBuddy -c "Set :GitCommitHash $sha" "$app/Contents/Info.plist"
}
