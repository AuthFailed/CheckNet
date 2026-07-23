# CheckNet — план развития

Цель: **лучшее приложение для диагностики сети на Apple-платформах** — нативное на iPhone, iPad и Mac,
честное в объяснениях, с проверками, которых нет у конкурентов (Speedtest, Network Analyzer, iNetTools).

Задачи живут в [Issues](https://github.com/AuthFailed/CheckNet/issues) и сгруппированы по вехам.
Этот файл — про **порядок и зависимости**: почему M2 идёт раньше M3, а M4 — раньше M6.

---

## Где мы сейчас

Обновлено 2026-07-23. **M1–M4 и M6 закрыты; остаётся M5 (платформенные интеграции).** Ниже
фактическое состояние; таблицы вех ниже отмечают каждую задачу отдельно колонкой «Статус».

- **27 инструментов** реализованы; **заглушек «скоро» не осталось**. Два Wi-Fi-инструмента
  работают только на macOS (CoreWLAN); на iOS они показывают заглушку «доступно на Mac».
  Добавлены за эту веху: bufferbloat (#46), геолокация IP и World Ping (#47), Wi-Fi на macOS (#48).
- **Ядро** `Packages/NetworkKit` — **207 XCTest-тестов** против реальных хостов и парсеров
  (парсеры DNS/X.509/MMDB и геолокация покрыты детерминированно). В CI: детерминированные —
  блокирующим гейтом, сетевые — информационно (см. «Как тесты гоняются в CI»).
- **App + Shared** — ~11 000 строк; появился таргет **`CheckNetTests` (104 теста)** на логику
  App/Shared (M4 #37). Чистые куски (`HostSharing`, `IPAddress`, `LaunchArguments`,
  `ScheduleRule`, `HistoryCSV`, фабрики `CheckRecord`, `ToolRunModel`) вынесены в `Shared/`.
- **Локализация** — string catalog, 13 языков. Осталась вторая категория: строки движков,
  которые ищутся через `LocalizedStringKey(переменная)` и в любой локали остаются русскими
  (issue #60).
- **iPad/macOS** — адаптивная раскладка есть: `NavigationSplitView` + `.sidebarAdaptable`,
  единый `ToolScaffold` с ограничением ширины, `MenuBarExtra` / команды / сцена Settings на Mac,
  landscape на iPhone (M2 #14–#19 закрыты).
- **Haptics** есть (`App/Common/Haptics.swift` + тумблер в настройках); доступность улучшена —
  статус передаётся формой и словом, а не только цветом, иконкам добавлены лейблы (#20, #21);
  Dynamic Type, reduce-motion и `numericText` доведены (M3 закрыта).
- Виджет главного экрана **удалён сознательно**: расширение публикует Live Activity и
  пользовательские контролы (#41), но в галерею домашнего экрана — ничего; после установки
  приложение ничего не навязывает.

---

## Логика порядка

```
M1 Стабилизация ──┬─→ M2 Адаптивный UI ──→ M3 UX-полировка
                  │            │                 │
                  └─→ M4 Архитектура и тесты ────┘
                               │
                               ├─→ M5 Платформенные интеграции
                               └─→ M6 Новые инструменты
```

**Статус вех:** M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 почти закрыта (#39–#44 ✅, остаётся P3 #45) · M6 ✅ (инструменты сделаны; #49 — живой бэклог идей).

- **M1 первым** — там блокеры релиза (privacy manifest), потеря данных (гонка в истории) и
  неработающий CI. Строить новое на нестабильном фундаменте дороже.
- **M2 раньше M3** — `ToolScaffold` и `NavigationSplitView` переписывают каркас всех 22 экранов.
  Полировать пустые состояния и анимации до этого — переделывать дважды.
- **M4 параллельно M2/M3** — `ToolRunModel` и `ToolScaffold` это две половины одного рефакторинга;
  вынос логики в NetworkKit делает её тестируемой.
- **M5 и M6 после M4** — новые инструменты и фоновые сценарии садятся на `CheckRunner`,
  единую обработку ошибок и `ToolScaffold`, иначе каждый новый экран снова копирует 200 строк.

---

## M1 · Стабилизация и релиз ✅

Без этого приложение нельзя выпускать: блокеры App Store, потеря данных, нелокализованный UI.

**Статус: завершена ✅** (все задачи закрыты).

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#5](https://github.com/AuthFailed/CheckNet/issues/5) | `PrivacyInfo.xcprivacy` — блокер ревью App Store | P0 | ✅ |
| [#6](https://github.com/AuthFailed/CheckNet/issues/6) | CI: гонять `swift test` и собирать macOS | P0 | ✅ |
| [#7](https://github.com/AuthFailed/CheckNet/issues/7) | Починить сборку macOS-таргета | P0 | ✅ |
| [#8](https://github.com/AuthFailed/CheckNet/issues/8) | История: экспорт CSV/JSON выполняется в `body` | P0 | ✅ |
| [#9](https://github.com/AuthFailed/CheckNet/issues/9) | История: захардкоженная `ru_RU`-локаль | P0 | ✅ |
| [#10](https://github.com/AuthFailed/CheckNet/issues/10) | 46 непереведённых ключей в каталоге строк | P0 | ✅ |
| [#11](https://github.com/AuthFailed/CheckNet/issues/11) | `SharedStore`: гонка при записи истории | P0 | ✅ |
| [#13](https://github.com/AuthFailed/CheckNet/issues/13) | Профили сети не работают без Wi-Fi-entitlement | P1 | ✅ |

**Порядок внутри вехи:** #7 → #6 (CI не может собирать сломанный таргет) → остальное параллельно.

---

## M2 · Адаптивный UI (iPad + macOS) ✅

Главный визуальный долг. Сейчас это «растянутый айфон» на всех широких экранах.

**Статус: завершена ✅** (все задачи закрыты).

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#14](https://github.com/AuthFailed/CheckNet/issues/14) | `NavigationSplitView` + `.tabViewStyle(.sidebarAdaptable)` | P1 | ✅ |
| [#15](https://github.com/AuthFailed/CheckNet/issues/15) | `ToolScaffold` — единый контейнер с ограничением ширины | P1 | ✅ |
| [#16](https://github.com/AuthFailed/CheckNet/issues/16) | Фиксированные ширины/высоты, ломающие Dynamic Type | P1 | ✅ |
| [#17](https://github.com/AuthFailed/CheckNet/issues/17) | Sheets без `presentationDetents` | P2 | ✅ |
| [#18](https://github.com/AuthFailed/CheckNet/issues/18) | macOS: `MenuBarExtra`, `.commands`, сцена `Settings` | P1 | ✅ |
| [#19](https://github.com/AuthFailed/CheckNet/issues/19) | Landscape на iPhone | P2 | ✅ |

**Порядок:** #15 (каркас) → #14 (навигация поверх него) → #16 → #17/#19 → #18 (зависит от #7).

---

## M3 · UX-полировка ✅

То, что отличает «работает» от «приятно пользоваться».

**Статус: завершена ✅** (все задачи закрыты). Большая часть закрыта ранними PR; последним доделан
Dynamic Type (#22) — единственный оставшийся хардкод размера шрифта.

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#20](https://github.com/AuthFailed/CheckNet/issues/20) | Haptics — сейчас 0 вызовов на весь проект | P1 | ✅ |
| [#21](https://github.com/AuthFailed/CheckNet/issues/21) | Доступность: статус только цветом, иконки без лейблов | P1 | ✅ |
| [#22](https://github.com/AuthFailed/CheckNet/issues/22) | Dynamic Type: 39 хардкодов `.font(.system(size:))` | P1 | ✅ |
| [#23](https://github.com/AuthFailed/CheckNet/issues/23) | Единая обработка ошибок + «Повторить» | P1 | ✅ |
| [#24](https://github.com/AuthFailed/CheckNet/issues/24) | Idle-состояния на 12 экранах | P2 | ✅ |
| [#25](https://github.com/AuthFailed/CheckNet/issues/25) | Поиск: синонимы в каталоге, поиск в истории | P2 | ✅ |
| [#26](https://github.com/AuthFailed/CheckNet/issues/26) | Reduce motion и `numericText` | P2 | ✅ |
| [#27](https://github.com/AuthFailed/CheckNet/issues/27) | Pull-to-refresh на списках | P3 | ✅ |
| [#28](https://github.com/AuthFailed/CheckNet/issues/28) | Экраны без ⓘ и асимметрия в Блокировках | P2 | ✅ |
| [#29](https://github.com/AuthFailed/CheckNet/issues/29) | Заглушка не объясняет, почему инструмент недоступен | P2 | ✅ |
| [#30](https://github.com/AuthFailed/CheckNet/issues/30) | Онбординг и pre-permission для локальной сети | P2 | ✅ |
| [#31](https://github.com/AuthFailed/CheckNet/issues/31) | `onTapGesture` вместо `NavigationLink` | P2 | ✅ |

**Порядок:** #23 (единая фаза/ошибка) → #20 и #24 садятся на неё → #21/#22 → остальное.

---

## M4 · Архитектура и тесты ✅

Убирает дублирование и закрывает самый рискованный непокрытый код.

**Статус: завершена ✅** (6 из 7 закрыто; у #32 внедрён строительный блок, миграция — отдельным
шагом, см. ниже).

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#35](https://github.com/AuthFailed/CheckNet/issues/35) | Тесты на `X509Parser` (рукописный DER) | P1 | ✅ |
| [#36](https://github.com/AuthFailed/CheckNet/issues/36) | Тесты на `DNSMessage`, включая pointer loop | P1 | ✅ |
| [#37](https://github.com/AuthFailed/CheckNet/issues/37) | Таргет `CheckNetTests` для `App/` и `Shared/` | P1 | ✅ |
| [#33](https://github.com/AuthFailed/CheckNet/issues/33) | Вынести `BlockingCheck.run` в NetworkKit | P1 | ✅ |
| [#34](https://github.com/AuthFailed/CheckNet/issues/34) | Дублирование: `CheckRecord`, `PingConfig`, персистенс | P2 | ✅ |
| [#38](https://github.com/AuthFailed/CheckNet/issues/38) | Непокрытые движки NetworkKit | P2 | ✅ |
| [#32](https://github.com/AuthFailed/CheckNet/issues/32) | `ToolRunModel<T>` — схлопнуть ~15 моделей | P2 | 🔨 частично |

**Что сделано (в `main`):**
- #36 — `DNSMessage.readName` отклоняет указатели сжатия не «строго назад» (циклы/вперёд/на себя),
  ограничивает имя 255 байтами, запрещает зарезервированные длины меток; +15 тестов.
- #35 — разбор строк по тегу (BMPString/Teletex), UTCTime по правилу века RFC 5280, разбор SAN
  (показан на листовом сертификате); +17 тестов с реальными RSA/EC-фикстурами и фаззингом.
- #37 — чистая логика App вынесена в `Shared/` и покрыта таргетом `CheckNetTests` (51 тест);
  экранирование CSV теперь RFC 4180 по всем колонкам.
- #33 — диспетчеризация проверок в `CensorshipCheckKind` (NetworkKit); Intents/планировщик
  больше не зависят от UI.
- #34 — пресеты `PingConfig`, фабрики `CheckRecord`, `UserDefaults.json/setJSON`.
- #38 — контрольная сумма ICMP (вектор RFC 1071) и разбор пакетов; +19 тестов.
- #32 — **строительный блок** `RunPhase` + `ToolRunModel<Value>` в `Shared/` (с тестами).

**Осталось по #32:** миграция ~15 моделей на `ToolRunModel`. Задумывалась совместно с #15
(`ToolScaffold`), но #15 уже закрыта, поэтому это отдельный механический шаг: экраны уже используют
`ToolScaffold`, миграция сводится к замене внутренностей каждой модели. Модели неоднородны —
~8 одноразовых (`run() async throws`) и ~7 потоковых (`start()/stop()` с прогрессом).

**Порядок (как делалось):** #35/#36 (риск безопасности и зависаний) → #37 → #33 → #34 → #38 → #32.

---

## M5 · Платформенные интеграции — в работе

Здесь приложение перестаёт быть «утилитой, которую открывают руками».

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#39](https://github.com/AuthFailed/CheckNet/issues/39) | Фоновый мониторинг через `BGTask` | P1 | ✅ |
| [#40](https://github.com/AuthFailed/CheckNet/issues/40) | Уведомления: actions, time-sensitive, foreground | P2 | ✅ |
| [#41](https://github.com/AuthFailed/CheckNet/issues/41) | Control Center + Lock Screen виджеты | P2 | ✅ |
| [#42](https://github.com/AuthFailed/CheckNet/issues/42) | Siri: донат интентов, `AppEntity` хостов | P2 | ✅ |
| [#43](https://github.com/AuthFailed/CheckNet/issues/43) | iCloud-синхронизация, Handoff, Spotlight | P2 | ✅ |
| [#44](https://github.com/AuthFailed/CheckNet/issues/44) | Focus filters, интерактивная Live Activity | P3 | ✅ |
| [#45](https://github.com/AuthFailed/CheckNet/issues/45) | watchOS и visionOS — исследование | P3 | |

**Порядок:** #39 → #40 (уведомления осмысленны только при работающем фоне) → #41/#42 → #43 → #44/#45.
Порядок мягкий: #42 взят раньше фоновых задач как чисто кодовый и юнит-тестируемый — он
не требует on-device-проверки, в отличие от `BGTask`/уведомлений.

**#42 сделан:** сохранённые хосты стали `SavedHostEntity` (`EntityStringQuery`) — в Shortcuts и
Siri пользователь выбирает свои избранные по имени, а любой адрес можно ввести вручную;
ручной пинг донатит `PingHostIntent` в `IntentDonationManager`, чтобы система предлагала его на
локскрине и в Spotlight. Матчинг и codec вынесены в `Shared/SavedHostsPersistence.swift`
(единый ключ хранилища для стора и запроса) и покрыты юнит-тестами в `CheckNetTests`.

**#44 сделан:** **интерактивная Live Activity** — на пинг-активности (Lock Screen + развёрнутый
Dynamic Island) появилась кнопка «Стоп» (`StopPingLiveActivityIntent: LiveActivityIntent`,
`#if os(iOS)`), которая через shared-генерацию (`LiveActivitySignal`, app-group) сигналит циклу
пинга завершиться; baseline снимается на старте, поэтому старое нажатие не гасит новый прогон.
**Focus filter** — `MonitorFocusFilter: SetFocusFilterIntent` (кросс-платформенный) заглушает
оповещения мониторинга в выбранном фокусе, персистя выбор в `FocusMonitorState`, который читает
`HostNotifier.post` (и foreground, и фон). Оба флага чистые и покрыты тестами; реальное
переключение фокусов проверяется только на устройстве.

**Live Activity обобщена (сверх #44).** Была только пинг-активность; теперь один
`CheckActivityAttributes` (статус + заголовок + подпись + до трёх чипов, `kind` → иконка и
кнопка) обслуживает любую длящуюся проверку. Контроллер и виджет переименованы в
`CheckActivityController` / `CheckLiveActivityWidget`, форматирование вынесено в чистые
`PingActivityContent` / `MonitorActivityContent` (юнит-тесты). **Мониторинг** теперь показывает
живую активность (агрегат «N/M онлайн», худший статус — цвет, чипы Онлайн/Не отвечают/Хостов),
обновляется из foreground-цикла и из `BackgroundMonitor` (перечислением активностей). Заодно
`MonitoringManager` поднят на уровень приложения (`@Environment`) — раньше мониторинг умирал при
уходе с экрана; теперь идёт всю сессию, а осиротевшие активности гасятся на старте. Проверено на
симуляторе: активность появляется в Dynamic Island (компакт «0/1» + развёрнутый вид с чипами) и
исчезает по «Стоп».

**#39 + #40 сделаны:** **фон** — `BackgroundMonitor` (`BGAppRefreshTask`, id
`com.chrsnv.checknet.monitor.refresh` в `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes:
fetch`) переоткрывает те же проверки, что foreground-мониторинг, пока приложение выгружено;
регистрируется в `init`, планируется при уходе в background и при включении мониторинга. **Уведомления**
— `HostNotifier` даёт категорию `HOST_STATUS` с действиями «Открыть» / «Проверить снова»,
foreground-показ баннера (делегат) и time-sensitive-уровень для падений (мягко деградирует до
`.active` без платного entitlement). Решение «слать ли и что» вынесено в чистый
`Shared/MonitorNotification.swift` (матрица переходов: первый замер молчит, флаппинг ok↔degraded
молчит, алертят только down/recovery), записи хостов — в общий `Shared/MonitorStore.swift`; всё
покрыто юнит-тестами. iOS-only (`BGTaskScheduler` нет на macOS — там остаётся foreground-цикл).
Реальное пробуждение системой и доставка проверяются только на устройстве; здесь — сборка,
тесты логики и чистый старт с зарегистрированной задачей на симуляторе.

**#43 сделан:** **Handoff** — открытый инструмент рекламируется как `NSUserActivity`
(`com.chrsnv.checknet.tool`, `Shared/ToolActivity.swift`, объявлен в `NSUserActivityTypes`) с
хостом; приём резолвится в корневой сцене через тот же `navigator.open`, что Spotlight и контролы.
**iCloud-синхронизация хостов** написана (`App/Store/CloudHostSync.swift`, `NSUbiquitousKeyValueStore`
+ чистое слияние `SavedHostMerge.union`, покрытое тестами), но **дормантна**: `isAvailable = false`,
т.к. entitlement `ubiquity-kvstore-identifier` подписывает только платный аккаунт — тот же барьер,
что у Wi-Fi (`CurrentNetwork.isSSIDReadable`); в настройках честно показано «Недоступна» с
объяснением. Флаг и entitlement включаются одним коммитом. **Spotlight** был закрыт ранее
(`acc7a6f`). Кросс-девайс Handoff/iCloud проверяются только на паре устройств; здесь — сборка,
юнит-тесты codec/слияния и рендер настроек на симуляторе.

**#41 сделан:** два `ControlWidget` в расширении (`Widgets/CheckNetControls.swift`) — «Пинг
хоста» (показывает последний результат из app-group-снапшота и по тапу переоткрывает проверку) и
«Проверить блокировки» (открывает вкладку). Оба **только пользовательские** (Центр управления,
локскрин, кнопка «Действие») — в галерею домашнего экрана по-прежнему ничего не публикуется. Тап
шлёт deep-link `checknet://tool/<raw>?host=&run=1` / `checknet://tab/<name>`, который резолвит
`onOpenURL`; грамматика ссылок и формат значения контрола вынесены в `Shared/ControlSupport.swift`
и покрыты юнит-тестами. Маршрутизация проверена на симуляторе (Ping с автозапуском, вкладка
«Блокировки»).

> Виджеты в #41 — **только те, что пользователь добавляет сам** (Control Center, локскрин).
> Виджет главного экрана после установки не появляется и появляться не должен.

---

## M6 · Новые инструменты ✅

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#46](https://github.com/AuthFailed/CheckNet/issues/46) | Bufferbloat — задержка под нагрузкой | P1 | ✅ |
| [#47](https://github.com/AuthFailed/CheckNet/issues/47) | Геолокация IP и World Ping — выбрать источник | P2 | ✅ |
| [#48](https://github.com/AuthFailed/CheckNet/issues/48) | Wi-Fi-анализ на macOS через CoreWLAN | P2 | ✅ |
| [#49](https://github.com/AuthFailed/CheckNet/issues/49) | Пул идей для конкурентного отрыва | P3 | 📋 бэклог |

**#46 сделан первым** — движок нагрузки уже был (`IperfClient`, `CloudflareSpeedTest`), а сама
проверка востребована больше остальных: именно bufferbloat объясняет «интернет быстрый, но звонки
рвутся». `BufferbloatTest` (idle → down → up RTT, оценка A–F, ограничение фаз по времени) +
`BufferbloatView` (оценка, график задержки по фазам, три числа); проверено на реальной сети.

Из [#49](https://github.com/AuthFailed/CheckNet/issues/49) наиболее перспективны:
**IPv6-готовность**, **QUIC/HTTP-3 доступность**, **дневник качества сети** и
**автоотчёт для провайдера** — последнее потенциально killer-фича.

---

## Как тесты гоняются в CI

Большая часть из 96 тестов ходит к живым хостам — это осознанно: проверка считается рабочей
только после подтверждения на реальном хосте. Но раннер GitHub не является надёжной сетью:
ICMP там обычно фильтруется, DNS и TLS к сторонним хостам флейкуют. Гонять такое как блокирующий
гейт значит краснить каждый PR из-за чужого сбоя.

Принятое решение — разделить прогон на два:

- **`unit-tests` — блокирующий.** Запускается с `CHECKNET_SKIP_NETWORK_TESTS=1`; сетевые тесты
  помечены вызовом `try requiresInternet()` и пропускаются. Остаются детерминированные:
  парсеры, кодировщики, каталоги, доставка вебхука на локальный сервер. Этот job не имеет права
  флейкать — красный крест здесь всегда означает регрессию.
- **`network-tests` — информационный** (`continue-on-error: true`). Гоняет весь набор против
  реальных хостов. Падение — повод посмотреть, а не повод блокировать PR.

Локально переменная не выставлена, поэтому `swift test` по-прежнему гоняет всё. Настоящий гейт
для сетевых проверок — локальный прогон перед тем, как включать инструмент.

---

## Принципы, которые не пересматриваются

1. **Тест до экрана.** Движок в `NetworkKit` + тест против реального хоста → только потом UI и
   `Tool.isImplemented = true`. Полуработающих проверок в сборке не бывает.
2. **Только детект, не обход.** Блокировки диагностируются; SNI-фрагментация, поддельный ClientHello,
   record-splitting и прочий DPI-байпас в приложение не добавляются — это вне задач диагностики.
3. **Ничего не навязываем.** Никаких виджетов, разрешений и уведомлений «по умолчанию» —
   всё включает пользователь, и каждая проверка объясняет себя через ⓘ.
4. **Приватность.** Диагностика выполняется с устройства; наружу уходит только то, что пользователь
   сам запросил. Внешние API подключаются только с явным объяснением в ⓘ.
5. **HIG.** Системные компоненты вместо самописных, Dynamic Type и VoiceOver — не опция.
