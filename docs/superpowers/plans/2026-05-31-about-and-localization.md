# About Dialog + Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a custom About window and four-locale localization (en/ar/zh-Hans/de) to the Footswitch macOS menu-bar app.

**Architecture:** All user-facing strings are centralized in one `L10n.swift` namespace wrapping `NSLocalizedString` against `Bundle.main`. Localized `.strings` live in hand-managed `.lproj` folders copied into `Footswitch.app/Contents/Resources/` by `package-app.sh` (same pattern as Info.plist/icns). The About window is a self-contained `NSWindowController` opened from the menu bar. The build commit hash is injected into Info.plist at package time.

**Tech Stack:** Swift 6, AppKit, SwiftPM (`swift build`/`swift test`), XCTest, bash packaging scripts.

---

## File Structure

**New files:**
- `Sources/Footswitch/L10n.swift` — one static namespace; every key has one `NSLocalizedString(_, comment:)` accessor. Single source of translator comments.
- `Sources/Footswitch/AboutWindowController.swift` — the About window (icon, version+commit, description, links).
- `Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings` — authoritative English (Base).
- `Sources/Footswitch/Resources/Localizations/ar.lproj/Localizable.strings` — Arabic (RTL).
- `Sources/Footswitch/Resources/Localizations/zh-Hans.lproj/Localizable.strings` — Simplified Chinese.
- `Sources/Footswitch/Resources/Localizations/de.lproj/Localizable.strings` — German.
- `Tests/FootswitchCoreTests/LocalizationParityTests.swift` — key-set + placeholder-arity parity across the four `.strings` files (reads files by path; no app bundle needed).

**Modified files:**
- `Sources/Footswitch/MenuBarController.swift` — add About menu item; replace literals with `L10n`.
- `Sources/Footswitch/SettingsView.swift` — replace literals with `L10n`.
- `Sources/Footswitch/AppDelegate.swift` — retain + open the About window.
- `Sources/Footswitch/Resources/Info.plist` — `CFBundleDevelopmentRegion`, `CFBundleLocalizations`, `GitCommitHash` placeholder.
- `Package.swift` — exclude `Resources/Localizations` from SwiftPM resource processing.
- `scripts/package-app.sh` — copy `.lproj` folders; inject git short SHA into copied Info.plist.

**Build/verify commands used throughout:**
- Build everything: `swift build`
- Run all tests: `swift test`
- Run one test class: `swift test --filter LocalizationParityTests`

---

## Task 1: Info.plist localization keys + commit placeholder

**Files:**
- Modify: `Sources/Footswitch/Resources/Info.plist`

- [ ] **Step 1: Add the three keys**

Edit `Sources/Footswitch/Resources/Info.plist`. After the `<key>LSMinimumSystemVersion</key><string>13.0</string>` line and before `</dict>`, add:

```xml
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ar</string>
    <string>zh-Hans</string>
    <string>de</string>
  </array>
  <key>GitCommitHash</key><string>0000000</string>
```

- [ ] **Step 2: Verify the plist is still valid**

Run: `plutil -lint Sources/Footswitch/Resources/Info.plist`
Expected: `Sources/Footswitch/Resources/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add Sources/Footswitch/Resources/Info.plist
git commit -m "feat: declare app localizations and commit-hash placeholder in Info.plist"
```

---

## Task 2: English Localizable.strings (authoritative Base)

**Files:**
- Create: `Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings`

- [ ] **Step 1: Create the English strings file**

Create `Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings` with exactly this content. Each entry has an English `/* */` translator comment (the authoritative context note):

```
/* Menu item: open the About window. */
"menu.about" = "About Footswitch";

/* Menu item: open the Settings window. Trailing ellipsis is conventional. */
"menu.settings" = "Settings…";

/* Menu item: quit the application entirely. */
"menu.quit" = "Quit Footswitch";

/* Menu warning shown when macOS Accessibility permission is not granted. Leading warning emoji. */
"menu.needsPermission" = "⚠️ Needs Accessibility permission";

/* Menu line showing the most recent pedal press. %1$@ = app name, %2$@ = action description. */
"menu.lastFire" = "Last: %1$@ → %2$@";

/* Menu line shown before any pedal press has happened. */
"menu.noPresses" = "No presses yet";

/* Action description: starts macOS dictation. Used inside menu.lastFire. */
"action.dictation" = "dictation";

/* Action description: pedal does nothing for this app. Used inside menu.lastFire. */
"action.none" = "no action";

/* Placeholder for an unknown frontmost app name. Used inside menu.lastFire. */
"app.unknown" = "unknown";

/* Title of the Settings window. */
"settings.windowTitle" = "Footswitch Settings";

/* Settings section header for the foot switch device. */
"settings.header.device" = "Foot switch";

/* Settings section header for the default (no-rule-matched) action. */
"settings.header.default" = "Default action";

/* Settings section header for the per-app rules list. */
"settings.header.rules" = "App rules";

/* Settings checkbox: enable dictation when no per-app rule matches. */
"settings.dictationCheckbox" = "Start dictation when no app rule matches";

/* Settings hint text below the rules table. */
"settings.rulesHint" = "Press the pedal in an app below to send its shortcut. Other apps use the default action above.";

/* Button: program the foot switch hardware with the trigger key. */
"settings.programButton" = "Program pedal";

/* Rules table column header for the application. */
"settings.col.application" = "Application";

/* Rules table column header for the keyboard shortcut. */
"settings.col.shortcut" = "Shortcut";

/* Device status: no supported foot switch is connected. */
"device.none" = "No supported foot switch detected";

/* Device status: a pedal was detected. %@ = device name. */
"device.detected" = "Detected pedal: %@";

/* Device config status: hardware matches expected configuration. */
"device.config.verified" = "Verified configuration";

/* Device config status: hardware configuration needs updating. */
"device.config.mismatch" = "Configuration must be updated";

/* Device config status: hardware configuration could not be read. */
"device.config.unreadable" = "Unable to read configuration";

/* Title of the device-info alert. */
"alert.deviceInfo.title" = "Foot switch information";

/* Device-info alert body when no device is connected. */
"alert.deviceInfo.none" = "No supported foot switch is connected.";

/* Generic title for foot switch alerts. */
"alert.footswitch.title" = "Foot switch";

/* Alert body after successfully programming the pedal. %@ = key name. */
"alert.programmed" = "Programmed the foot switch to send %@.";

/* Alert body after a failed programming attempt. %@ = error detail. */
"alert.programFailed" = "Could not program the foot switch.\n\n%@";

/* Generic OK button. */
"alert.ok" = "OK";

/* Title of the open panel used to pick an application for a rule. */
"openPanel.title" = "Choose an application";

/* Shortcut capture field: prompt before a shortcut is set. */
"capture.clickToSet" = "Click to set";

/* Shortcut capture field: prompt while recording a shortcut. */
"capture.pressShortcut" = "Press shortcut…";

/* Shortcut capture field: shown when an unsupported key is pressed. */
"capture.unsupportedKey" = "Unsupported key";

/* Shortcut capture field: shown when a modifier is required. Glyphs are command/option/control/shift. */
"capture.addModifier" = "Add a modifier (⌘⌥⌃⇧)";

/* About window title. */
"about.windowTitle" = "About Footswitch";

/* About window one-line description of the app. */
"about.description" = "Map your USB foot switch to keyboard shortcuts, per app.";

/* About window version line. %1$@ = short version, %2$@ = git commit hash. */
"about.version" = "Version %1$@ (%2$@)";

/* About window copyright line. */
"about.copyright" = "© 2026 Eric Fitzgerald";

/* About window link button: open the GitHub repository. */
"about.viewOnGitHub" = "View on GitHub";

/* About window link button: open a prefilled new GitHub issue. */
"about.reportProblem" = "Report a problem";

/* About window link button: open the license. */
"about.license" = "License";
```

