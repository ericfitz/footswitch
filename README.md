# Footswitch

Context-aware macOS menu bar app for a single-pedal iKKEGOL / PCsensor USB foot
switch. Press the pedal to run an action chosen by the frontmost app: a key
combo, or macOS dictation / input mute as the default action.

## How it works

The pedal is programmed once to emit **F13** — a key with no physical key on Mac
keyboards and no terminal escape sequence, so it never collides with normal
typing or leaks visible characters. The app installs a global event tap that
catches and swallows F13, looks at the frontmost application, and runs the action
mapped to that app (falling back to a configurable default).

## One-time hardware setup

Program the pedal to emit F13 using the open-source `footswitch` CLI:

```sh
brew install footswitch        # rgerganov/footswitch
sudo footswitch -k f13
```

Verify: run `sudo footswitch` (no args) to read back the current programming.
Pressing the pedal in a text field should produce no visible character once the
app is running and has permission (F13 has no glyph and is swallowed).

> This is a **single-pedal** device, so address it with a bare `-k` (no `-1`/`-2`
> index). Out of the box it ships emitting a lowercase `b`.

## macOS dictation setup

There is no public API to start dictation, so the app synthesizes a dictation
keyboard shortcut. Set it up once:

1. System Settings → Keyboard → Dictation → turn Dictation on.
2. Set the Dictation **Shortcut** to a single custom combo, e.g. **⌃⌥⌘D**
   (Control-Option-Command-D). Avoid the "double-tap" presets — they can't be
   synthesized reliably.
3. Make sure the app's `dictationShortcut` matches (the default is ⌃⌥⌘D).

## Build & run

```sh
swift test                    # run the unit-tested core
./scripts/setup-signing.sh    # one-time: pick your signing identity (writes scripts/signing.env)
./scripts/package-app.sh      # build a signed Footswitch.app under build/
open build/Footswitch.app
```

`setup-signing.sh` reads your keychain, lets you choose an **Apple Development**
identity, and writes an untracked `scripts/signing.env` that `package-app.sh`
sources. An Apple Development certificate is free with any Apple ID (Xcode →
Settings → Accounts → Manage Certificates → +) — it gives the build a stable
code identity, which is all you need for personal use. No personal identity is
committed to the repo.

Signing is **optional**: if you skip `setup-signing.sh` you can sign ad-hoc
instead (`export SIGN_IDENTITY=-` before running `package-app.sh`, or edit the
script). Ad-hoc builds run fine, but because they have no stable identity macOS
re-prompts for Accessibility on every rebuild. A (free) Apple Development
identity makes the grant persist.

On first launch, grant **Accessibility** permission (System Settings → Privacy &
Security → Accessibility). This single permission lets the app both listen for
F13 and synthesize keystrokes. The menu bar 🦶 shows a warning item until granted;
click it to open the right settings pane.

> **Why a packaged `.app` instead of `swift run`, and why signed?** The
> Accessibility grant is tied to a stable code identity. Ad-hoc signatures have
> no stable identity, so macOS treats every rebuild as a new app and the grant
> never persists — signing with your Apple Development identity keeps it stable.
> `package-app.sh` also embeds `Info.plist` (`LSUIElement`): SwiftPM doesn't allow
> `Info.plist` as a top-level resource, so it lives in
> `Sources/Footswitch/Resources/Info.plist`, is excluded from the SwiftPM resource
> bundle, and is copied into `Contents/Info.plist` by the packaging script.
> Runtime menu-bar behavior is also set via `setActivationPolicy(.accessory)`.

## Configuration

Config lives at `~/.footswitch/config.json` (created on first launch). Edit it
via the **Settings…** menu item, or by hand. In-app edits to rules and the
default action take effect immediately; hand edits — and any change to
`triggerKey` or `debounceMs` — take effect on the next launch.

Example:

```json
{
  "triggerKey": "F13",
  "dictationShortcut": { "modifiers": ["ctrl", "opt", "cmd"], "key": "D" },
  "debounceMs": 250,
  "defaultAction": { "type": "dictation" },
  "rules": [
    {
      "match": "com.microsoft.VSCode",
      "appName": "Visual Studio Code",
      "action": { "type": "keyCombo", "modifiers": ["cmd"], "key": "D" }
    }
  ]
}
```

- `match` is the frontmost app's **bundle ID** (stable across renames). Exact
  match wins; otherwise `defaultAction` runs.
- `defaultAction.type` is `dictation`, `muteInput`, or `none`.
- Modifiers accept `cmd`/`opt`/`ctrl`/`shift` (or the long forms).

## Action types

Per-app rules send a key combo:

- `keyCombo` — synthesize a keystroke (e.g. VS Code → ⌘D)

The default action (when no app rule matches) is one of:

- **Start dictation** — replay your configured dictation shortcut
- **Mute sound input** — toggle hardware mute on the default input device
- **No action** — do nothing

## Project layout

- `Sources/FootswitchCore/` — pure, headlessly-testable logic (models,
  `RuleResolver`, `Debouncer`, `Keymap`, `ActionDispatcher`, `ConfigStore`,
  device protocol, injectable `EventPosting`/`InputMuting` seams). Covered by
  `swift test`.
- `Sources/Footswitch/` — the AppKit/SwiftUI app and OS glue (event tap, live
  CGEvent key synthesis, CoreAudio mute, IOKit device detection, menu bar,
  settings window, permissions). Verified manually.
- `docs/supported-devices.md` — the USB foot switch models this app recognizes.

## Manual verification checklist

The core logic is unit-tested, but the OS integration needs the real device:

1. `./scripts/package-app.sh && open build/Footswitch.app` — 🦶 appears in the menu bar.
2. Grant Accessibility; the warning menu item disappears.
3. Open Settings — the **Foot switch** section detects the pedal; use
   **Program pedal** if the configuration row says it must be updated.
4. Add a VS Code rule via the **+** button and capture ⌘D (changes auto-save).
5. Focus VS Code, press the pedal → ⌘D fires.
6. Focus another app (e.g. TextEdit), press the pedal → the default action runs
   (dictation, mute, or nothing per the radio selection).
7. Confirm the trigger key never appears as a character anywhere (it is swallowed).

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — you may use, modify, and share this
software for any **noncommercial** purpose (personal use, hobby projects,
education, research). **Commercial use is not permitted.** See [LICENSE](LICENSE)
for the full terms.

## Acknowledgements

Thanks to Radoslav Gerganov for [`footswitch`](https://github.com/rgerganov/footswitch),
the command-line utility for programming PCsensor and Scythe foot switches. It
was invaluable for understanding how these devices work, and this project's
device detection and programming were inspired by it. No code from that project
is used here — the USB HID logic is an independent reimplementation in Swift.
