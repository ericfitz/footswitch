# About Dialog + Localization — Design

Date: 2026-05-31
Status: Approved (pending written-spec review)

## Goal

Add two features to the Footswitch macOS menu-bar app:

1. A custom **About window** (icon, name, version+commit, description, repo link,
   "Report a problem" link, license link, copyright).
2. **Localization infrastructure** with four locales chosen to stress-test the UI:
   `en` (US English, authoritative Base), `ar` (Arabic — RTL), `zh-Hans`
   (Simplified Chinese — non-Roman/CJK), `de` (German — long words). English is
   the authoritative language; other locales are backfilled whenever English
   strings change.

## Context

- SwiftPM macOS app, Swift 6, AppKit + a little SwiftUI. `LSUIElement` (no Dock icon).
- The `.app` is assembled by `scripts/package-app.sh`, which hand-copies
  `Info.plist` and `AppIcon.icns` into `Contents/`. SwiftPM resource bundling is
  deliberately bypassed for these artifacts (see comment in `Package.swift`).
- User-facing strings currently live as inline literals in
  `Sources/Footswitch/MenuBarController.swift` and
  `Sources/Footswitch/SettingsView.swift`. No `.lproj` infrastructure exists yet.

## Chosen approach

**Centralized string keys + dedicated About module.** Introduce one `L10n.swift`
namespace wrapping `NSLocalizedString` so every key has exactly one definition and
one authoritative English comment. Put the About window in its own
`AboutWindowController.swift`. This matches the codebase's small, single-purpose-file
style and gives a single auditable inventory of every user-facing string — which is
what makes the RTL/CJK/German layout audit tractable.

Rejected alternatives:
- *Inline `NSLocalizedString` everywhere* — scatters keys, no inventory, bloats
  `MenuBarController`.
- *SwiftPM resource bundle (`Bundle.module`)* — adds a nested resource bundle the app
  must locate at runtime; the existing Package.swift comment shows this path is finicky here.
- *String Catalog `.xcstrings`* — designed for Xcode-driven builds; needs extra
  `xcstringstool` tooling in a pure `swift build` + manual-packaging pipeline.

---

## Section 1 — Localization infrastructure

### File layout (committed source of truth)

```
Sources/Footswitch/Resources/Localizations/
  en.lproj/Localizable.strings       ← Base / authoritative (English US)
  ar.lproj/Localizable.strings       ← Arabic (RTL)
  zh-Hans.lproj/Localizable.strings  ← Simplified Chinese (CJK)
  de.lproj/Localizable.strings       ← German (long words)
```

These `.lproj` folders are **excluded** from the SwiftPM resource bundle (the same
treatment Info.plist/icns already get) and are copied into
`Footswitch.app/Contents/Resources/<lang>.lproj/` by `package-app.sh`.

### Access in code

- One `Sources/Footswitch/L10n.swift` namespace. Every key is accessed through a
  static accessor (or a thin `L10n.string(_:comment:)` wrapper) calling
  `NSLocalizedString(key, comment:)` against `Bundle.main`.
- Because the strings live in the **main** bundle's `Contents/Resources/<lang>.lproj/`,
  default `Bundle.main` resolution works in the packaged app with no custom bundle helper.
- Interpolated strings become **positional format strings** (`"%1$@ → %2$@"`,
  `"%@"`) so translators can reorder arguments (critical for Arabic/German).
  Composition uses `String(format: L10n.x, a, b)`.

### Info.plist additions

- `CFBundleDevelopmentRegion` = `en`
- `CFBundleLocalizations` = `[en, ar, zh-Hans, de]`

### Translator comments (English is authoritative)

- The canonical context note is the **`comment:` argument** of each
  `NSLocalizedString` call in `L10n.swift` (e.g. `// Menu item: quit the app entirely.`).
- The same note is mirrored as a `/* comment */` header above each entry in
  **every** locale file (English text in all four), so a translator opening any
  `.lproj` sees the English context inline:
  ```
  /* Menu item: quit the application entirely. */
  "menu.quit" = "Footswitch beenden";
  ```