- [ ] **Step 2: Verify the strings file parses**

Run: `plutil -lint Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings`
Expected: `... OK`

- [ ] **Step 3: Commit**

```bash
git add Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings
git commit -m "feat: add authoritative English Localizable.strings"
```

---

## Task 3: Translated .strings (ar, zh-Hans, de)

Each file mirrors the English keys and `/* */` comments (comments stay English — they are translator context), with translated values. Translations are best-effort and flagged for native review.

**Files:**
- Create: `Sources/Footswitch/Resources/Localizations/de.lproj/Localizable.strings`
- Create: `Sources/Footswitch/Resources/Localizations/zh-Hans.lproj/Localizable.strings`
- Create: `Sources/Footswitch/Resources/Localizations/ar.lproj/Localizable.strings`

- [ ] **Step 1: Create the German file**

Create `Sources/Footswitch/Resources/Localizations/de.lproj/Localizable.strings`:

```
/* Menu item: open the About window. */
"menu.about" = "Über Footswitch";

/* Menu item: open the Settings window. Trailing ellipsis is conventional. */
"menu.settings" = "Einstellungen…";

/* Menu item: quit the application entirely. */
"menu.quit" = "Footswitch beenden";

/* Menu warning shown when macOS Accessibility permission is not granted. Leading warning emoji. */
"menu.needsPermission" = "⚠️ Bedienungshilfen-Berechtigung erforderlich";

/* Menu line showing the most recent pedal press. %1$@ = app name, %2$@ = action description. */
"menu.lastFire" = "Zuletzt: %1$@ → %2$@";

/* Menu line shown before any pedal press has happened. */
"menu.noPresses" = "Noch keine Betätigungen";

/* Action description: starts macOS dictation. Used inside menu.lastFire. */
"action.dictation" = "Diktat";

/* Action description: pedal does nothing for this app. Used inside menu.lastFire. */
"action.none" = "keine Aktion";

/* Placeholder for an unknown frontmost app name. Used inside menu.lastFire. */
"app.unknown" = "unbekannt";

/* Title of the Settings window. */
"settings.windowTitle" = "Footswitch-Einstellungen";

/* Settings section header for the foot switch device. */
"settings.header.device" = "Fußschalter";

/* Settings section header for the default (no-rule-matched) action. */
"settings.header.default" = "Standardaktion";

/* Settings section header for the per-app rules list. */
"settings.header.rules" = "App-Regeln";

/* Settings checkbox: enable dictation when no per-app rule matches. */
"settings.dictationCheckbox" = "Diktat starten, wenn keine App-Regel zutrifft";

/* Settings hint text below the rules table. */
"settings.rulesHint" = "Betätigen Sie den Fußschalter in einer der unten stehenden Apps, um deren Kurzbefehl zu senden. Andere Apps verwenden die obige Standardaktion.";

/* Button: program the foot switch hardware with the trigger key. */
"settings.programButton" = "Pedal programmieren";

/* Rules table column header for the application. */
"settings.col.application" = "Anwendung";

/* Rules table column header for the keyboard shortcut. */
"settings.col.shortcut" = "Kurzbefehl";

/* Device status: no supported foot switch is connected. */
"device.none" = "Kein unterstützter Fußschalter erkannt";

/* Device status: a pedal was detected. %@ = device name. */
"device.detected" = "Pedal erkannt: %@";

/* Device config status: hardware matches expected configuration. */
"device.config.verified" = "Konfiguration überprüft";

/* Device config status: hardware configuration needs updating. */
"device.config.mismatch" = "Konfiguration muss aktualisiert werden";

/* Device config status: hardware configuration could not be read. */
"device.config.unreadable" = "Konfiguration kann nicht gelesen werden";

/* Title of the device-info alert. */
"alert.deviceInfo.title" = "Fußschalter-Informationen";

/* Device-info alert body when no device is connected. */
"alert.deviceInfo.none" = "Es ist kein unterstützter Fußschalter angeschlossen.";

/* Generic title for foot switch alerts. */
"alert.footswitch.title" = "Fußschalter";

/* Alert body after successfully programming the pedal. %@ = key name. */
"alert.programmed" = "Der Fußschalter wurde so programmiert, dass er %@ sendet.";

/* Alert body after a failed programming attempt. %@ = error detail. */
"alert.programFailed" = "Der Fußschalter konnte nicht programmiert werden.\n\n%@";

/* Generic OK button. */
"alert.ok" = "OK";

/* Title of the open panel used to pick an application for a rule. */
"openPanel.title" = "Anwendung auswählen";

/* Shortcut capture field: prompt before a shortcut is set. */
"capture.clickToSet" = "Zum Festlegen klicken";

/* Shortcut capture field: prompt while recording a shortcut. */
"capture.pressShortcut" = "Kurzbefehl drücken…";

/* Shortcut capture field: shown when an unsupported key is pressed. */
"capture.unsupportedKey" = "Nicht unterstützte Taste";

/* Shortcut capture field: shown when a modifier is required. Glyphs are command/option/control/shift. */
"capture.addModifier" = "Modifikatortaste hinzufügen (⌘⌥⌃⇧)";

/* About window title. */
"about.windowTitle" = "Über Footswitch";

/* About window one-line description of the app. */
"about.description" = "Ordnen Sie Ihren USB-Fußschalter pro App Tastaturkurzbefehlen zu.";

/* About window version line. %1$@ = short version, %2$@ = git commit hash. */
"about.version" = "Version %1$@ (%2$@)";

/* About window copyright line. */
"about.copyright" = "© 2026 Eric Fitzgerald";

/* About window link button: open the GitHub repository. */
"about.viewOnGitHub" = "Auf GitHub ansehen";

/* About window link button: open a prefilled new GitHub issue. */
"about.reportProblem" = "Problem melden";

/* About window link button: open the license. */
"about.license" = "Lizenz";
```

