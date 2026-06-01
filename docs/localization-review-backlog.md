# Localization review backlog (native review needed)

Generated from a 3-source review: gpt-5-codex + a blind Claude-Sonnet pass,
adjudicated by a Claude-Opus panel. The 23 highest-confidence fixes (objective
errors + clearly Apple-native terminology where 2+ sources agreed) were applied
directly. **Everything below was NOT applied** — it is either a single-source
stylistic preference or an adjudicated toss-up. None of the three models are
native speakers, so these are candidates for a future native-speaker review,
not confirmed defects. Finnish (fi) was dropped entirely.

## Native review status

- **Thai (th)** — ✅ reviewed by a native speaker, who confirmed all 5 of
  gpt-5-codex's suggestions were improvements. All 5 applied; Thai is resolved and
  its entries have been removed from the tiers below.

## Tier 1 — both automated reviewers flagged, but adjudication rejected the change

These had two independent flags; worth a native look first.

- **da / `capture.addModifier`** — gpt5: `Tilføj en kombitast (⌘⌥⌃⇧)`  ·  sonnet: `Tilføj en modifikatortast (⌘⌥⌃⇧)`
- **de / `capture.addModifier`** — gpt5: `Sondertaste hinzufügen (⌘⌥⌃⇧)`  ·  sonnet: `Zusatztaste hinzufügen (⌘⌥⌃⇧)`
- **de / `settings.rulesHint`** — gpt5: `Betätigen Sie den Fußschalter in einer unten aufgeführten App, um den zugehörigen Tastaturkurzbefehl zu senden. Andere Apps verwenden die Standardaktion oben.`  ·  sonnet: `Fußschalter in einer der untenstehenden Apps betätigen, um deren Kurzbefehl zu senden. Andere Apps verwenden die Standardaktion oben.`
- **el / `capture.addModifier`** — gpt5: `Προσθέστε πλήκτρο τροποποίησης (⌘⌥⌃⇧)`  ·  sonnet: `Προσθέστε πλήκτρο τροποποίησης (⌘⌥⌃⇧)`
- **es / `about.description`** — gpt5: `Asigna tu pedal USB a funciones rápidas de teclado para cada app.`  ·  sonnet: `Asigna tu pedal USB a atajos de teclado, por aplicación.`
- **es / `capture.clickToSet`** — gpt5: `Haz clic para definir`  ·  sonnet: `Clic para establecer`
- **es / `settings.rulesHint`** — gpt5: `Pulsa el pedal en una app de la lista para enviar su función rápida de teclado. Las demás apps usan la acción predeterminada de arriba.`  ·  sonnet: `Pulsa el pedal en una aplicación de abajo para enviar su atajo. Las demás aplicaciones usan la acción predeterminada de arriba.`
- **he / `settings.dictationCheckbox`** — gpt5: `הפעל הכתבה כשאין כלל תואם לאפליקציה`  ·  sonnet: `הפעל הכתבה כאשר אין כלל אפליקציה תואם`
- **id / `capture.addModifier`** — gpt5: `Tambahkan tombol pengubah (⌘⌥⌃⇧)`  ·  sonnet: `Tambahkan tombol modifier (⌘⌥⌃⇧)`
- **it / `capture.pressShortcut`** — gpt5: `Premi una combinazione di tasti…`  ·  sonnet: `Premi l'abbreviazione…`
- **it / `menu.needsPermission`** — gpt5: `⚠️ È necessaria l'autorizzazione di Accessibilità`  ·  sonnet: `⚠️ Richiede l'autorizzazione Accessibilità`
- **it / `settings.col.shortcut`** — gpt5: `Abbreviazione da tastiera`  ·  sonnet: `Abbreviazione`
- **ja / `alert.programmed`** — gpt5: `%@を送信するようにフットスイッチを設定しました。`  ·  sonnet: `フットスイッチを %@ を送信するようにプログラムしました。`
- **ja / `settings.rulesHint`** — gpt5: `以下のいずれかのアプリでペダルを踏むと、そのキーボードショートカットが送信されます。他のアプリでは上のデフォルトのアクションが使用されます。`  ·  sonnet: `下のアプリでペダルを押すとショートカットが送信されます。他のアプリは上のデフォルトのアクションを使用します。`
- **nb / `capture.pressShortcut`** — gpt5: `Trykk på en tastatursnarvei…`  ·  sonnet: `Trykk en snarvei…`
- **nl / `capture.addModifier`** — gpt5: `Voeg een speciale toets toe (⌘⌥⌃⇧)`  ·  sonnet: `Voeg een wijzigingstoets toe (⌘⌥⌃⇧)`
- **pt-BR / `capture.addModifier`** — gpt5: `Adicione uma tecla modificadora (⌘⌥⌃⇧)`  ·  sonnet: `Adicionar um modificador (⌘⌥⌃⇧)`
- **pt-BR / `capture.unsupportedKey`** — gpt5: `Tecla incompatível`  ·  sonnet: `Tecla sem suporte`
- **pt-PT / `capture.addModifier`** — gpt5: `Adicione uma tecla modificadora (⌘⌥⌃⇧)`  ·  sonnet: `Adicionar um modificador (⌘⌥⌃⇧)`
- **sv / `menu.needsPermission`** — gpt5: `⚠️ Behörighet till Hjälpmedel krävs`  ·  sonnet: `⚠️ Kräver åtkomst till Hjälpmedel`
- **zh-Hant / `settings.dictationCheckbox`** — gpt5: `沒有符合的 App 規則時開始聽寫`  ·  sonnet: `未符合任何應用程式規則時啟動語音輸入`

