# Apple Shortcut Action — Design

Date: 2026-06-03
Status: Implemented (GitHub issue #3)

## Goal

Let a per-app rule fire a **macOS Shortcuts.app shortcut** (Monterey+ "Shortcuts")
instead of a keyboard key sequence. Implement GitHub issue #3:

1. A per-app rule's action can be **either** a key sequence (the current default)
   **or** a Shortcuts.app shortcut invocation.
2. The Settings UI lets the user pick, per rule, which kind of action it is, and
   choose an installed shortcut when they pick "shortcut".
3. When the pedal fires in that app, the chosen shortcut runs.

### Terminology (read this first — the codebase overloads "shortcut")

This feature introduces a naming collision that must be policed throughout:

- **key combo / key sequence** — the existing `KeyCombo` (`⌘D`, `F13`). The UI
  column is titled `settings.col.shortcut` ("Shortcut") and `ShortcutCaptureView`
  captures one. In code these are always `KeyCombo` / "key combo".
- **Shortcut (Shortcuts.app)** — a named automation from Apple's Shortcuts app,
  identified by a name and a stable UUID. In code these are **always** spelled
  `Shortcut`, `shortcutRef`, "Shortcuts.app shortcut", or "Apple shortcut" — never
  the bare word "shortcut" in a new symbol where it could mean a key combo.

To remove the existing ambiguity, this design also **renames the Settings column
title key** from `settings.col.shortcut` to `settings.col.action` (see Section 6).

## Context (real codebase facts)

- `Action` (`Sources/FootswitchCore/Models/Action.swift`) is already a sum type:
  `enum Action: Codable, Equatable, Sendable { case keyCombo(KeyCombo); case dictation }`,
  with a hand-written `Codable` keyed on a `"type"` discriminator (`"keyCombo"` /
  `"dictation"`) and an explicit `default:` that **throws** on an unknown type.
  `ActionCodingTests.testUnknownActionTypeThrows` pins that throwing behavior.
- `Rule` (`Sources/FootswitchCore/Models/Rule.swift`) holds `match` (bundle ID),
  `appName` (display only), and `action: Action`.
- `ResolvedAction` (`Sources/FootswitchCore/Models/DefaultAction.swift`) is the
  post-resolution value the dispatcher consumes:
  `enum ResolvedAction { case keyCombo(KeyCombo); case dictation; case none }`.
- `RuleResolver.resolve(bundleID:config:)` maps a matched rule's `Action` to a
  `ResolvedAction` (key combo → key combo, dictation → dictation) and otherwise
  returns the config's `DefaultAction`.
- `ActionDispatcher.dispatch(_:)` switches on `ResolvedAction`; `.keyCombo` and
  `.dictation` both post a `KeyCombo` through `EventPosting`
  (`Sources/FootswitchCore/Seams.swift`). It has no IO beyond `EventPosting`.
- `SettingsView.swift` builds a two-column `NSTableView` ("Application" /
  "Shortcut"). The action cell is always a `ShortcutCaptureView` (key-combo
  recorder). `addRule()` seeds a key combo from `KnownAppDefaults` and stores
  `.keyCombo(...)`; `updateShortcut(row:combo:)` rewrites `rules[row].action` as
  `.keyCombo`. There is currently **no way to choose any non-keyCombo action per
  rule** in the UI.
- `MenuBarController.describe(_:)` renders a `ResolvedAction` for the "Last:" menu
  line: key combo → glyphs, dictation/none → localized text.
- App is **not sandboxed**, hardened runtime, `LSUIElement`. `Footswitch.entitlements`
  is an intentionally empty dict; its comment states the app "is not sandboxed, has
  no network use, and reads/writes only `~/.footswitch`."
- `/usr/bin/shortcuts` exists on the target OS (macOS 13+). Verified subcommands:
  `shortcuts list [--show-identifiers]` (prints one shortcut name per line; with
  `--show-identifiers`, appends ` (UUID)`), and
  `shortcuts run <name-or-identifier>`. There is also a documented URL scheme
  `shortcuts://run-shortcut?name=<name>`.
- `AboutWindowController` already shells nothing but uses `NSWorkspace.shared.open`
  for URLs; `PermissionsManager` uses `NSWorkspace.shared.open`. No existing code
  spawns a `Process`.
- Config is stored at `~/.footswitch/config.json`; `Config.init(from:)` already
  demonstrates the codebase's lenient-migration pattern (an old `defaultAction`
  that fails to decode migrates to `.dictation`).