- Workflow when English changes: update `L10n.swift` comment + `en` value →
  propagate comment + fresh translation to `ar`, `zh-Hans`, `de`.

### Testing boundary

- `swift test` runs **without** the `.app` bundle, so unit tests must NOT assert on
  translated output.
- Tests assert structural parity instead: every key present in `en` exists in
  `ar/zh-Hans/de`, and positional-placeholder counts match across all four locales.
- A small parity check (test or script) reads the four `.strings` files and verifies
  key sets and `%N$@` arity agree.

---

## Section 2 — About window

### Structure

- New `Sources/Footswitch/AboutWindowController.swift`: a `@MainActor`
  `NSWindowController` (or window factory mirroring `SettingsWindowFactory`).
- `AppDelegate` retains a single instance (like `settingsWindow`) so re-opening reuses it.
- `MenuBarController` gains an **About Footswitch** menu item, wired via an
  `openAbout` closure (same pattern as `openSettings`).
- Menu order becomes: **About Footswitch** / separator / `Settings…` / `Quit Footswitch`
  (About added above Settings).
- Window is non-resizable: `styleMask = [.titled, .closable]`, like Settings.

### Layout (vertical centered NSStackView, ~360pt wide)

- App icon (64×64) from the bundle.
- App name "Footswitch" (bold).
- Version line — `Version 1.0.1 (abcdef10)` — from `CFBundleShortVersionString`,
  the new `GitCommitHash` Info.plist key. (Format localized; values not.)
  Note: `CFBundleVersion` (build number) is intentionally not shown — the commit
  hash supersedes it for identifying a build.
- One-line description (localized).
- Copyright line (localized).
- Horizontal row of borderless link-style `NSButton`s, opened with
  `NSWorkspace.shared.open`:
  - **View on GitHub** → `https://github.com/ericfitz/footswitch`
  - **Report a problem** → prefilled new-issue URL (below)
  - **License** → `https://github.com/ericfitz/footswitch/blob/main/LICENSE`

### Version / commit injection

- Source `Info.plist` gains `<key>GitCommitHash</key><string>0000000</string>`
  as a placeholder.
