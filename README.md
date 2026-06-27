# Footswitch

Context-aware macOS menu bar app for iKKEGOL / PCsensor USB and Bluetooth foot
switches, single- or multi-pedal. Press a pedal to run an action chosen by the
frontmost app: a key combo or a macOS Shortcut for apps you've configured, or
macOS dictation as the default action.

The app is a universal binary (Apple Silicon + Intel), runs as a menu bar
app, and is localized into 30 languages — it follows your macOS language
automatically.

## Typical uses

The app was designed for two use cases: to allow the pedal to enable dictation
in apps that accept text input, and to allow the pedal to mute/unmute apps that
use the microphone for voice communication. Because a pedal can also send any key
combo or run any macOS Shortcut per app, you can map it to whatever else you like
— page turning in music or reading applications, a script, a clipboard action, a
multi-step automation, and so on.

## Multi-pedal switches

Multi-pedal USB foot switches (e.g. 3-pedal PCsensor / iKKEGOL page-turners) are
supported. The app detects how many pedals your device has and lets you program
each pedal a distinct key (default **F13 / F14 / F15** for pedals 1 / 2 / 3) and
assign per-app actions per pedal in Settings. Single-pedal devices behave exactly
as before. Plugging in a multi-pedal unit while the app is running is detected
live — no relaunch needed.

## Install