- L10n: every user string flows through `Sources/Footswitch/L10n.swift` →
  `NSLocalizedString` against `Bundle.main`. There are **30 locales** on disk under
  `Sources/Footswitch/Resources/Localizations/<locale>.lproj/Localizable.strings`
  (en is authoritative; verified by counting `.lproj` folders in the source tree —
  ignore the duplicate copies under `.build/` and `build/Footswitch.app`).
  `LocalizationParityTests` **discovers locales dynamically** from disk
  (`FileManager.contentsOfDirectory` filtered to `*.lproj`) and enforces identical
  key sets and matching positional-placeholder arity across **all** discovered
  locales, reading the source `.strings` directly (no `.app` bundle). Because the
  test discovers locales at runtime, the localization work below must touch **every
  locale folder present on disk** (currently 30) — the count is informational, not a
  hard target; if a locale is added or removed the same rule applies.

## Chosen approach

The model change is small and obvious: add a third `Action` case. The real design
decision is **how to invoke a Shortcuts.app shortcut on press** and **how to
enumerate installed shortcuts for the picker**. Three candidate invocation
mechanisms:

### Candidate A — `/usr/bin/shortcuts run` via `Process` (recommended)

Spawn `Process` with `executableURL = /usr/bin/shortcuts`, `arguments =
["run", <identifier-or-name>]`, launched off the main thread.

- **Pros:** First-party Apple CLI, present on every macOS 13+. Same binary backs
  the picker (`shortcuts list`), so enumeration and invocation share one
  dependency and one failure surface. Synchronous exit status + stderr give a real
  error signal we can surface. No URL-scheme round-trip through `NSWorkspace`. Not
  sandboxed, so `Process` spawning is permitted (no `com.apple.security.*`
  entitlement needed).
- **Cons:** Spawns a child process per press (cheap; pedal presses are debounced at
  250 ms and human-paced). `shortcuts run` blocks until the shortcut finishes — we
  must run it detached so a long shortcut never stalls the pedal. We do not capture
  the shortcut's *output* (intentional — see Out of scope).

### Candidate B — `shortcuts://run-shortcut?name=<name>` URL via `NSWorkspace.shared.open`

- **Pros:** Mirrors the existing `NSWorkspace.shared.open` pattern in
  `AboutWindowController`/`PermissionsManager`; no `Process`.
- **Cons:** The URL scheme keys on **name only** (no UUID), so two shortcuts with
  the same name are ambiguous and a rename silently breaks the rule. It activates
  Shortcuts.app UI and gives **no completion or error signal** back to Footswitch —
  we cannot tell success from "no such shortcut". Enumeration still needs the CLI,
  so this does not even remove the CLI dependency.

### Candidate C — Private/AppKit Shortcuts framework / `NSUserActivity`

- **Cons:** No supported public API to *run a named shortcut by identifier* from an
  arbitrary app on macOS 13. Would rely on private SPI (notarization/longevity
  risk). Rejected outright.

### Recommendation

**Candidate A.** Use `/usr/bin/shortcuts` for both enumeration (`list
--show-identifiers`) and invocation (`run <identifier>`), storing the shortcut's
**UUID identifier** (with the name kept for display) so renames don't break rules.
Keep all process-spawning IO in the **Footswitch** target behind a small
`ShortcutRunning` seam (mirroring `EventPosting`), so `FootswitchCore` stays
platform-agnostic and unit-testable with a mock. This matches the existing
Core/IO split exactly.