- [ ] **Step 2: Create the Simplified Chinese file**

Create `Sources/Footswitch/Resources/Localizations/zh-Hans.lproj/Localizable.strings`:

```
/* Menu item: open the About window. */
"menu.about" = "关于 Footswitch";

/* Menu item: open the Settings window. Trailing ellipsis is conventional. */
"menu.settings" = "设置…";

/* Menu item: quit the application entirely. */
"menu.quit" = "退出 Footswitch";

/* Menu warning shown when macOS Accessibility permission is not granted. Leading warning emoji. */
"menu.needsPermission" = "⚠️ 需要辅助功能权限";

/* Menu line showing the most recent pedal press. %1$@ = app name, %2$@ = action description. */
"menu.lastFire" = "最近：%1$@ → %2$@";

/* Menu line shown before any pedal press has happened. */
"menu.noPresses" = "尚无按下记录";

/* Action description: starts macOS dictation. Used inside menu.lastFire. */
"action.dictation" = "听写";

/* Action description: pedal does nothing for this app. Used inside menu.lastFire. */
"action.none" = "无操作";

/* Placeholder for an unknown frontmost app name. Used inside menu.lastFire. */
"app.unknown" = "未知";

/* Title of the Settings window. */
"settings.windowTitle" = "Footswitch 设置";

/* Settings section header for the foot switch device. */
"settings.header.device" = "脚踏开关";

/* Settings section header for the default (no-rule-matched) action. */
"settings.header.default" = "默认操作";

/* Settings section header for the per-app rules list. */
"settings.header.rules" = "应用规则";

/* Settings checkbox: enable dictation when no per-app rule matches. */
"settings.dictationCheckbox" = "当没有匹配的应用规则时启动听写";

/* Settings hint text below the rules table. */
"settings.rulesHint" = "在下方应用中踩下踏板即可发送其快捷键。其他应用使用上方的默认操作。";

/* Button: program the foot switch hardware with the trigger key. */
"settings.programButton" = "对踏板编程";

/* Rules table column header for the application. */
"settings.col.application" = "应用程序";

/* Rules table column header for the keyboard shortcut. */
"settings.col.shortcut" = "快捷键";

/* Device status: no supported foot switch is connected. */
"device.none" = "未检测到受支持的脚踏开关";

/* Device status: a pedal was detected. %@ = device name. */
"device.detected" = "检测到踏板：%@";

/* Device config status: hardware matches expected configuration. */
"device.config.verified" = "配置已验证";

/* Device config status: hardware configuration needs updating. */
"device.config.mismatch" = "必须更新配置";

/* Device config status: hardware configuration could not be read. */
"device.config.unreadable" = "无法读取配置";

/* Title of the device-info alert. */
"alert.deviceInfo.title" = "脚踏开关信息";

/* Device-info alert body when no device is connected. */
"alert.deviceInfo.none" = "未连接受支持的脚踏开关。";

/* Generic title for foot switch alerts. */
"alert.footswitch.title" = "脚踏开关";

/* Alert body after successfully programming the pedal. %@ = key name. */
"alert.programmed" = "已将脚踏开关编程为发送 %@。";

/* Alert body after a failed programming attempt. %@ = error detail. */
"alert.programFailed" = "无法对脚踏开关编程。\n\n%@";

/* Generic OK button. */
"alert.ok" = "好";

/* Title of the open panel used to pick an application for a rule. */
"openPanel.title" = "选择一个应用程序";

/* Shortcut capture field: prompt before a shortcut is set. */
"capture.clickToSet" = "点按以设置";

/* Shortcut capture field: prompt while recording a shortcut. */
"capture.pressShortcut" = "请按快捷键…";

/* Shortcut capture field: shown when an unsupported key is pressed. */
"capture.unsupportedKey" = "不支持的按键";

/* Shortcut capture field: shown when a modifier is required. Glyphs are command/option/control/shift. */
"capture.addModifier" = "请添加修饰键 (⌘⌥⌃⇧)";

/* About window title. */
"about.windowTitle" = "关于 Footswitch";

/* About window one-line description of the app. */
"about.description" = "为每个应用将 USB 脚踏开关映射到键盘快捷键。";

/* About window version line. %1$@ = short version, %2$@ = git commit hash. */
"about.version" = "版本 %1$@（%2$@）";

/* About window copyright line. */
"about.copyright" = "© 2026 Eric Fitzgerald";

/* About window link button: open the GitHub repository. */
"about.viewOnGitHub" = "在 GitHub 上查看";

/* About window link button: open a prefilled new GitHub issue. */
"about.reportProblem" = "报告问题";

/* About window link button: open the license. */
"about.license" = "许可证";
```

- [ ] **Step 3: Create the Arabic file (RTL)**

Create `Sources/Footswitch/Resources/Localizations/ar.lproj/Localizable.strings`:

```
/* Menu item: open the About window. */
"menu.about" = "حول Footswitch";

/* Menu item: open the Settings window. Trailing ellipsis is conventional. */
"menu.settings" = "الإعدادات…";

/* Menu item: quit the application entirely. */
"menu.quit" = "إنهاء Footswitch";

/* Menu warning shown when macOS Accessibility permission is not granted. Leading warning emoji. */
"menu.needsPermission" = "⚠️ يلزم إذن إمكانية الوصول";

/* Menu line showing the most recent pedal press. %1$@ = app name, %2$@ = action description. */
"menu.lastFire" = "الأخير: %1$@ ← %2$@";

/* Menu line shown before any pedal press has happened. */
"menu.noPresses" = "لا توجد ضغطات بعد";

/* Action description: starts macOS dictation. Used inside menu.lastFire. */
"action.dictation" = "الإملاء";

/* Action description: pedal does nothing for this app. Used inside menu.lastFire. */
"action.none" = "بلا إجراء";

/* Placeholder for an unknown frontmost app name. Used inside menu.lastFire. */
"app.unknown" = "غير معروف";

/* Title of the Settings window. */
"settings.windowTitle" = "إعدادات Footswitch";

/* Settings section header for the foot switch device. */
"settings.header.device" = "مفتاح القدم";

/* Settings section header for the default (no-rule-matched) action. */
"settings.header.default" = "الإجراء الافتراضي";

/* Settings section header for the per-app rules list. */
"settings.header.rules" = "قواعد التطبيقات";

/* Settings checkbox: enable dictation when no per-app rule matches. */
"settings.dictationCheckbox" = "بدء الإملاء عند عدم تطابق أي قاعدة تطبيق";

/* Settings hint text below the rules table. */
"settings.rulesHint" = "اضغط على المفتاح بالقدم في أحد التطبيقات أدناه لإرسال اختصاره. تستخدم التطبيقات الأخرى الإجراء الافتراضي أعلاه.";

/* Button: program the foot switch hardware with the trigger key. */
"settings.programButton" = "برمجة الدواسة";

/* Rules table column header for the application. */
"settings.col.application" = "التطبيق";

/* Rules table column header for the keyboard shortcut. */
"settings.col.shortcut" = "الاختصار";

/* Device status: no supported foot switch is connected. */
"device.none" = "لم يتم اكتشاف مفتاح قدم مدعوم";

/* Device status: a pedal was detected. %@ = device name. */
"device.detected" = "تم اكتشاف الدواسة: %@";

/* Device config status: hardware matches expected configuration. */
"device.config.verified" = "تم التحقق من التهيئة";

/* Device config status: hardware configuration needs updating. */
"device.config.mismatch" = "يجب تحديث التهيئة";

/* Device config status: hardware configuration could not be read. */
"device.config.unreadable" = "تعذّرت قراءة التهيئة";

/* Title of the device-info alert. */
"alert.deviceInfo.title" = "معلومات مفتاح القدم";

/* Device-info alert body when no device is connected. */
"alert.deviceInfo.none" = "لا يوجد مفتاح قدم مدعوم متصل.";

/* Generic title for foot switch alerts. */
"alert.footswitch.title" = "مفتاح القدم";

/* Alert body after successfully programming the pedal. %@ = key name. */
"alert.programmed" = "تمت برمجة مفتاح القدم لإرسال %@.";

/* Alert body after a failed programming attempt. %@ = error detail. */
"alert.programFailed" = "تعذّرت برمجة مفتاح القدم.\n\n%@";

/* Generic OK button. */
"alert.ok" = "موافق";

/* Title of the open panel used to pick an application for a rule. */
"openPanel.title" = "اختر تطبيقًا";

/* Shortcut capture field: prompt before a shortcut is set. */
"capture.clickToSet" = "انقر للتعيين";

/* Shortcut capture field: prompt while recording a shortcut. */
"capture.pressShortcut" = "اضغط الاختصار…";

/* Shortcut capture field: shown when an unsupported key is pressed. */
"capture.unsupportedKey" = "مفتاح غير مدعوم";

/* Shortcut capture field: shown when a modifier is required. Glyphs are command/option/control/shift. */
"capture.addModifier" = "أضف مفتاح تعديل (⌘⌥⌃⇧)";

/* About window title. */
"about.windowTitle" = "حول Footswitch";

/* About window one-line description of the app. */
"about.description" = "اربط مفتاح القدم USB باختصارات لوحة المفاتيح لكل تطبيق.";

/* About window version line. %1$@ = short version, %2$@ = git commit hash. */
"about.version" = "الإصدار %1$@ (%2$@)";

/* About window copyright line. */
"about.copyright" = "© 2026 Eric Fitzgerald";

/* About window link button: open the GitHub repository. */
"about.viewOnGitHub" = "عرض على GitHub";

/* About window link button: open a prefilled new GitHub issue. */
"about.reportProblem" = "الإبلاغ عن مشكلة";

/* About window link button: open the license. */
"about.license" = "الترخيص";
```

- [ ] **Step 4: Verify all three parse**

Run:
```bash
for l in de zh-Hans ar; do plutil -lint "Sources/Footswitch/Resources/Localizations/$l.lproj/Localizable.strings"; done
```
Expected: three `... OK` lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/Footswitch/Resources/Localizations/de.lproj Sources/Footswitch/Resources/Localizations/zh-Hans.lproj Sources/Footswitch/Resources/Localizations/ar.lproj
git commit -m "feat: add ar/zh-Hans/de translations (pending native review)"
```

---

## Task 4: Localization parity test

This test reads the four `.strings` files directly (no app bundle) and asserts: identical key sets, and identical positional-placeholder arity per key. It locates the repo via `#filePath`.

**Files:**
- Create: `Tests/FootswitchCoreTests/LocalizationParityTests.swift`

- [ ] **Step 1: Write the test**

Create `Tests/FootswitchCoreTests/LocalizationParityTests.swift`:

```swift
import XCTest

/// Verifies the four hand-managed Localizable.strings files stay structurally in
/// sync: same keys everywhere, and the same number of positional placeholders
/// (%N$@) per key. Reads the source .strings files directly — no .app bundle.
final class LocalizationParityTests: XCTestCase {
    private static let locales = ["en", "ar", "zh-Hans", "de"]

    /// Repo root derived from this file's path: Tests/FootswitchCoreTests/<file>.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FootswitchCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private static func stringsURL(_ locale: String) -> URL {
        repoRoot()
            .appendingPathComponent("Sources/Footswitch/Resources/Localizations")
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("Localizable.strings")
    }

    /// Parses a .strings file into [key: value] using PropertyListSerialization
    /// (the .strings old-style plist format is supported by the OpenStep reader).
    private func parse(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        guard let dict = plist as? [String: String] else {
            XCTFail("Not a string dictionary: \(url.path)")
            return [:]
        }
        return dict
    }

    /// Counts positional specifiers like %1$@, %2$@ — returns the highest index.
    private func placeholderArity(_ value: String) -> Int {
        var maxIndex = 0
        let pattern = try! NSRegularExpression(pattern: "%([0-9]+)\\$@")
        let ns = value as NSString
        for m in pattern.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            let idx = Int(ns.substring(with: m.range(at: 1))) ?? 0
            maxIndex = max(maxIndex, idx)
        }
        // Also count bare %@ (each contributes one positional argument).
        let bare = try! NSRegularExpression(pattern: "%@")
        let bareCount = bare.numberOfMatches(in: value, range: NSRange(location: 0, length: ns.length))
        return max(maxIndex, bareCount)
    }

    func testAllLocalesParse() throws {
        for locale in Self.locales {
            let dict = try parse(Self.stringsURL(locale))
            XCTAssertFalse(dict.isEmpty, "\(locale) parsed empty")
        }
    }

    func testKeySetsMatchEnglish() throws {
        let en = Set(try parse(Self.stringsURL("en")).keys)
        for locale in Self.locales where locale != "en" {
            let keys = Set(try parse(Self.stringsURL(locale)).keys)
            XCTAssertEqual(keys, en,
                "\(locale) keys differ from en. Missing: \(en.subtracting(keys)). Extra: \(keys.subtracting(en)).")
        }
    }

    func testPlaceholderArityMatchesEnglish() throws {
        let en = try parse(Self.stringsURL("en"))
        for locale in Self.locales where locale != "en" {
            let dict = try parse(Self.stringsURL(locale))
            for (key, enValue) in en {
                guard let value = dict[key] else { continue } // key-set test covers gaps
                XCTAssertEqual(placeholderArity(value), placeholderArity(enValue),
                    "Placeholder count mismatch for '\(key)' in \(locale).")
            }
        }
    }
}
```