- `package-app.sh` rewrites it to `git rev-parse --short HEAD` in the **copied**
  Info.plist at package time (PlistBuddy/`plutil`; back up then delete the backup
  per the repo's CLI-edit rule).
- Dev `swift run` (unpackaged) shows the `0000000` placeholder — acceptable and
  clearly identifiable as an unpackaged build.

### Report-a-problem URL

`https://github.com/ericfitz/footswitch/issues/new?labels=bug&body=<url-encoded body>`

Body is an **English** template (GitHub issues are English; not localized):

```
**Describe the problem:**


**Environment (auto-filled):**
- Footswitch version: 1.0.1 (abcdef10)
- macOS: <ProcessInfo.processInfo.operatingSystemVersionString>
- Architecture: <arm64 | x86_64, from utsname>
```

Only the **button titles** are localized; the URL and issue-body template are not.

### RTL note

The link row is a horizontal `NSStackView` (AppKit mirrors it under Arabic). The
version/commit line stays LTR-readable (mostly digits).

---

## Section 3 — String inventory

All user-facing literals are extracted. Interpolated values use positional
format specifiers. Status-symbol glyphs (`✓ ⚠ ✗ ⊘`) and `KeyComboFormatter`
glyph output (⌘⇧ etc.) are locale-neutral and stay literal; only adjacent text is localized.

### MenuBarController.swift

| Key | English |
|---|---|
| `menu.about` | `About Footswitch` |
| `menu.settings` | `Settings…` |
| `menu.quit` | `Quit Footswitch` |
| `menu.needsPermission` | `⚠️ Needs Accessibility permission` |
| `menu.lastFire` | `Last: %1$@ → %2$@` |
| `menu.noPresses` | `No presses yet` |
| `action.dictation` | `dictation` |
| `action.none` | `no action` |
| `app.unknown` | `unknown` |

### SettingsView.swift

| Key | English |
|---|---|
| `settings.windowTitle` | `Footswitch Settings` |
| `settings.header.device` | `Foot switch` |
| `settings.header.default` | `Default action` |
| `settings.header.rules` | `App rules` |
| `settings.dictationCheckbox` | `Start dictation when no app rule matches` |
| `settings.rulesHint` | `Press the pedal in an app below to send its shortcut. Other apps use the default action above.` |
| `settings.programButton` | `Program pedal` |
| `settings.col.application` | `Application` |
| `settings.col.shortcut` | `Shortcut` |
| `device.none` | `No supported foot switch detected` |
| `device.detected` | `Detected pedal: %@` |
| `device.config.verified` | `Verified configuration` |
| `device.config.mismatch` | `Configuration must be updated` |
| `device.config.unreadable` | `Unable to read configuration` |
| `alert.deviceInfo.title` | `Foot switch information` |
| `alert.deviceInfo.none` | `No supported foot switch is connected.` |
| `alert.footswitch.title` | `Foot switch` |
| `alert.programmed` | `Programmed the foot switch to send %@.` |
| `alert.programFailed` | `Could not program the foot switch.\n\n%@` |
| `alert.ok` | `OK` |
| `openPanel.title` | `Choose an application` |
| `capture.clickToSet` | `Click to set` |
| `capture.pressShortcut` | `Press shortcut…` |
| `capture.unsupportedKey` | `Unsupported key` |
| `capture.addModifier` | `Add a modifier (⌘⌥⌃⇧)` |

### AboutWindowController.swift (new)

| Key | English |
|---|---|
| `about.windowTitle` | `About Footswitch` |
| `about.description` | `Map your USB foot switch to keyboard shortcuts, per app.` |
| `about.version` | `Version %1$@ (%2$@)` |
| `about.copyright` | `© 2026 Eric Fitzgerald` |
| `about.viewOnGitHub` | `View on GitHub` |
| `about.reportProblem` | `Report a problem` |
| `about.license` | `License` |

### RTL audit checklist (Arabic, verify visually)

- `statusLine()` symbol-then-text ordering in `SettingsView`.
- `detectedRow` / `configRow` horizontal stacks.
- About window link row.
- Table column order (Application / Shortcut).
- `ShortcutCaptureView` label alignment.

---

## Packaging changes (`scripts/package-app.sh`)

1. Copy `Sources/Footswitch/Resources/Localizations/*.lproj` into
   `Footswitch.app/Contents/Resources/`.
2. Rewrite `GitCommitHash` in the copied `Contents/Info.plist` to the short SHA.

(`build-dmg.sh` / `notarize-release.sh` call `package-app.sh`, so they inherit both.)

## Out of scope

- Native review of `ar`/`zh-Hans`/`de` translations (flagged for later).
- Additional locales beyond the four chosen.
- Localizing the GitHub issue-body template (intentionally English).
- Localizing `KeyComboFormatter` glyph output.

## Affected / new files

- New: `Sources/Footswitch/L10n.swift`
- New: `Sources/Footswitch/AboutWindowController.swift`
- New: `Sources/Footswitch/Resources/Localizations/{en,ar,zh-Hans,de}.lproj/Localizable.strings`
- Edit: `Sources/Footswitch/MenuBarController.swift` (About item, localize strings)
- Edit: `Sources/Footswitch/SettingsView.swift` (localize strings)
- Edit: `Sources/Footswitch/AppDelegate.swift` (retain + open About window)
- Edit: `Sources/Footswitch/Resources/Info.plist` (CFBundleLocalizations,
  CFBundleDevelopmentRegion, GitCommitHash placeholder)
- Edit: `Package.swift` (exclude Localizations from SwiftPM resource processing if needed)
- Edit: `scripts/package-app.sh` (copy .lproj, inject commit hash)
- New: a `.strings` parity test under `Tests/` (or a script)