**Rejected alternatives:** Candidate B (name-only, no error signal, still needs the
CLI); Candidate C (private SPI).

---

## Section 1 — Data model: the `shortcut` Action case

### New value type (FootswitchCore)

A small `Codable`, `Equatable`, `Sendable` reference identifying a Shortcuts.app
shortcut by stable identifier, with a human name for display:

```swift
public struct ShortcutRef: Codable, Equatable, Sendable {
    public var identifier: String   // Shortcuts UUID (stable across renames)
    public var name: String         // display name at capture time
}
```

`identifier` is what we pass to `shortcuts run`; `name` is what the table and the
"Last:" menu line show. If `identifier` is somehow empty (e.g. a hand-edited
config), invocation falls back to running by `name` (Section 4).

### Extend `Action`

Add a third case and extend the hand-written `Codable` with discriminator
`"shortcut"`:

```swift
public enum Action: Codable, Equatable, Sendable {
    case keyCombo(KeyCombo)
    case dictation
    case shortcut(ShortcutRef)
}
```

Coding keys grow to `{ type, modifiers, key, identifier, name }`. Encode writes
`type:"shortcut"`, `identifier`, `name`. Decode adds a `case "shortcut":` that
reads `identifier` (required) and `name` (default `""`). The existing `default:`
that throws on unknown types is **kept** — `ActionCodingTests.testUnknownActionTypeThrows`
stays green because `"shell"` is still unknown.

### Back-compat