- [ ] **Step 2: Run the test — it should PASS now (files already exist from Tasks 2–3)**

Run: `swift test --filter LocalizationParityTests`
Expected: PASS, 3 tests.

If `testKeySetsMatchEnglish` fails, a `.strings` file has a missing/extra key — fix the file, not the test. If `testPlaceholderArityMatchesEnglish` fails, a translated value dropped or added a `%@`/`%N$@` — fix the translation.

- [ ] **Step 3: Commit**

```bash
git add Tests/FootswitchCoreTests/LocalizationParityTests.swift
git commit -m "test: assert Localizable.strings key + placeholder parity across locales"
```

---

## Task 5: L10n namespace

One static namespace; every key resolved via `NSLocalizedString` against `Bundle.main`. Interpolated strings expose `String(format:)` helpers so call sites never build format strings by hand.

**Files:**
- Create: `Sources/Footswitch/L10n.swift`

- [ ] **Step 1: Write L10n.swift**

Create `Sources/Footswitch/L10n.swift`:

```swift
import Foundation

/// Central catalog of every user-facing string. Each property/function is the one
/// place a key is defined; the `comment:` is the authoritative translator note,
/// mirrored as a /* */ header in every Localizable.strings file. Values resolve
/// from Bundle.main (Contents/Resources/<lang>.lproj), populated by the packaging
/// scripts. Unpackaged `swift run` falls back to the key (no .lproj present).
enum L10n {
    private static func t(_ key: String, _ comment: String) -> String {
        NSLocalizedString(key, comment: comment)
    }

    // Menu
    static var menuAbout: String { t("menu.about", "Menu item: open the About window.") }
    static var menuSettings: String { t("menu.settings", "Menu item: open the Settings window.") }
    static var menuQuit: String { t("menu.quit", "Menu item: quit the application entirely.") }
    static var menuNeedsPermission: String { t("menu.needsPermission", "Menu warning when Accessibility permission is missing.") }
    static var menuNoPresses: String { t("menu.noPresses", "Menu line before any pedal press.") }
    /// %1$@ = app name, %2$@ = action description.
    static func menuLastFire(app: String, action: String) -> String {
        String(format: t("menu.lastFire", "Menu line for the most recent press. %1$@ app, %2$@ action."), app, action)
    }

    // Action descriptions
    static var actionDictation: String { t("action.dictation", "Action: starts dictation.") }
    static var actionNone: String { t("action.none", "Action: pedal does nothing.") }
    static var appUnknown: String { t("app.unknown", "Unknown frontmost app name.") }

    // Settings
    static var settingsWindowTitle: String { t("settings.windowTitle", "Settings window title.") }
    static var settingsHeaderDevice: String { t("settings.header.device", "Settings header: device.") }
    static var settingsHeaderDefault: String { t("settings.header.default", "Settings header: default action.") }
    static var settingsHeaderRules: String { t("settings.header.rules", "Settings header: app rules.") }
    static var settingsDictationCheckbox: String { t("settings.dictationCheckbox", "Settings checkbox: dictation fallback.") }
    static var settingsRulesHint: String { t("settings.rulesHint", "Settings hint below rules table.") }
    static var settingsProgramButton: String { t("settings.programButton", "Button: program the pedal.") }
    static var settingsColApplication: String { t("settings.col.application", "Rules column header: application.") }
    static var settingsColShortcut: String { t("settings.col.shortcut", "Rules column header: shortcut.") }

    // Device status
    static var deviceNone: String { t("device.none", "Device status: none detected.") }
    /// %@ = device name.
    static func deviceDetected(name: String) -> String {
        String(format: t("device.detected", "Device status: detected. %@ name."), name)
    }
    static var deviceConfigVerified: String { t("device.config.verified", "Config status: verified.") }
    static var deviceConfigMismatch: String { t("device.config.mismatch", "Config status: must update.") }
    static var deviceConfigUnreadable: String { t("device.config.unreadable", "Config status: unreadable.") }

    // Alerts
    static var alertDeviceInfoTitle: String { t("alert.deviceInfo.title", "Device-info alert title.") }
    static var alertDeviceInfoNone: String { t("alert.deviceInfo.none", "Device-info alert: no device.") }
    static var alertFootswitchTitle: String { t("alert.footswitch.title", "Generic foot switch alert title.") }
    /// %@ = key name.
    static func alertProgrammed(key: String) -> String {
        String(format: t("alert.programmed", "Alert: programmed. %@ key."), key)
    }
    /// %@ = error detail.
    static func alertProgramFailed(error: String) -> String {
        String(format: t("alert.programFailed", "Alert: programming failed. %@ error."), error)
    }
    static var alertOK: String { t("alert.ok", "Generic OK button.") }

    // Open panel
    static var openPanelTitle: String { t("openPanel.title", "Open panel title for choosing an app.") }

    // Shortcut capture
    static var captureClickToSet: String { t("capture.clickToSet", "Capture: before a shortcut is set.") }
    static var capturePressShortcut: String { t("capture.pressShortcut", "Capture: while recording.") }
    static var captureUnsupportedKey: String { t("capture.unsupportedKey", "Capture: unsupported key.") }
    static var captureAddModifier: String { t("capture.addModifier", "Capture: modifier required.") }

    // About
    static var aboutWindowTitle: String { t("about.windowTitle", "About window title.") }
    static var aboutDescription: String { t("about.description", "About window description.") }
    /// %1$@ = short version, %2$@ = commit hash.
    static func aboutVersion(version: String, commit: String) -> String {
        String(format: t("about.version", "About version line. %1$@ version, %2$@ commit."), version, commit)
    }
    static var aboutCopyright: String { t("about.copyright", "About copyright line.") }
    static var aboutViewOnGitHub: String { t("about.viewOnGitHub", "About link: GitHub repo.") }
    static var aboutReportProblem: String { t("about.reportProblem", "About link: report a problem.") }
    static var aboutLicense: String { t("about.license", "About link: license.") }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds with no errors. (L10n is not yet referenced — that's fine; it must compile.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Footswitch/L10n.swift
git commit -m "feat: add L10n string catalog namespace"
```