Download `Footswitch.dmg` from the [latest release](https://github.com/ericfitz/footswitch/releases/latest),
open it, and drag **Footswitch** to Applications. The app is signed with a
Developer ID and notarized by Apple, so it launches without Gatekeeper warnings.

On first launch, grant **Accessibility** permission (see below). To build from
source instead, see [Build & run](#build--run).

## How it works

The app programs each pedal to emit a function key — **F13** for a single pedal,
and **F14 / F15** for the 2nd / 3rd pedals on multi-pedal units. You can choose
any single key that you want, optionally including modifier keys, and program it
to the pedal. F13-F19 were selected as the defauls as they have no physical key
on most Mac keyboards and no terminal escape sequence, so they never collide
with normal typing or leak visible characters.

The app installs a global event tap that catches and swallows those keys,
identifies which pedal fired, looks at the frontmost application, and runs the
action mapped to that app for that pedal (falling back to a configurable default).
The tap only catches keys for pedals your connected device actually has, so unused
function keys pass through normally.

A pedal's trigger isn't limited to a bare function key — you can program it to
emit a key plus modifiers (⌃⌥⇧⌘), e.g. ⌥F13, and the app listens for that exact
combo. The defaults (F13 / F14 / F15, no modifiers) are what most people want.

## macOS dictation setup

There is no public API to start dictation, so the app synthesizes a dictation
keyboard shortcut. It reads your actual macOS Dictation shortcut automatically,
so the only setup is turning Dictation on:

1. System Settings → Keyboard → Dictation → turn Dictation on.
2. Leave the Dictation **Shortcut** at whatever single key combo you like — the
   app detects it and uses it as-is, no config to keep in sync.

Two caveats:

- The "double-tap" presets (e.g. *Press Control twice*) can't be synthesized as a
  keystroke. If your shortcut is a double-tap, the app surfaces a ⚠️ warning in the
  menu bar and falls back to its configured `dictationShortcut`; pick a regular
  combo instead.
- To override auto-detection, set an explicit `dictationShortcut` in
  `~/.footswitch/config.json` to any value other than the default ⌃⌥⌘D — that
  always wins.

## PCsensor FS17Pro (wireless)

The FS17Pro works over Bluetooth or USB. Pair it over Bluetooth (or connect the
USB-C cable), open **Settings…**, set the pedal's trigger key to `F16`, and click
**Program pedal** — the app writes the key over whichever transport the pedal is
connected on. F16 is recommended (the app's general default elsewhere is F13, but
PCsensor's ElfKey app cannot assign F13–F15, so the FS17Pro uses F16). Programming
over Bluetooth stores the key but the FS17Pro only applies it after you power-cycle
the pedal (turn it off and on) — the app reminds you when you click **Program
pedal**. (Programming over USB applies immediately.)

**Important:** the FS17Pro stores its key configuration independently for USB and
Bluetooth — the two slots do not share. Programming over one transport has no
effect on the other. You must program the pedal in the same mode you intend to use
it. If you use it both wired and wireless, connect in each mode and click **Program
pedal** each time (use the same trigger key both times so it behaves identically).

The first time you program over Bluetooth, macOS asks for Bluetooth permission —
allow it (the app needs Bluetooth only to configure the pedal).

## Build & run

```sh
swift test                    # run the unit-tested core
swiftlint                     # optional: style/lint check (brew install swiftlint)
./scripts/setup-signing.sh    # one-time: pick your signing identity (writes scripts/signing.env)
./scripts/package-app.sh      # build a signed Footswitch.app under build/
open build/Footswitch.app
```

Linting is optional for local dev but enforced for release builds:
`package-app.sh` runs `swiftlint --strict` (when SwiftLint is installed) and fails
the build on any violation. Rules live in `.swiftlint.yml`.

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
`debounceMs` or a device's trigger keys — take effect on the next launch.

Example:

```json
{
  "devices": [
    {
      "vendorId": "0x0C45",
      "productId": "0x7403",
      "program": "footswitch",
      "name": "PCsensor Foot Switch",
      "triggers": [{ "key": "F13", "slot": 1 }]
    }
  ],
  "dictationShortcut": { "modifiers": ["ctrl", "opt", "cmd"], "key": "D" },
  "debounceMs": 250,
  "defaultAction": { "type": "dictation" },
  "rules": [
    {
      "match": "com.microsoft.VSCode",
      "appName": "Visual Studio Code",
      "slots": {
        "1": { "type": "keyCombo", "modifiers": ["cmd"], "key": "D" }
      }
    },
    {
      "match": "com.apple.mail",
      "appName": "Mail",
      "slots": {
        "1": { "type": "shortcut", "identifier": "01234567-89AB-CDEF-0123-456789ABCDEF", "name": "Archive & Reply" }
      }
    }
  ]
}
```

- `devices` records each foot switch the app has seen and the trigger key each
  pedal emits. The app writes this for you when you program a pedal; you rarely
  edit it by hand. A device with no entry uses the defaults (F13 / F14 / F15).
  Each entry under `triggers` may also carry a `modifiers` array if you've
  programmed the pedal to emit a modifier combo.
- `match` is the frontmost app's **bundle ID** (stable across renames). Exact
  match wins; otherwise `defaultAction` runs.
- `slots` maps each pedal (1-based: `"1"` is the first pedal) to the action it
  runs for that app. Single-pedal devices only use `"1"`.
- `defaultAction.type` is `dictation` or `none`.
- Modifiers accept `cmd`/`opt`/`ctrl`/`shift` (or the long forms).

## Action types

Each per-app rule can run one of two kinds of action per pedal (pick the kind
from the popup in the rule's action cell):

- **Key sequence** (`keyCombo`) — synthesize a keystroke to the frontmost app
  (e.g. VS Code → ⌘D).
- **Run a Shortcut** (`shortcut`) — run a macOS Shortcuts.app shortcut by name.
  Footswitch lists your installed Shortcuts in the picker and runs the chosen one
  via `shortcuts run` when the pedal fires (fire-and-forget, so a long-running
  Shortcut never blocks the pedal). macOS may ask permission the first time a
  Shortcut runs.

The default action (when no app rule matches) is either **Start dictation**
(replay your configured dictation shortcut) or nothing — controlled by the
"Start dictation when no app rule matches" checkbox.

### Muting on calls

To mute in a conferencing app, add a per-app rule with that app's own mute
shortcut. Picking a known app pre-fills it: FaceTime ⌘⇧M, Zoom ⌘⇧A, Teams ⌘⇧M,
Google Meet (in Chrome) ⌘D. This drives the app's real mute — a system-wide
device mute does **not** work for these apps, since each keeps its own mute
state independent of the OS input device.

## Menu bar

The 🦶 status item shows the most recent press and a menu with **About
Footswitch**, **Settings…**, and **Quit**. The About window shows the version and
build commit and links to the GitHub repo, a prefilled "Report a problem" issue
(with your app version, macOS version, and architecture), and the license.

## Localization

The UI ships in 30 languages and follows your macOS language automatically
(System Settings → General → Language & Region). If your language isn't included,
it falls back to English. Strings live in
`Sources/Footswitch/Resources/Localizations/<lang>.lproj/Localizable.strings`,
with English (`en`) as the authoritative source; the packaging scripts copy them
into the app bundle. See [docs/localization-review-backlog.md](docs/localization-review-backlog.md)
for the status of per-language review.

## Project layout

- `Sources/FootswitchCore/` — pure, headlessly-testable logic (models,
  `RuleResolver`, `Debouncer`, `Keymap`, `ActionDispatcher`, `ConfigStore`,
  device protocol, injectable `EventPosting` seam). Covered by `swift test`.
- `Sources/Footswitch/` — the AppKit/SwiftUI app and OS glue (event tap, live
  CGEvent key synthesis, IOKit device detection, menu bar, settings window,
  permissions). Verified manually.
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
   (dictation, or nothing, per the checkbox).
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