Adding a case is purely additive to the JSON: existing configs contain only
`"keyCombo"` / `"dictation"` action objects and decode unchanged. A new
`"shortcut"` object only appears once a user creates one in this build. No
`Config`-level migration is required (the `Config.init(from:)` lenient path is for
`defaultAction`, which this feature does not touch). Older app builds reading a
config that contains a `"shortcut"` action would throw on that rule — acceptable
and out of scope (we don't support downgrade).

## Section 2 — Resolution: extend `ResolvedAction`

`ResolvedAction` gains a parallel case so the dispatcher receives a fully-resolved
value with no further config lookup:

```swift
public enum ResolvedAction: Equatable, Sendable {
    case keyCombo(KeyCombo)
    case dictation
    case shortcut(ShortcutRef)
    case none
}
```

`RuleResolver.resolve(bundleID:config:)` adds one arm to its matched-rule switch:
`case .shortcut(let ref): return .shortcut(ref)`. The `DefaultAction` branch is
unchanged — a Shortcuts.app shortcut is only ever a **per-app rule** action, never
the global default (matching how `dictation` is the default and `keyCombo` is rule
-only today; see Assumptions).

## Section 3 — Invocation seam (`ShortcutRunning`) and dispatch

### The seam (FootswitchCore)

Mirror `EventPosting` so Core stays IO-free and testable:

```swift
// Sources/FootswitchCore/Seams.swift  (alongside EventPosting)
public protocol ShortcutRunning: AnyObject {
    /// Runs the Shortcuts.app shortcut identified by `ref`, fire-and-forget.
    func run(_ ref: ShortcutRef)
}
```

### Dispatcher change (FootswitchCore)

`ActionDispatcher` takes an optional runner and gains one `dispatch` arm:

```swift
public init(poster: EventPosting,
            dictationShortcut: KeyCombo,
            shortcutRunner: ShortcutRunning? = nil) { ... }

// in dispatch(_:)
case .shortcut(let ref): shortcutRunner?.run(ref)
case .none: break
```

The `shortcutRunner` is optional (default `nil`) so existing dispatcher
construction in tests compiles unchanged; a `nil` runner makes `.shortcut` a no-op,
exactly like `.none`. The dispatcher itself spawns nothing.

### Live runner (Footswitch target)

`Sources/Footswitch/ShortcutRunner.swift` — the only new code that spawns a
process:

```swift
final class ShortcutRunner: ShortcutRunning {
    func run(_ ref: ShortcutRef) {
        let arg = ref.identifier.isEmpty ? ref.name : ref.identifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", arg]
        // stdout/stderr to /dev/null (or a pipe drained for logging).
        // IMPORTANT (implementation detail): assign `terminationHandler` BEFORE
        // calling `run()`, and capture `p` strongly inside that handler so the
        // Process is retained until it exits — otherwise `p` may be deallocated
        // mid-flight and the handler may never fire. We do NOT wait synchronously —
        // a long-running shortcut must not block the pedal.
        p.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                // log non-zero exit for diagnosis (e.g. deleted shortcut). `proc`
                // (== p) is retained by this closure until termination.
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { try? p.run() }
    }
}
```

The `terminationHandler`/strong-reference handling above is load-bearing: there is
no existing `Process`-spawning code in the codebase (verified — `ShortcutRunner` is
the first), so the implementer cannot copy an established pattern and must get the
lifetime right here. The handler is what Section 5 relies on to log deleted-shortcut
(non-zero exit) failures.

`AppDelegate` constructs `ActionDispatcher(poster: LiveEventPoster(),
dictationShortcut: config.dictationShortcut, shortcutRunner: ShortcutRunner())` in
both `applicationDidFinishLaunching` and `reload(_:)`.

### Enumeration seam for the picker (Footswitch target)

A separate small helper (UI-side, not in Core) lists installed shortcuts for the
picker:

```swift
// Sources/Footswitch/ShortcutCatalog.swift
enum ShortcutCatalog {
    /// Runs `shortcuts list --show-identifiers`, parses "<name> (<UUID>)" lines,
    /// returns [ShortcutRef] sorted by name. Returns [] on any failure.
    static func installed() -> [ShortcutRef]
}
```

It runs `/usr/bin/shortcuts list --show-identifiers`, captures stdout via a `Pipe`,
and parses each line of the form `Name (UUID)` into a `ShortcutRef`. This is a
**synchronous, on-demand** call (not on the press hot path), so blocking briefly is
fine.

**Caching to avoid N spawns:** `NSTableView` builds and recycles cells eagerly, so
calling `installed()` while building every row would spawn `shortcuts list` once per
visible shortcut row. To prevent that, `SettingsViewController` fetches the catalog
**once per Settings-window open** (or lazily on the first time any shortcut popup is
built/opened) and caches the `[ShortcutRef]` in a stored property; cell building and
menu population read the cached array, never re-spawning per row. The cache lives
only for the lifetime of the open Settings window (live-refresh on Shortcuts.app
changes is explicitly out of scope), so a single fetch is sufficient.

## Section 4 — Data flow

Press path (unchanged shape; one new terminal branch):

```
PedalListener → AppDelegate.handlePress()
  → RuleResolver.resolve(bundleID, config) → ResolvedAction
  → ActionDispatcher.dispatch(action)
       .keyCombo / .dictation → EventPosting.postKeyStroke (existing)
       .shortcut(ref)         → ShortcutRunning.run(ref)  → Process /usr/bin/shortcuts run <id>
       .none                  → no-op
  → MenuBarController.setLastFire(app:action:)
```

Picker/config path (Settings):

```
User opens action-kind menu on a row → picks "Run a Shortcut"
  → ShortcutCatalog.installed() (shortcuts list) → [ShortcutRef]
  → user selects one → rules[row].action = .shortcut(ref) → save() → onSave → ConfigStore
```

## Section 5 — Error handling

- **`/usr/bin/shortcuts` missing or `Process.run()` throws** (e.g. on a future OS):
  `ShortcutRunner.run` swallows the `try?` and logs; the press is a silent no-op.
  No crash. (Pre-13 is out of scope; min target is macOS 13.)
- **Shortcut deleted/renamed after configuration:** running by stored `identifier`
  (UUID) survives renames. If the shortcut was *deleted*, `shortcuts run` exits
  non-zero; `terminationHandler` logs it. We deliberately do not pop an alert on a
  pedal press (the pedal must stay quiet and non-modal); the user discovers the
  problem because nothing happens, and the Settings table still shows the stale
  name (Section 6 offers a "shortcut no longer installed" affordance).
- **Empty `identifier`** (hand-edited config): fall back to running by `name`.
- **`ShortcutCatalog.installed()` returns `[]`** (CLI error, no shortcuts, or
  Automation/permission prompt declined): the picker shows a localized "No
  shortcuts found" disabled item and the user keeps whatever action the row had.
- **First-run Automation permission:** the first `shortcuts run`/`list` from a new
  app may trigger a macOS Shortcuts permission prompt. This is OS-driven and
  one-time; we surface a localized one-line hint under the rules table noting that
  macOS may ask permission the first time a shortcut runs (Assumptions).
- **Stale-name display:** the "Last:" menu line and table show `ref.name`; if it no
  longer matches an installed shortcut we still show the stored name (we don't
  re-list on every menu open — too costly).

## Section 6 — UI/UX changes (`SettingsView.swift`)

### Per-row action kind selector

The rules table's second column currently always hosts a `ShortcutCaptureView`.
Change the column to render **one of two editors** depending on `rule.action`,
fronted by a compact **action-kind** control so the user can switch a row between
"Key sequence" and "Run a Shortcut":

- The action cell becomes a horizontal stack: a small `NSPopUpButton` (the
  kind selector: **Key sequence** / **Run a Shortcut**) followed by the
  kind-specific editor:
  - **Key sequence** → the existing `ShortcutCaptureView` (unchanged behavior).
  - **Run a Shortcut** → an `NSPopUpButton` listing installed shortcuts (populated
    from the **cached** catalog described in Section 3 — fetched once per
    Settings-window open, not re-listed per cell), with the currently-selected
    `ref.name` shown. Selecting an item writes `.shortcut(ref)`.
- Switching the kind popup rewrites `rules[row].action`:
  - → Key sequence: `.keyCombo(KeyCombo(modifiers: [], key: ""))` (blank, user then
    records), preserving today's "click to set" flow.
  - → Run a Shortcut: `.shortcut(ShortcutRef(identifier: "", name: ""))` until the
    user picks one; an unpicked shortcut row is treated like an unset key combo
    (saved but effectively a no-op until completed).
- A row whose chosen shortcut is **not** in the freshly-listed installed set shows
  its stored name plus a localized "(not installed)" suffix in the popup so the
  user notices.

Two new fileprivate mutators on `SettingsViewController` parallel the existing
`updateShortcut(row:combo:)`:

```swift
fileprivate func updateActionKind(row: Int, kind: ActionKind)  // swaps the case
fileprivate func updateShortcutRef(row: Int, ref: ShortcutRef) // sets .shortcut(ref)
```

`addRule()` is unchanged for kind selection (new rules still default to **Key
sequence**, seeded from `KnownAppDefaults` as today); the user opts into a shortcut
afterward via the kind popup. `KnownAppDefaults` stays key-combo-only (Assumptions).

### Column-title disambiguation

Rename the table column **title key** from `settings.col.shortcut` ("Shortcut")
to a new key `settings.col.action` ("Action"), because the column can now hold
either an action kind. Concretely: `keyCol.title` in `SettingsView.swift` changes
from `L10n.settingsColShortcut` to `L10n.settingsColAction`. The old
`settings.col.shortcut` key (and the `L10n.settingsColShortcut` accessor) is
**removed** from `L10n.swift` and from every locale's `.strings` file (it is only
used for this column header).