---

## Task 6: Exclude Localizations from SwiftPM resources

The `.lproj` files are copied into the app by `package-app.sh`, not bundled by SwiftPM. Exclude them so SwiftPM doesn't process them into a resource bundle (which would change runtime lookup paths).

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the exclude**

In `Package.swift`, the `Footswitch` executable target's `exclude` array currently reads:

```swift
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
```

Replace it with:

```swift
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns", "Resources/Localizations"],
```

- [ ] **Step 2: Verify the package resolves and builds**

Run: `swift build`
Expected: builds with no errors and no "unhandled resource" warnings about Localizations.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: exclude Localizations from SwiftPM resource processing"
```

---

## Task 7: Localize MenuBarController

Replace inline literals with `L10n`, and add the About menu item driven by a new `openAbout` closure.

**Files:**
- Modify: `Sources/Footswitch/MenuBarController.swift`

- [ ] **Step 1: Add the openAbout stored property and init parameter**

In `MenuBarController`, change the stored closure section and init. Replace:

```swift
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "🦶"
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }
```

with:

```swift
    private let openSettings: () -> Void
    private let openAbout: () -> Void

    init(openSettings: @escaping () -> Void, openAbout: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openAbout = openAbout
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "🦶"
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }
```

- [ ] **Step 2: Initialize lastFireText from L10n**

Replace:

```swift
    private var lastFireText = "No presses yet"
```

with:

```swift
    private var lastFireText = L10n.menuNoPresses
```

- [ ] **Step 3: Localize setLastFire**

Replace:

```swift
    func setLastFire(app: String?, action: ResolvedAction) {
        lastFireText = "Last: \(app ?? "unknown") → \(describe(action))"
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }
```

with:

```swift
    func setLastFire(app: String?, action: ResolvedAction) {
        lastFireText = L10n.menuLastFire(app: app ?? L10n.appUnknown, action: describe(action))
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }
```

- [ ] **Step 4: Localize describe()**

Replace:

```swift
    private func describe(_ action: ResolvedAction) -> String {
        switch action {
        case .keyCombo(let c): return KeyComboFormatter.display(c)
        case .dictation: return "dictation"
        case .none: return "no action"
        }
    }
```

with:

```swift
    private func describe(_ action: ResolvedAction) -> String {
        switch action {
        case .keyCombo(let c): return KeyComboFormatter.display(c)
        case .dictation: return L10n.actionDictation
        case .none: return L10n.actionNone
        }
    }