## Tier 2 — single-source stylistic suggestions (one reviewer only)

Lower priority; one model's terminology preference.

- ar / `about.description` (gpt-5-codex): `اربط مفتاح القدم عبر USB باختصارات لوحة المفاتيح، لكل تطبيق.`
- ar / `capture.pressShortcut` (gpt-5-codex): `اضغط على اختصار…`
- ar / `menu.needsPermission` (gpt-5-codex): `⚠️ يلزم إذن تسهيلات الاستخدام`
- ar / `settings.rulesHint` (gpt-5-codex): `اضغط على الدواسة أثناء استخدام أحد التطبيقات أدناه لإرسال اختصاره. تستخدم التطبيقات الأخرى الإجراء الافتراضي أعلاه.`
- cs / `about.viewOnGitHub` (gpt-5-codex): `Zobrazit na GitHubu`
- cs / `capture.addModifier` (gpt-5-codex): `Přidejte modifikační klávesu (⌘⌥⌃⇧)`
- cs / `settings.rulesHint` (gpt-5-codex): `Stisknutím pedálu v některé z níže uvedených aplikací odešlete její klávesovou zkratku. Ostatní aplikace použijí výchozí akci uvedenou výše.`
- da / `capture.pressShortcut` (gpt-5-codex): `Tryk på en tastaturgenvej…`
- da / `capture.unsupportedKey` (gpt-5-codex): `Tasten understøttes ikke`
- da / `menu.quit` (gpt-5-codex): `Slut Footswitch`
- da / `settings.windowTitle` (gpt-5-codex): `Indstillinger til Footswitch`
- de / `capture.pressShortcut` (gpt-5-codex): `Tastaturkurzbefehl drücken…`
- de / `settings.col.shortcut` (gpt-5-codex): `Tastaturkurzbefehl`
- el / `about.description` (gpt-5-codex): `Αντιστοιχίστε τον ποδοδιακόπτη USB σας σε συντομεύσεις πληκτρολογίου, ανά εφαρμογή.`
- el / `about.windowTitle` (gpt-5-codex): `Πληροφορίες για το Footswitch`
- el / `alert.deviceInfo.none` (gpt-5-codex): `Δεν είναι συνδεδεμένος υποστηριζόμενος ποδοδιακόπτης.`
- el / `alert.deviceInfo.title` (gpt-5-codex): `Πληροφορίες ποδοδιακόπτη`
- el / `alert.footswitch.title` (gpt-5-codex): `Ποδοδιακόπτης`
- el / `alert.programFailed` (gpt-5-codex): `Δεν ήταν δυνατός ο προγραμματισμός του ποδοδιακόπτη.\n\n%@`
- el / `alert.programmed` (gpt-5-codex): `Ο ποδοδιακόπτης προγραμματίστηκε να στέλνει %@.`
- el / `device.none` (gpt-5-codex): `Δεν εντοπίστηκε υποστηριζόμενος ποδοδιακόπτης`
- el / `menu.about` (gpt-5-codex): `Πληροφορίες για το Footswitch`
- el / `settings.dictationCheckbox` (gpt-5-codex): `Έναρξη υπαγόρευσης όταν δεν ταιριάζει κανόνας εφαρμογής`
- el / `settings.header.device` (gpt-5-codex): `Ποδοδιακόπτης`
- es / `capture.addModifier` (gpt-5-codex): `Añade una tecla modificadora (⌘⌥⌃⇧)`
- es / `capture.pressShortcut` (gpt-5-codex): `Pulsa una función rápida de teclado…`
- es / `settings.col.shortcut` (gpt-5-codex): `Función rápida`
- es-419 / `capture.addModifier` (gpt-5-codex): `Agrega una tecla modificadora (⌘⌥⌃⇧)`
- es-419 / `settings.rulesHint` (gpt-5-codex): `Presiona el pedal en una de las apps de abajo para enviar su atajo. Las demás apps usan la acción predeterminada de arriba.`
- fr / `capture.addModifier` (gpt-5-codex): `Ajoutez une touche de modification (⌘⌥⌃⇧)`
- fr / `capture.pressShortcut` (gpt-5-codex): `Appuyez sur un raccourci clavier…`
- fr / `menu.noPresses` (gpt-5-codex): `Aucun appui pour l’instant`
- fr / `settings.col.shortcut` (gpt-5-codex): `Raccourci clavier`
- fr / `settings.rulesHint` (gpt-5-codex): `Appuyez sur la pédale dans l’une des apps ci-dessous pour envoyer son raccourci clavier. Les autres apps utilisent l’action par défaut ci-dessus.`
- fr-CA / `settings.rulesHint` (gpt-5-codex): `Appuyez sur la pédale dans l’une des apps ci-dessous pour envoyer son raccourci clavier. Les autres apps utilisent l’action par défaut ci-dessus.`
- he / `about.description` (gpt-5-codex): `מפה את דוושת הרגל בחיבור USB לקיצורי מקלדת, לפי אפליקציה.`
- he / `capture.addModifier` (gpt-5-codex): `הוסף מקש צירוף (⌘⌥⌃⇧)`
- he / `capture.pressShortcut` (gpt-5-codex): `הקש קיצור מקלדת…`
- he / `settings.rulesHint` (gpt-5-codex): `לחץ על הדוושה באחת מהאפליקציות שלהלן כדי לשלוח את קיצור המקלדת שלה. אפליקציות אחרות משתמשות בפעולת ברירת המחדל שלמעלה.`
- id / `about.description` (gpt-5-codex): `Petakan sakelar kaki USB Anda ke pintasan papan ketik, untuk tiap aplikasi.`
- id / `alert.deviceInfo.none` (gpt-5-codex): `Tidak ada sakelar kaki yang didukung yang terhubung.`
- id / `alert.deviceInfo.title` (gpt-5-codex): `Informasi sakelar kaki`
- id / `alert.footswitch.title` (gpt-5-codex): `Sakelar kaki`
- id / `alert.programFailed` (gpt-5-codex): `Tidak dapat memprogram sakelar kaki.\n\n%@`
- id / `alert.programmed` (gpt-5-codex): `Sakelar kaki berhasil diprogram untuk mengirim %@.`
- id / `capture.pressShortcut` (gpt-5-codex): `Tekan pintasan papan ketik…`
- id / `device.none` (gpt-5-codex): `Tidak terdeteksi sakelar kaki yang didukung`
- id / `menu.noPresses` (gpt-5-codex): `Pedal belum pernah ditekan`
- id / `settings.header.device` (gpt-5-codex): `Sakelar kaki`
- id / `settings.rulesHint` (gpt-5-codex): `Tekan pedal saat salah satu aplikasi di bawah ini aktif untuk mengirim pintasan papan ketiknya. Aplikasi lain menggunakan tindakan default di atas.`
- it / `about.description` (gpt-5-codex): `Associa il pedale USB alle abbreviazioni da tastiera, app per app.`
- it / `alert.deviceInfo.title` (gpt-5-codex): `Informazioni sul pedale`
- it / `settings.programButton` (gpt-5-codex): `Programma il pedale`
- it / `settings.rulesHint` (gpt-5-codex): `Premi il pedale in una delle app qui sotto per inviare la relativa abbreviazione da tastiera. Le altre app usano l'azione predefinita indicata sopra.`
- ja / `alert.programFailed` (gpt-5-codex): `フットスイッチを設定できませんでした。\n\n%@`
- ja / `capture.pressShortcut` (gpt-5-codex): `キーボードショートカットを入力…`
- ja / `settings.programButton` (gpt-5-codex): `ペダルを設定`
- ko / `about.windowTitle` (gpt-5-codex): `Footswitch에 관하여`
- ko / `menu.about` (gpt-5-codex): `Footswitch에 관하여`
- ko / `menu.noPresses` (gpt-5-codex): `아직 누른 적 없음`
- nb / `capture.addModifier` (gpt-5-codex): `Legg til en spesialtast (⌘⌥⌃⇧)`
- nb / `settings.header.default` (gpt-5-codex): `Standardhandling`
- nb / `settings.rulesHint` (gpt-5-codex): `Trykk på pedalen i en av appene nedenfor for å sende appens tastatursnarvei. Andre apper bruker standardhandlingen ovenfor.`
- nl / `capture.pressShortcut` (gpt-5-codex): `Druk op een toetscombinatie…`
- nl / `settings.rulesHint` (gpt-5-codex): `Druk op het pedaal in een van de onderstaande apps om de toetscombinatie te verzenden. Andere apps gebruiken de bovenstaande standaardactie.`
- pl / `about.viewOnGitHub` (gpt-5-codex): `Zobacz w serwisie GitHub`
- pl / `about.windowTitle` (gpt-5-codex): `O programie Footswitch`
- pl / `capture.addModifier` (gpt-5-codex): `Dodaj klawisz modyfikujący (⌘⌥⌃⇧)`
- pl / `capture.pressShortcut` (gpt-5-codex): `Naciśnij skrót klawiszowy…`
- pl / `menu.about` (gpt-5-codex): `O programie Footswitch`
- pl / `settings.rulesHint` (gpt-5-codex): `Naciśnij pedał w jednej z poniższych aplikacji, aby wysłać jej skrót klawiszowy. Pozostałe aplikacje używają powyższej akcji domyślnej.`
- pt-BR / `capture.pressShortcut` (gpt-5-codex): `Pressione um atalho de teclado…`
- pt-BR / `menu.noPresses` (gpt-5-codex): `Nenhum acionamento ainda`
- pt-BR / `settings.rulesHint` (gpt-5-codex): `Pressione o pedal em um dos apps abaixo para enviar o atalho desse app. Os outros apps usam a ação padrão acima.`
- pt-PT / `about.windowTitle` (gpt-5-codex): `Acerca do Footswitch`
- pt-PT / `capture.pressShortcut` (gpt-5-codex): `Prima um atalho de teclado…`
- pt-PT / `menu.about` (gpt-5-codex): `Acerca do Footswitch`
- pt-PT / `settings.col.shortcut` (gpt-5-codex): `Atalho de teclado`
- pt-PT / `settings.rulesHint` (gpt-5-codex): `Prima o pedal numa das aplicações abaixo para enviar o respetivo atalho de teclado. As outras aplicações utilizam a ação predefinida acima.`
- ru / `about.description` (gpt-5-codex): `Назначайте USB-педали сочетания клавиш отдельно для каждого приложения.`
- ru / `capture.addModifier` (gpt-5-codex): `Добавьте клавишу-модификатор (⌘⌥⌃⇧)`
- ru / `settings.rulesHint` (gpt-5-codex): `Нажмите педаль в одном из перечисленных ниже приложений, чтобы отправить назначенное ему сочетание клавиш. В остальных приложениях используется действие по умолчанию выше.`
- sv / `about.description` (gpt-5-codex): `Koppla din USB-fotpedal till kortkommandon för varje app.`
- sv / `capture.addModifier` (gpt-5-codex): `Lägg till en specialtangent (⌘⌥⌃⇧)`
- sv / `menu.noPresses` (gpt-5-codex): `Inga tryck ännu`
- sv / `settings.dictationCheckbox` (gpt-5-codex): `Starta diktering när ingen regel för appen matchar`
- sv / `settings.header.rules` (gpt-5-codex): `Appregler`
- sv / `settings.programButton` (gpt-5-codex): `Programmera pedalen`
- sv / `settings.rulesHint` (gpt-5-codex): `Tryck på pedalen i någon av apparna nedan för att skicka appens kortkommando. Andra appar använder standardåtgärden ovan.`
- tr / `about.description` (gpt-5-codex): `USB ayak pedalınızı uygulamaya göre klavye kestirmelerine eşleyin.`
- tr / `capture.addModifier` (gpt-5-codex): `Niteleme tuşu ekleyin (⌘⌥⌃⇧)`
- tr / `capture.pressShortcut` (gpt-5-codex): `Bir klavye kestirmesine basın…`
- tr / `settings.dictationCheckbox` (gpt-5-codex): `Eşleşen uygulama kuralı olmadığında dikteyi başlat`
- tr / `settings.rulesHint` (gpt-5-codex): `Aşağıdaki uygulamalardan birinde pedala basarak klavye kestirmesini gönderin. Diğer uygulamalar yukarıdaki varsayılan eylemi kullanır.`
- uk / `about.description` (gpt-5-codex): `Призначте USB-педаль клавіатурним скороченням для кожної програми.`
- uk / `capture.addModifier` (gpt-5-codex): `Додайте клавішу-модифікатор (⌘⌥⌃⇧)`
- uk / `capture.pressShortcut` (gpt-5-codex): `Натисніть клавіатурне скорочення…`
- uk / `settings.col.shortcut` (gpt-5-codex): `Клавіатурне скорочення`
- uk / `settings.rulesHint` (gpt-5-codex): `Натисніть педаль в одній із наведених нижче програм, щоб надіслати її клавіатурне скорочення. В інших програмах використовується типова дія вище.`
- vi / `about.description` (gpt-5-codex): `Gán bàn đạp chân USB của bạn cho các phím tắt, theo từng ứng dụng.`
- vi / `alert.deviceInfo.none` (gpt-5-codex): `Không có bàn đạp chân được hỗ trợ nào được kết nối.`
- vi / `capture.clickToSet` (gpt-5-codex): `Bấm để đặt`
- vi / `settings.rulesHint` (gpt-5-codex): `Nhấn bàn đạp khi đang dùng một trong các ứng dụng bên dưới để gửi phím tắt của ứng dụng đó. Các ứng dụng khác sử dụng tác vụ mặc định ở trên.`
- zh-HK / `capture.addModifier` (gpt-5-codex): `請加入變更鍵 (⌘⌥⌃⇧)`
- zh-HK / `menu.needsPermission` (gpt-5-codex): `⚠️ 需要輔助使用權限`
- zh-HK / `settings.dictationCheckbox` (gpt-5-codex): `沒有任何 App 規則相符時開始聽寫`
- zh-Hans / `menu.lastFire` (gpt-5-codex): `上次：%1$@ → %2$@`
- zh-Hans / `menu.noPresses` (gpt-5-codex): `尚无踩踏记录`
- zh-Hans / `settings.rulesHint` (gpt-5-codex): `在下方任一应用中踩下踏板，即可发送该应用的快捷键。其他应用使用上方的默认操作。`
- zh-Hant / `action.dictation` (gpt-5-codex): `聽寫`
- cs / `action.dictation` (sonnet): `Diktování`
- cs / `app.unknown` (sonnet): `neznámá aplikace`
- cs / `menu.needsPermission` (sonnet): `⚠️ Vyžaduje oprávnění Usnadnění přístupu`
- cs / `settings.col.shortcut` (sonnet): `Zkratka`
- cs / `settings.dictationCheckbox` (sonnet): `Spustit diktování, pokud neodpovídá žádné pravidlo aplikace`
- da / `about.description` (sonnet): `Knyt din USB-fodpedal til tastaturgenveje, per app.`
- da / `menu.needsPermission` (sonnet): `⚠️ Kræver tilladelse til Tilgængelighed`
- da / `settings.col.application` (sonnet): `App`
- da / `settings.col.shortcut` (sonnet): `Genvej`
- de / `about.description` (sonnet): `USB-Fußschalter pro App Tastaturkürzeln zuordnen.`
- de / `action.dictation` (sonnet): `Diktieren`
- de / `capture.clickToSet` (sonnet): `Klicken zum Festlegen`
- de / `settings.col.application` (sonnet): `App`
- el / `menu.quit` (sonnet): `Έξοδος από Footswitch`
- el / `settings.col.shortcut` (sonnet): `Συντόμευση`
- es / `menu.settings` (sonnet): `Configuración…`
- es / `settings.dictationCheckbox` (sonnet): `Iniciar dictado cuando no coincida ninguna regla de aplicación`
- es / `settings.header.rules` (sonnet): `Reglas por aplicación`
- es / `settings.windowTitle` (sonnet): `Configuración de Footswitch`
- es-419 / `about.reportProblem` (sonnet): `Informar un problema`
- fr / `about.description` (sonnet): `Associez votre pédale USB à des raccourcis clavier, par application.`
- fr / `capture.clickToSet` (sonnet): `Cliquez pour définir`
- fr / `menu.needsPermission` (sonnet): `⚠️ Autorisation Accessibilité requise`
- fr / `settings.header.rules` (sonnet): `Règles par application`
- fr-CA / `capture.clickToSet` (sonnet): `Cliquer pour configurer`
- fr-CA / `settings.header.rules` (sonnet): `Règles par appli`
- he / `about.reportProblem` (sonnet): `דיווח על בעיה`
- he / `capture.clickToSet` (sonnet): `לחיצה להגדרה`
- id / `action.dictation` (sonnet): `Dikte`
- id / `settings.dictationCheckbox` (sonnet): `Mulai Dikte jika tidak ada aturan aplikasi yang cocok`
- it / `app.unknown` (sonnet): `sconosciuto`
- it / `menu.noPresses` (sonnet): `Nessuna pressione ancora`
- ja / `about.viewOnGitHub` (sonnet): `GitHubで開く`
- ja / `device.config.verified` (sonnet): `設定は確認済みです`
- ja / `menu.needsPermission` (sonnet): `⚠️ アクセシビリティの権限が必要`
- ja / `settings.dictationCheckbox` (sonnet): `アプリのルールが一致しない場合に音声入力を使用する`
- ja / `settings.windowTitle` (sonnet): `Footswitch の設定`
- ko / `capture.pressShortcut` (sonnet): `단축키를 누르세요…`
- ko / `openPanel.title` (sonnet): `앱 선택`
- ko / `settings.col.application` (sonnet): `앱`
- nb / `settings.col.shortcut` (sonnet): `Snarvei`
- nl / `about.description` (sonnet): `Koppel je USB-voetschakelaar aan toetscombinaties, per app.`
- nl / `menu.needsPermission` (sonnet): `⚠️ Vereist toegankelijkheidstoestemming`
- nl / `menu.quit` (sonnet): `Sluit Footswitch af`
- nl / `settings.col.application` (sonnet): `Toepassing`
- pl / `app.unknown` (sonnet): `nieznane`
- pl / `settings.col.shortcut` (sonnet): `Skrót`
- pl / `settings.header.device` (sonnet): `Pedał`
- pt-BR / `menu.settings` (sonnet): `Preferências…`
- pt-BR / `settings.windowTitle` (sonnet): `Preferências do Footswitch`
- ru / `capture.clickToSet` (sonnet): `Нажмите, чтобы задать`
- ru / `settings.programButton` (sonnet): `Запрограммировать педаль`
- sv / `settings.col.application` (sonnet): `App`
- uk / `menu.needsPermission` (sonnet): `⚠️ Потрібен дозвіл на доступність`
- uk / `openPanel.title` (sonnet): `Виберіть програму`
- vi / `openPanel.title` (sonnet): `Chọn ứng dụng`
- vi / `settings.header.rules` (sonnet): `Quy tắc ứng dụng`
- zh-HK / `alert.ok` (sonnet): `確定`
- zh-Hans / `alert.ok` (sonnet): `好的`
- zh-Hans / `capture.addModifier` (sonnet): `添加修饰键 (⌘⌥⌃⇧)`
- zh-Hans / `capture.clickToSet` (sonnet): `点按以设定`
- zh-Hant / `alert.ok` (sonnet): `確定`
- zh-Hant / `capture.addModifier` (sonnet): `加入修飾鍵 (⌘⌥⌃⇧)`
- zh-Hant / `capture.pressShortcut` (sonnet): `按下快速鍵…`
- zh-Hant / `settings.header.rules` (sonnet): `應用程式規則`
- zh-Hant / `settings.rulesHint` (sonnet): `在下列應用程式中踩踏腳踏開關，即可傳送對應的快速鍵。其他應用程式使用上方的預設動作。`