> Note: this renames only the *displayed title* string key. The column's internal
> `NSTableColumn` **identifier** is the unrelated raw string `"shortcut"` (used as
> the `case "shortcut":` arm in `tableView(_:viewFor:row:)`). Leave that identifier
> as-is — changing it is unnecessary and would break the cell-vending switch.

### Menu "Last:" line (`MenuBarController.describe`)

Add `case .shortcut(let ref): return ref.name` so the most-recent-press line reads
e.g. `Last: Notes → My Shortcut`. (`ResolvedAction` gained `.shortcut`; the
`switch` must stay exhaustive.)

## Section 7 — Localization

Per the established workflow, every new user string is defined once in
`L10n.swift` (with an authoritative English `comment:`) and added — with the
English comment mirrored as a `/* */` header and a translated value — to **every
`<locale>.lproj/Localizable.strings` present on disk** (currently 30).
`LocalizationParityTests` discovers locales from disk and enforces identical key
sets and placeholder arity across every one, so a partial rollout fails
`swift test`.

New/changed keys:

| Key | English | Note |
|---|---|---|
| `settings.col.action` | `Action` | replaces `settings.col.shortcut` as the column title |
| `settings.actionKind.keySequence` | `Key sequence` | kind-popup item |
| `settings.actionKind.shortcut` | `Run a Shortcut` | kind-popup item (Shortcuts.app) |
| `settings.shortcut.choose` | `Choose a Shortcut…` | placeholder in the shortcut popup before one is picked |
| `settings.shortcut.none` | `No Shortcuts found` | disabled item when the catalog is empty |
| `settings.shortcut.notInstalled` | `%@ (not installed)` | stale stored shortcut; `%@` = stored name |
| `settings.shortcut.permissionHint` | `macOS may ask permission the first time a Shortcut runs.` | one-line hint under the rules table |