```

- [ ] **Step 5: Localize the menu and add the About item**

Replace the body of `rebuildMenu(trusted:)`:

```swift
    private func rebuildMenu(trusted: Bool) {
        let menu = NSMenu()
        if !trusted {
            let warn = NSMenuItem(title: "⚠️ Needs Accessibility permission",
                                  action: #selector(grantPermission), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: lastFireText, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Footswitch",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Power glyph (⏻) via the SF Symbol so it renders crisply and tracks the
        // menu text color, instead of embedding the raw character in the title.
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }
```

with:

```swift
    private func rebuildMenu(trusted: Bool) {
        let menu = NSMenu()
        if !trusted {
            let warn = NSMenuItem(title: L10n.menuNeedsPermission,
                                  action: #selector(grantPermission), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: lastFireText, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let about = NSMenuItem(title: L10n.menuAbout,
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let settings = NSMenuItem(title: L10n.menuSettings,
                                  action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: L10n.menuQuit,
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Power glyph (⏻) via the SF Symbol so it renders crisply and tracks the
        // menu text color, instead of embedding the raw character in the title.
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }
```

- [ ] **Step 6: Add the showAbout action**

Immediately after the `@objc private func showSettings() { openSettings() }` line, add:

```swift
    @objc private func showAbout() { openAbout() }
```

- [ ] **Step 7: Build (will fail until AppDelegate passes openAbout — expected)**

Run: `swift build`
Expected: FAIL — `AppDelegate.swift` calls `MenuBarController(openSettings:)` without `openAbout:`. This is fixed in Task 9. Do not commit yet; proceed.

(If you prefer a green build per task, Task 9 is small — but committing here is acceptable since the next task fixes it. To keep commits green, complete Task 9 before committing this task. The plan commits Tasks 7+9 together — see Task 9 Step 3.)

---

## Task 8: Localize SettingsView

Replace every literal in `SettingsView.swift` with `L10n`. No structural changes.

**Files:**
- Modify: `Sources/Footswitch/SettingsView.swift`

- [ ] **Step 1: Window title**

Replace `window.title = "Footswitch Settings"` with `window.title = L10n.settingsWindowTitle`.

- [ ] **Step 2: Program button + headers + checkbox + hint**

Replace `NSButton(title: "Program pedal",` with `NSButton(title: L10n.settingsProgramButton,`.

Replace `let deviceHeader = makeHeader("Foot switch")` with `let deviceHeader = makeHeader(L10n.settingsHeaderDevice)`.

Replace `let defaultHeader = makeHeader("Default action")` with `let defaultHeader = makeHeader(L10n.settingsHeaderDefault)`.

Replace:
```swift
        dictationCheckbox = NSButton(checkboxWithTitle: "Start dictation when no app rule matches",
                                     target: self, action: #selector(dictationCheckboxChanged))
```
with:
```swift
        dictationCheckbox = NSButton(checkboxWithTitle: L10n.settingsDictationCheckbox,
                                     target: self, action: #selector(dictationCheckboxChanged))
```

Replace `let rulesHeader = makeHeader("App rules")` with `let rulesHeader = makeHeader(L10n.settingsHeaderRules)`.

Replace:
```swift
        let hint = NSTextField(labelWithString:
            "Press the pedal in an app below to send its shortcut. Other apps use the default action above.")
```
with:
```swift
        let hint = NSTextField(labelWithString: L10n.settingsRulesHint)
```

- [ ] **Step 3: Table column titles**

Replace `appCol.title = "Application"` with `appCol.title = L10n.settingsColApplication`.
Replace `keyCol.title = "Shortcut"` with `keyCol.title = L10n.settingsColShortcut`.

- [ ] **Step 4: Device status lines**

In `refreshDeviceStatus()`, replace:
```swift
            deviceStatusLabel.attributedStringValue = statusLine("⊘", "No supported foot switch detected", .secondaryLabelColor)
```
with:
```swift
            deviceStatusLabel.attributedStringValue = statusLine("⊘", L10n.deviceNone, .secondaryLabelColor)
```

Replace:
```swift
        deviceStatusLabel.attributedStringValue =
            statusLine("✓", "Detected pedal: \(detected.device.name)", .systemGreen)
```
with:
```swift
        deviceStatusLabel.attributedStringValue =
            statusLine("✓", L10n.deviceDetected(name: detected.device.name), .systemGreen)
```

Replace the three config-status literals:
```swift
            configStatusLabel.attributedStringValue =
                statusLine("✓", "Verified configuration", .systemGreen)
```
→ `statusLine("✓", L10n.deviceConfigVerified, .systemGreen)`
```swift
            configStatusLabel.attributedStringValue =
                statusLine("⚠", "Configuration must be updated", .systemYellow)
```
→ `statusLine("⚠", L10n.deviceConfigMismatch, .systemYellow)`
```swift
            configStatusLabel.attributedStringValue =
                statusLine("✗", "Unable to read configuration", .systemRed)
```
→ `statusLine("✗", L10n.deviceConfigUnreadable, .systemRed)`

- [ ] **Step 5: Alerts (device info + program)**

In `showDeviceInfo()`, replace:
```swift
        let info = FootswitchHIDController.deviceInfo() ?? "No supported foot switch is connected."
```
→ `let info = FootswitchHIDController.deviceInfo() ?? L10n.alertDeviceInfoNone`

Replace `alert.messageText = "Foot switch information"` with `alert.messageText = L10n.alertDeviceInfoTitle`.
Replace `alert.addButton(withTitle: "OK")` with `alert.addButton(withTitle: L10n.alertOK)` (both occurrences — in `showDeviceInfo` and `presentInfo`).

In `programPedal()`, replace:
```swift
            presentInfo("Programmed the foot switch to send \(baseConfig.triggerKey).")
```
→ `presentInfo(L10n.alertProgrammed(key: baseConfig.triggerKey))`
```swift
            presentInfo("Could not program the foot switch.\n\n\(error)")
```
→ `presentInfo(L10n.alertProgramFailed(error: "\(error)"))`

In `presentInfo(_:)`, replace `alert.messageText = "Foot switch"` with `alert.messageText = L10n.alertFootswitchTitle`.

- [ ] **Step 6: Open panel title**

In `addRule()`, replace `panel.title = "Choose an application"` with `panel.title = L10n.openPanelTitle`.

- [ ] **Step 7: ShortcutCaptureView strings**

Replace `flashHint("Unsupported key")` with `flashHint(L10n.captureUnsupportedKey)`.
Replace `flashHint("Add a modifier (⌘⌥⌃⇧)")` with `flashHint(L10n.captureAddModifier)`.

In `renderLive(_:)`, replace both `"Press shortcut…"` occurrences with `L10n.capturePressShortcut`:
```swift
        let glyphs = mods.isEmpty ? L10n.capturePressShortcut
            : KeyComboFormatter.display(KeyCombo(modifiers: mods, key: "")).trimmingCharacters(in: .whitespaces)
        label.stringValue = glyphs.isEmpty ? L10n.capturePressShortcut : glyphs
```

In `render()`, replace:
```swift
        if recording {
            label.stringValue = "Press shortcut…"
            label.textColor = .secondaryLabelColor
        } else if let combo, !combo.key.isEmpty {
            label.stringValue = KeyComboFormatter.display(combo)
        } else {
            label.stringValue = "Click to set"
            label.textColor = .secondaryLabelColor
        }
```
with:
```swift
        if recording {
            label.stringValue = L10n.capturePressShortcut
            label.textColor = .secondaryLabelColor
        } else if let combo, !combo.key.isEmpty {
            label.stringValue = KeyComboFormatter.display(combo)
        } else {
            label.stringValue = L10n.captureClickToSet
            label.textColor = .secondaryLabelColor
        }
```

- [ ] **Step 8: Build (still fails on AppDelegate from Task 7 — expected)**

Run: `swift build`
Expected: FAIL only on the `MenuBarController(openSettings:)` call in AppDelegate (Task 9). No errors originating in `SettingsView.swift`. Proceed to Task 9.

---

## Task 9: About window + AppDelegate wiring

Create the About window and wire `openAbout` through AppDelegate. This makes the build green again.

**Files:**
- Create: `Sources/Footswitch/AboutWindowController.swift`
- Modify: `Sources/Footswitch/AppDelegate.swift`

- [ ] **Step 1: Create AboutWindowController.swift**

Create `Sources/Footswitch/AboutWindowController.swift`:

```swift
import AppKit

/// A self-contained, non-resizable About window: icon, name, version+commit,
/// description, copyright, and link buttons (GitHub, report-a-problem, license).
/// Version/commit come from Info.plist; the commit hash is injected at package time.
@MainActor
final class AboutWindowController: NSWindowController {
    private static let repoURL = "https://github.com/ericfitz/footswitch"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L10n.aboutWindowTitle
        self.init(window: window)
        window.contentView = AboutWindowController.makeContentView()
        window.center()
    }

    // MARK: - Bundle values

    private static func shortVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static func commitHash() -> String {
        Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? "0000000"
    }

    private static func archString() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine
    }

    // MARK: - Content

    private static func makeContentView() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage ?? NSImage(named: "AppIcon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let name = label("Footswitch", font: .boldSystemFont(ofSize: 18))
        let version = label(
            L10n.aboutVersion(version: shortVersion(), commit: commitHash()),
            font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let desc = label(L10n.aboutDescription, font: .systemFont(ofSize: 12))
        desc.alignment = .center
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 3
        desc.preferredMaxLayoutWidth = 300
        let copyright = label(L10n.aboutCopyright, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

        let links = NSStackView(views: [
            linkButton(L10n.aboutViewOnGitHub, action: #selector(openRepo)),
            linkButton(L10n.aboutReportProblem, action: #selector(openIssue)),
            linkButton(L10n.aboutLicense, action: #selector(openLicense)),
        ])
        links.orientation = .horizontal
        links.spacing = 16
        links.alignment = .centerY

        let stack = NSStackView(views: [icon, name, version, desc, copyright, links])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private static func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        l.alignment = .center
        return l
    }

    /// A borderless, blue link-style button. Target is set in makeContentView via
    /// the shared controller — but since these statics have no instance, we route
    /// actions through the responder chain by giving the button a nil target and a
    /// selector handled by the window controller (set below in init wiring).
    private static func linkButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: nil, action: action)
        b.isBordered = false
        b.bezelStyle = .inline
        b.contentTintColor = .linkColor
        let attr = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: 12),
        ])
        b.attributedTitle = attr
        return b
    }

    // MARK: - Link actions

    @objc private func openRepo() {
        open(Self.repoURL)
    }

    @objc private func openLicense() {
        open("\(Self.repoURL)/blob/main/LICENSE")
    }

    @objc private func openIssue() {
        let body = """
        **Describe the problem:**


        **Environment (auto-filled):**
        - Footswitch version: \(Self.shortVersion()) (\(Self.commitHash()))
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Architecture: \(Self.archString())
        """
        var components = URLComponents(string: "\(Self.repoURL)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
```

Note on targets: the link buttons are created in a `static` factory, so they can't reference `self`. Wire their targets after the content view is built — update `convenience init()` accordingly in the next step.

- [ ] **Step 2: Wire button targets to the controller instance**

The static `linkButton` factory sets `target: nil`. Set real targets after init. Replace the `convenience init()` in `AboutWindowController.swift` with:

```swift
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L10n.aboutWindowTitle
        self.init(window: window)
        let content = AboutWindowController.makeContentView()
        window.contentView = content
        wireLinkTargets(in: content)
        window.center()
    }

    /// Point every link button's target at this controller (the static factory
    /// could not reference self).
    private func wireLinkTargets(in view: NSView) {
        for sub in view.subviews {
            if let button = sub as? NSButton { button.target = self }
            wireLinkTargets(in: sub)
        }
    }
```

- [ ] **Step 3: Wire AppDelegate — retain + open the About window, pass openAbout**

In `AppDelegate.swift`, add a stored property next to `settingsWindow`:

```swift
    private var settingsWindow: NSWindow?
```
becomes:
```swift
    private var settingsWindow: NSWindow?
    private var aboutWindowController: AboutWindowController?
```

Replace the `menuBar = MenuBarController(...)` line:
```swift
        menuBar = MenuBarController(openSettings: { [weak self] in self?.showSettings() })
```
with:
```swift
        menuBar = MenuBarController(
            openSettings: { [weak self] in self?.showSettings() },
            openAbout: { [weak self] in self?.showAbout() })
```

Add a `showAbout()` method after `showSettings()`:
```swift
    private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 4: Build — should now succeed**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all tests pass, including `LocalizationParityTests`.

- [ ] **Step 6: Commit Tasks 7–9 together (green build)**

```bash
git add Sources/Footswitch/MenuBarController.swift Sources/Footswitch/SettingsView.swift Sources/Footswitch/AboutWindowController.swift Sources/Footswitch/AppDelegate.swift
git commit -m "feat: add About window and localize menu bar + settings UI"
```

---

## Task 10: Packaging — copy .lproj and inject commit hash

Make `package-app.sh` copy the localization folders and write the real short SHA into the packaged Info.plist.

**Files:**
- Modify: `scripts/package-app.sh`

- [ ] **Step 1: Copy the .lproj folders and inject the commit hash**

In `scripts/package-app.sh`, find this block:

```bash
cp "$BIN" "$APP/Contents/MacOS/Footswitch"
cp "$ROOT/Sources/Footswitch/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/Footswitch/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
```

Replace it with:

```bash
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
```

- [ ] **Step 2: Run the packaging script (requires signing.env)**

Run: `./scripts/package-app.sh`
Expected: `Built .../build/Footswitch.app`. If `SIGN_IDENTITY` is unset, the script exits early with its own message — set up signing.env first (out of scope for this plan).

- [ ] **Step 3: Verify the .lproj folders and commit hash landed**

Run:
```bash
ls build/Footswitch.app/Contents/Resources/*.lproj -d
/usr/libexec/PlistBuddy -c "Print :GitCommitHash" build/Footswitch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" build/Footswitch.app/Contents/Info.plist
```
Expected: four `.lproj` dirs (ar, de, en, zh-Hans); the printed hash equals `git rev-parse --short HEAD`; the localizations array lists en/ar/zh-Hans/de.

- [ ] **Step 4: Commit**

```bash
git add scripts/package-app.sh
git commit -m "build: package localizations and inject git commit hash into Info.plist"
```

---

## Task 11: Manual verification (localized rendering + RTL)

No code — a manual checklist to confirm the machinery works end-to-end. `swift test` cannot render UI, so this is human verification.

**Files:** none.

- [ ] **Step 1: Verify English rendering**

Run: `open build/Footswitch.app`
Click the 🦶 menu bar item → confirm **About Footswitch**, **Settings…**, **Quit Footswitch** appear in English. Open About → confirm version line shows `Version 1.0.1 (<sha>)`, the three links open the repo, a prefilled issue, and the LICENSE.

- [ ] **Step 2: Verify German (long words)**

Run:
```bash
defaults write com.github.ericfitz.footswitch AppleLanguages '("de")'
open build/Footswitch.app
```
Confirm menu and Settings render in German; check that long German strings (e.g. "Bedienungshilfen-Berechtigung erforderlich", "Modifikatortaste hinzufügen") are not clipped. Note any clipped fields.

- [ ] **Step 3: Verify Simplified Chinese (CJK)**

Run:
```bash
defaults write com.github.ericfitz.footswitch AppleLanguages '("zh-Hans")'
open build/Footswitch.app
```
Confirm CJK glyphs render correctly in menu, Settings, and About.

- [ ] **Step 4: Verify Arabic (RTL)**

Run:
```bash
defaults write com.github.ericfitz.footswitch AppleLanguages '("ar")'
open build/Footswitch.app
```
Confirm the UI mirrors: Settings controls right-aligned, the About link row reversed. Inspect the RTL audit checklist items from the spec — `statusLine()` symbol/text order, detected/config rows, table column order, ShortcutCaptureView label alignment. Note any item that does not mirror correctly (these become follow-up fixes; the design flagged the hand-built `statusLine` and capture view as at-risk).

- [ ] **Step 5: Restore language and clean up**

Run:
```bash
defaults delete com.github.ericfitz.footswitch AppleLanguages
```

- [ ] **Step 6: Record findings**

If any RTL/clipping issues were found, note them in the PR description or a follow-up issue. No commit (no files changed).

---

## Self-Review Notes

- **Spec coverage:** Info.plist keys (T1), en Base (T2), ar/zh-Hans/de (T3), parity test (T4), L10n namespace (T5), SwiftPM exclude (T6), menu+About item & string extraction (T7/T8), About window with version/commit/links/issue-body (T9), packaging copy + SHA injection (T10), RTL/CJK/German manual audit (T11). All spec sections mapped.
- **Type consistency:** `MenuBarController.init(openSettings:openAbout:)` matches the call in AppDelegate (T9). `L10n` accessor names used in T7/T8/T9 all defined in T5. `GitCommitHash` key consistent across T1/T9/T10. `repoURL` base reused for repo/license/issue URLs.
- **Out-of-scope honored:** no native translation review, no extra locales, issue-body template stays English.