Removed key: `settings.col.shortcut` (deleted from `L10n.swift` + every locale on disk, currently 30).

Glyph/CLI strings are not localized. Shortcut **names** are user data and shown
verbatim.

## Section 8 — Testing

`swift test` runs against `FootswitchCore` without an `.app` bundle, so all new
unit tests live in Core and use seams/mocks.

- **`ActionCodingTests`**: `.shortcut(ShortcutRef(...))` round-trips; decodes from
  `{"type":"shortcut","identifier":"UUID","name":"My SC"}`; `name` defaults to `""`
  when absent; missing `identifier` throws; the existing unknown-type-throws test
  still passes; a pre-existing `keyCombo`/`dictation` config still decodes
  (back-compat).
- **`RuleResolverTests`**: a matched rule with `.shortcut(ref)` resolves to
  `ResolvedAction.shortcut(ref)`; default-action path unaffected.
- **`ActionDispatcherTests`**: add a `MockShortcutRunner: ShortcutRunning`
  recording `run(_:)` calls. Assert `dispatch(.shortcut(ref))` calls the runner
  once with that `ref`; with a `nil` runner it is a no-op; `.keyCombo`/`.dictation`
  still post key strokes and never call the runner.
- **`LocalizationParityTests`**: passes automatically once the new keys are added
  to every locale on disk (currently 30) and `settings.col.shortcut` is removed from
  each (it discovers locales from disk and checks key-set + placeholder-arity parity
  — `settings.shortcut.notInstalled`'s single `%@` must be present everywhere).
- **Line-parser unit test for `ShortcutCatalog`** (pure string parsing extracted to
  a free function in Core, e.g. `ShortcutListParser.parse(_ stdout:) -> [ShortcutRef]`):
  given sample `shortcuts list --show-identifiers` text including names with
  parentheses, returns the expected refs; malformed lines are skipped. Putting the
  parser in Core keeps it test-covered without spawning a process.

Manual/QA (not unit-testable here): real `shortcuts run` fires a chosen shortcut;
the first-run Automation permission prompt; deleted-shortcut produces a quiet
no-op; the Settings kind-popup swaps editors and persists.

## Out of scope (YAGNI)

- Passing **input to** or capturing **output from** a shortcut (`shortcuts run
  --input-path/--output-path`). Fire-and-forget only.
- Making a Shortcuts.app shortcut available as the **global `DefaultAction`** (it
  stays a per-app rule action, like `keyCombo`).
- Seeding `KnownAppDefaults` with shortcut suggestions (it stays key-combo only).
- Folder filtering / search in the shortcut picker; live-refresh of the picker when
  Shortcuts.app changes; reacting to renames after configuration.
- Sandboxing the app or adding entitlements. The app is intentionally un-sandboxed;
  `Process`-spawning `/usr/bin/shortcuts` needs no `com.apple.security.*`
  entitlement under the current hardened-runtime, non-sandboxed configuration. The
  empty `Footswitch.entitlements` dict is unchanged.
- Supporting downgrade (older app builds reading a `"shortcut"` action).
- macOS 12 (Monterey) — min deployment target is macOS 13 (`Package.swift`).

## Affected / new files

- Edit `Sources/FootswitchCore/Models/Action.swift` — add `ShortcutRef` type and
  `case shortcut(ShortcutRef)` with `Codable` discriminator `"shortcut"`.
- Edit `Sources/FootswitchCore/Models/DefaultAction.swift` — add
  `case shortcut(ShortcutRef)` to `ResolvedAction`.
- Edit `Sources/FootswitchCore/RuleResolver.swift` — map matched `.shortcut` rule to
  `ResolvedAction.shortcut`.
- Edit `Sources/FootswitchCore/Seams.swift` — add `ShortcutRunning` protocol.
- Edit `Sources/FootswitchCore/ActionDispatcher.swift` — optional `shortcutRunner`,
  dispatch `.shortcut`.
- New `Sources/FootswitchCore/ShortcutListParser.swift` — pure parser for
  `shortcuts list --show-identifiers` output (testable, no IO).
- New `Sources/Footswitch/ShortcutRunner.swift` — `ShortcutRunning` impl spawning
  `/usr/bin/shortcuts run` detached.
- New `Sources/Footswitch/ShortcutCatalog.swift` — enumerates installed shortcuts
  via `/usr/bin/shortcuts list --show-identifiers`, parses with `ShortcutListParser`.
- Edit `Sources/Footswitch/SettingsView.swift` — action-kind popup, shortcut popup
  editor, `updateActionKind`/`updateShortcutRef`, column-title key change, hint.
- Edit `Sources/Footswitch/MenuBarController.swift` — `describe(.shortcut)`.
- Edit `Sources/Footswitch/AppDelegate.swift` — pass `ShortcutRunner()` to the
  dispatcher (launch + reload).
- Edit `Sources/Footswitch/L10n.swift` — add the new keys, remove
  `settings.col.shortcut`.
- Edit every `Sources/Footswitch/Resources/Localizations/<locale>.lproj/Localizable.strings`
  on disk (currently 30) — add new keys, remove `settings.col.shortcut`.
- Edit `Tests/FootswitchCoreTests/ActionCodingTests.swift`,
  `RuleResolverTests.swift`, `ActionDispatcherTests.swift` — new cases + mock
  runner; new `ShortcutListParserTests.swift`.

## Assumptions

- **Invocation mechanism:** `/usr/bin/shortcuts run <identifier>` via `Process`,
  fire-and-forget, detached off the main thread (Candidate A). Chosen over the
  `shortcuts://` URL scheme because the CLI keys on a stable UUID and returns an
  exit status.
- **Identity:** store the Shortcuts **UUID** (`identifier`) plus a display `name`;
  run by `identifier`, fall back to `name` only if `identifier` is empty.
- **Scope of the new action:** Shortcuts.app shortcuts are a **per-app rule** action
  only, never the global `DefaultAction` (the issue says "per-app-shortcut").
- **New rules default to Key sequence**, preserving current behavior; the user opts
  into a shortcut via the per-row kind popup. `KnownAppDefaults` stays key-combo-only.
- **Disambiguation rename:** the rules column title moves from
  `settings.col.shortcut` to `settings.col.action` ("Action"), and the
  `settings.col.shortcut` key is deleted. This is a localized-string change, not an
  architectural one, but it is surfaced here because it removes the "shortcut"
  ambiguity the issue created.
- **No alert on press failure:** a failed/missing shortcut on a pedal press is a
  quiet no-op (logged), never a modal — the pedal must stay non-intrusive.
- **Automation permission** is OS-driven and one-time; we only show a static hint,
  we do not attempt to pre-authorize or detect the grant.
- **No sandbox/entitlement change:** consistent with the existing un-sandboxed,
  empty-entitlements posture documented in `Footswitch.entitlements`.
- **Picker enumeration is on-demand and synchronous** (only when the user opens the
  picker), acceptable because it is off the press hot path.


## Review & revision notes

Autonomous integration of reviewer feedback (status from review: "Issues Found").

### Issue addressed

- **Wrong locale count ("32" vs actual 30).** The reviewer flagged that every
  mention of "32 locales" is wrong; the source tree has **30** `.lproj` folders,
  each with a `Localizable.strings`. Verified independently:
  `find Sources/Footswitch/Resources/Localizations -name '*.lproj' -type d | wc -l`
  = 30 (and likewise for `Localizable.strings`). The earlier "120" counts seen in a
  naive `find` over the repo root were the same 30 locales duplicated across four
  build-output trees (`.build/apple/Products/Release`,
  `.build/arm64-apple-macosx/debug`, `build/Footswitch.app`) — 4 × 30. Every literal
  "32" in the spec (Context, Section 6 rename, Section 7, Section 8, Affected files)
  was corrected. Per the reviewer's preferred recommendation, the wording now leads
  with "every locale folder present on disk" (the parity test discovers locales
  dynamically, confirmed at `LocalizationParityTests.swift` lines 18–26 via
  `FileManager.contentsOfDirectory` filtered to `*.lproj`) and treats "30" as the
  current informational count rather than a hard checklist target, so the spec does
  not go stale if a locale is added/removed.

### Recommendations applied

- **`terminationHandler` / Process lifetime (Section 3).** Confirmed there is **no
  existing `Process()` or `terminationHandler` usage anywhere in `Sources/`** (ripgrep
  returned nothing), so the implementer has no in-repo pattern to copy. The live
  runner snippet was rewritten to assign `terminationHandler` *before* `run()` and to
  retain the `Process` by capturing it in the handler closure until it exits, with an
  explicit callout that this lifetime handling is load-bearing and is what Section 5
  relies on to log deleted-shortcut (non-zero exit) failures.

- **Avoid N `shortcuts list` spawns while building cells (Sections 3 & 6).** Confirmed
  `SettingsView` vends cells via `tableView(_:viewFor:row:)` (line 350), which AppKit
  calls per visible/recycled row. The spec now specifies a **single cached fetch per
  Settings-window open** (or lazy on first popup build) stored on
  `SettingsViewController`, with cell building and menu population reading the cache
  rather than re-spawning per row; the cache lives only for the open window's lifetime
  (live-refresh remains out of scope).

### Additional correctness fix found during verification (beyond the review)

- **Title key vs column identifier collision (Section 6).** The column's internal
  `NSTableColumn` identifier is the raw string `"shortcut"` (used as the
  `case "shortcut":` arm in `tableView(_:viewFor:row:)`), which is *separate* from the
  displayed-title localization key `settings.col.shortcut` (`keyCol.title =
  L10n.settingsColShortcut`, line 177). The rename in this spec targets only the
  title key/accessor. Added an explicit note that the column `identifier` "shortcut"
  must be left unchanged so the cell-vending switch keeps working — without it an
  implementer could mistakenly rename the identifier and break cell rendering.

### Not deferred

No reviewer point required a human product decision; all were resolvable against the
source. No new unresolved concerns were introduced.
