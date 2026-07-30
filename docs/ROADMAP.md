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
- **App + Shared** — ~11 000 строк; появился таргет **`CheckNetTests` (119 тестов)** на логику
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
                               ├─→ M6 Новые инструменты
                               └─→ M7 Инструменты для VPN ──→ M8 Публикация в App Store
                                                                    ▲
   Качество релиза (сквозные, идут к M8):  M9 Дизайн-редизайн ······┤
                                           M10 Переводы и тон ·······┘

   После M8, форвардные:  M11 Конкурентный отрыв и дизайн-лидерство
```

**Статус вех:** M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 почти закрыта (#39–#44 ✅, остаётся P3 #45) · M6 ✅ (инструменты сделаны; #49 — живой бэклог идей) · **M7 🔨 в работе** (раздел для владельцев VPN: #70/#71/#72/#73/#75/#76/#77/#78/#79 ✅, остаётся #74) · **M8 📋 запланирована** (подготовка и публикация в App Store) · **M9 📋** (дизайн-редизайн: macOS + VPN + единый язык) · **M10 📋** (переводы и тон) · **M11 📋** (конкурентный отрыв и дизайн-лидерство).

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
уходе с экрана; теперь идёт всю сессию, а осиротевшие активности гасятся на старте.

**Live Activity доведена до всех запускаемых инструментов — 22 шт.**
- *Длящиеся* (живой Dynamic Island): пинг, мониторинг, тест скорости (Мбит/с + фаза),
  bufferbloat (фаза/RTT → оценка A–F с цветом), MTR (задержка цели/потери/раунд), трассировка,
  скан портов и IP (прогресс «X/Y» + найдено), World Ping и обзор сети (прогресс), Bonjour
  (счётчик сервисов), MTU (размер пробы → path MTU).
- *Одноразовые* (результат держится 90с на локскране): host→IP, обратный DNS, DNS lookup/compare/
  tamper, whois, TLS, чёрные списки, CGNAT, IP-геолокация.

Масштабируемость: активность подключена к самому `ToolRunModel` (seam для ~10 одноразовых
инструментов — задают короткий `ActivityDescriptor` + маппер фазы→вид; `LookupActivityContent`
рисует «выполняется / результат / ошибка», статус per-result красит истёкший серт / листинг /
подмену в красный). Прогресс-сканы делят `ScanActivityContent`. Контент вынесен в чистые билдеры
в `Shared/` и покрыт юнит-тестами; `kind` → иконка в виджете. Найден и починен race: `start()`
моделей первым делом зовёт `stop()`, а асинхронный конец из `stop()` гасил только что созданную
активность — перешли на **отдельный контроллер на прогон**. Осознанно без активности: Wake-on-LAN
(синхронная мгновенная отправка — нечего показывать), список интерфейсов и iOS-заглушки Wi-Fi.
Проверено на симуляторе: MTR-активность в Dynamic Island (компакт «30 хопов» + развёрнутый вид),
создание lookup-активности подтверждено логом.

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

## M7 · Инструменты для владельцев VPN — запланирована

Новый раздел не для конечного пользователя, а для **оператора VPN** (экосистема Xray / Reality /
mihomo / sing-box / Happ). Сейчас приложение смотрит на сеть глазами клиента; операторам нужен
другой набор — проверить домен под Reality, убедиться, что инбаунд жив, разобрать geosite/geoip и
правила роутинга, распарсить подписку. В App Store эта ниша почти пустует — потенциальный отрыв.

**Граница.** Раздел остаётся диагностикой и управлением конфигами: проверить, разобрать, показать,
собрать конфиг. Приложение **не выполняет DPI-обход** и не становится средством обхода — тот же
принцип, что во вкладке «Блокировки» (детект, не обход). Не встраиваем фрагментацию SNI, поддельный
ClientHello и подобное; помогаем оператору настроить и проверить **свой** сервер.

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#69](https://github.com/AuthFailed/CheckNet/issues/69) | Эпик: раздел «VPN» — зонтичная задача | P2 | 📋 |
| [#70](https://github.com/AuthFailed/CheckNet/issues/70) | Пригодность домена как SNI/dest для Reality | P2 | ✅ |
| [#71](https://github.com/AuthFailed/CheckNet/issues/71) | Доступность Xray-инбаунда (VLESS/Trojan) — реальный handshake | P2 | ✅ |
| [#72](https://github.com/AuthFailed/CheckNet/issues/72) | Парсинг подписки — хосты, роутинг, быстрые действия | P2 | ✅ |
| [#73](https://github.com/AuthFailed/CheckNet/issues/73) | Просмотр geosite/geoip — загрузка, разбор, поиск тегов, фильтры | P3 | ✅ |
| [#74](https://github.com/AuthFailed/CheckNet/issues/74) | Просмотр mihomo rule-set (`.mrs`) | P3 | 📋 |
| [#75](https://github.com/AuthFailed/CheckNet/issues/75) | Ответ сервера подписки на заголовки разных клиентов | P3 | ✅ |
| [#76](https://github.com/AuthFailed/CheckNet/issues/76) | Конфигуратор правил роутинга Happ + разбор | P3 | ✅ |
| [#77](https://github.com/AuthFailed/CheckNet/issues/77) | Happ Decrypt — расшифровка конфигов/подписок Happ | P3 | ✅ |
| [#78](https://github.com/AuthFailed/CheckNet/issues/78) | Incy deep-link — разбор и генерация `incy://crypt1` (+ QR) | P3 | ✅ |
| [#79](https://github.com/AuthFailed/CheckNet/issues/79) | Сканер доменов для Reality — обход IP/подсети в поиске TLS 1.3 dest | P2 | ✅ |

**Порядок:** сначала разборщики и клиенты в `NetworkKit` (движок → тест → экран), от которых
зависит остальное: парсинг подписки (#72) и клиент VLESS/Trojan (#71) — фундамент; SNI-проверка
(#70) переиспользует TLS inspector/`X509Parser`; просмотрщики (#73/#74) — независимы; конфигуратор
роутинга (#76) и Happ Decrypt (#77) ждут спецификаций форматов (см. открытые вопросы в issue).

**#70 сделан:** `RealitySNICheck` выносит вердикт о пригодности домена как `dest`/SNI по тем же
критериям, на которых стоит эталонный `XTLS/RealiTLScanner` и README REALITY. Обязательные (провал
роняет вердикт): **TLS 1.3**, **ALPN `h2`**, реальный листовой сертификат с субъектом и издателем —
это правило приёма RealiTLScanner. Мягкие (только замечание): **поддержка X25519**, отсутствие
внешнего редиректа с главной (`example.com` → `www` допустим), доверенный неистёкший сертификат,
покрытие домена SAN. Факты TLS берутся из существующего `TLSInspector`/`X509Parser`; редирект — из
живого `GET /` поверх `TLSStream`. X25519 нельзя ограничить через Network.framework (нет API для
key-exchange-групп), поэтому `TLS13GroupProbe` вручную шлёт минимальный TLS 1.3 ClientHello с
единственной группой X25519 и читает ServerHello — так же, как RealiTLScanner фиксирует
`CurvePreferences`. Всё поверх `NWConnection` (сырые BSD-сокеты в песочнице заблокированы, поэтому
`TLSInspector` и раньше жил на Network.framework). Движок покрыт юнит-тестами (детерминированная
логика вердикта/матчинга сертификата/редиректа) и проверен на живых доменах: microsoft/google/
apple/cloudflare/github → «подходит», `dl.google.com` → «с замечанием» (кросс-субдоменный редирект
на `www.google.com`). На устройстве подтверждён вердикт по www.microsoft.com. Экран
`RealitySNIView` — вводим домен, `ToolRunModel<RealitySNIReport>`, карточка вердикта + список
критериев со статусом формой и словом + карточка деталей. Граница соблюдена: только диагностика,
никакого обхода. **Готово в M7:** #70, #72, #76, #77, #78; **осталось:** #71 (Xray-инбаунд),
#73/#74 (просмотрщики geosite/`.mrs`), #75 (заголовки клиентов), #79 (сканер, в работе).

**#79 — сканер доменов для Reality (сделан).** #70 проверяет один домен; сканер решает обратную
задачу — «дай IP/подсеть рядом с моим сервером, найди в ней хосты, годные под `dest`». Обходит
диапазон IPv4 (CIDR / `a.b.c.d-e` / `a.b.c` / одиночный IP; домен резолвится в IP, опц. соседний
/24), к каждому IP делает TLS 1.3-хендшейк **без SNI** и собирает попадания: TLS 1.3 + сертификат,
из листа берётся домен (CN/SAN) и издатель, помечается поддержка h2. Стриминговый результат
(прогресс + список находок IP → домен → издатель), как в скане портов/IP. Переиспользует
`IPv4Range.hosts` (разбор диапазона) и потоковый `withTaskGroup` из `IPRangeScanner`, TLS-факты — по
образцу `TLSInspector`. Скан диапазона сетевой-интрузивный → гейт согласия (`.confirmationDialog`,
как у скана портов/IP). Граница M7 соблюдена: находим камуфляжные домены, а не обходим DPI.

**#75 — ответ сервера по клиентам (сделан).** `ClientHeaderProbe` (NetworkKit/VPN) запрашивает URL
подписки от лица каждого клиента (`SubscriptionUserAgents`: v2rayNG, Happ, Clash Meta, sing-box,
Hiddify, Streisand, Shadowrocket, NekoBox, V2Box, Karing) и стримит per-client результат: статус,
число узлов, формат (через `SubscriptionParser`) и заголовки панели — `subscription-userinfo`
(upload/download/total/expire; `expire=0` = без срока, не 1970), `content-disposition` (filename,
в т.ч. RFC 5987), `profile-title` (plain/`base64:`), `profile-update-interval`, support-url. Экран
`ClientHeadersView` — стриминговый список с цветным статусом (обслужен/без узлов/отказ) и раскрытыми
деталями; поле URL подключено к общему `SavedSubscriptionsStore` (тот же список подписок, что в
«Парсинг подписки», #72) — можно подставить сохранённую или закладкой сохранить текущую. **Редактор
клиентов** (`ClientEditorView` + `EditableClient`): пользователь сам правит приложение и версию
(собирается UA «Приложение/Версия»), включает/выключает и добавляет свои; для open-source клиентов
`ClientReleaseIndex` подтягивает реальные версии с GitHub Releases (карта клиент→репозиторий:
2dust/v2rayNG, SagerNet/sing-box, clash-verge-rev, hiddify-app, NekoBox, Karing, mihomo, FlClash) —
кнопка «подтянуть последние» + per-row меню выбора версии; closed-source (Happ, Streisand,
Shadowrocket, V2Box) остаются ручными. **HWID:** тумблер «передавать HWID» + своё значение (или
генерация) — уходит заголовком `X-HWID` для панелей с привязкой к устройству; можно выключить
передачу целиком. **Сырые заголовки ответа** сохраняются и показываются per-client (раскрывающийся
список «Заголовки ответа (N)»). Набор клиентов/HWID персистится в UserDefaults. 11 + 6 юнит-тестов (разбор
заголовков и релизов GitHub) + живые смоуки против cloudflare-trace и GitHub API; проверено на реальной
подписке (Happ → 200/20 узлов, трафик/название/поддержка распарсились) и на устройстве (подтяжка
версий: v2rayNG 1.9.5→2.2.6, clash-verge→2.5.2, sing-box→1.14.0-beta.2). **Осталось в M7:** #71
(Xray-инбаунд, через-прокси только на macOS), #73/#74 (просмотрщики geosite/`.mrs`).

**#73 — просмотрщик geosite/geoip (сделан).** `GeoData` (NetworkKit/VPN) — ручной разбор
wire-format protobuf v2fly (свой `ProtoReader`: varint/length-delimited/skip, как рукописные
DER/MMDB-парсеры). `GeoDataDocument.load` авто-определяет geosite vs geoip (по типу первого поля
внутреннего сообщения: varint=домен → geosite, bytes=IP → geoip), строит индекс категорий
(`country_code` + счётчик, диапазон байт), а правила декодирует по требованию — файл на ~0.5 млн
правил не материализуется в объекты целиком. geosite: тип домена (full/domain/keyword/regexp) +
значение + атрибуты `@ads`; geoip: CIDR (v4 и v6). Поиск: `categoriesContaining(domain:)` (точное/
поддомен/keyword/regex) и `categoriesContaining(ip:)` (IPv4-принадлежность по маске). Экран
`GeoDataView` — открыть свой `.dat` (`fileImporter`) или загрузить сборку Loyalsoldier, шапка
(тип/категории/правила), поиск домена/IP по категориям, `.searchable` список категорий → детальный
экран правил с бейджами типа. 10 юнит-тестов на самодельных protobuf-фикстурах + живой разбор
реальных geosite.dat/geoip.dat (GOOGLE/NETFLIX/CN, CN >1000 доменов, IP 1.2.4.8→CN). Проверено на
устройстве: geosite.dat = 1527 категорий / 498 682 правил; geoip рендерит CIDR.

**#71 — доступность Xray-инбаунда (сделан).** Проверяет, что VLESS/Trojan-инбаунд оператора
действительно принимает соединения: поднимает **ядро Xray прямо в процессе приложения** (а не
скачанным бинарём — на iOS его нельзя ни скачать, ни запустить) и делает через него пробный запрос.
Ядро — вендоренный `LibXray.xcframework` (XTLS/libXray, статический Go-core `libXray.a`; тянется
`Scripts/fetch-libxray.sh`, в git не коммитится — линкуется, не эмбедится; Go резолвит DNS через
`libresolv`). Мост `XrayCore` (App/VPN) обёртывает единственную C-точку `CGoInvoke(json)->json`
(версия ядра, `runXrayFromJson`, `stopXray`). `XrayProxyRunner.startInProcess` собирает конфиг из
узла (`XrayTestConfig`: один локальный SOCKS-инбаунд + реальный outbound узла — при Xray-JSON берётся
verbatim, иначе восстанавливается из полей ссылки), поднимает ядро и отдаёт живой SOCKS-порт.

**Выходной IP через прокси.** Вместо одного «работает/нет» инструмент опрашивает через прокси
~19 независимых ресурсов и показывает, **какой выходной IP видит каждый** — так оператор
подтверждает адрес выхода, ловит сплит-роутинг (разные ресурсы видят разные IP) и читает гео/ASN,
которые сервер предъявляет наружу. Движок `EgressIPProbe` (NetworkKit/VPN) пинит весь `URLSession`
к SOCKS-прокси через `ProxyConfiguration(socksv5Proxy:)` (Network, iOS 17+) — TLS, редиректы и JSON
целиком идут по туннелю, поэтому в набор входит и HTTPS-взгляд самого Cloudflare. Каталог диверсифицирован
(`EgressResource.catalog`): IP-эхо (ipify, ifconfig.me, icanhazip, Amazon AWS, ident.me, ip.sb, SeeIP,
myexternalip, WTFIsMyIP), Cloudflare `/cdn-cgi/trace` (IP + страна + colo) и гео/ASN
(ip-api, ipinfo, ipwho.is, ipapi.co, ip.sb geoip, GeoJS, myip.com, FreeIPAPI). Результаты стримятся
(`AsyncStream`, конкурентно), экран `XrayCheckView` даёт вердикт («инбаунд работает / N из M ответили»),
крупный выходной IP с флагом страны и предупреждение при расхождении IP, ниже — список по группам
(ресурс → IP → флаг/страна/ASN/провайдер/colo, задержка, красная причина при отказе). Разбор ответов
(plain/trace/JSON, вложенные ключи, `AS`-префикс для числовых ASN) покрыт юнит-тестами.

`XrayTestConfig`/`SubscriptionParser`/`EgressIPProbe` покрыты юнит-тестами (сборка конфига из
reality-ссылки и из полного Xray-JSON, разбор всех форматов эхо — детерминированно). **Проверено
живьём** на iPhone 17 Pro (симулятор) против реального VLESS+Vision-сервера (Франция): ядро
поднялось, подключилось, 17 из 19 ресурсов вернули один и тот же выходной IP `50.7.33.242`,
Cloudflare — 🇫🇷 FR/colo VIE, ip-api — FDCservers.net; два ресурса отвалились по таймауту и честно
показаны красным. Так подтверждён и позитивный end-to-end-хендшейк, который раньше требовал живого
сервера. Граница M7 соблюдена: диагностируем свой инбаунд и его выход, а не обходим DPI. **Осталось
в M7:** #74 (`.mrs`, нужен zstd).

Источники идеи (референсы поведения сканера, не зависимость):
- `XTLS/RealiTLScanner` — https://github.com/XTLS/RealiTLScanner (эталон: `-addr <IP/CIDR/домен>`,
  правило приёма `version==TLS1.3 && alpn=="h2" && есть CN && есть issuer`, вывод `IP  домен  издатель`,
  флаги `-port/-thread/-timeout/-showFail`).
- Веб-реализация: https://ru.inettools.net/tools/reality-tls-scanner
- Гайд по настройке Xray+Reality (выбор `dest`, применение сканера):
  https://pikabu.ru/story/nastraivaem_server_i_klient_xray_s_xtlsreality_12073187

**Форматы разобраны (спеки в issue):** Happ crypt/crypt5 (RSA PKCS#1 + ChaCha20-Poly1305,
публичный материал ключей) — #77; Happ-роутинг (`happ://routing/add/<base64 JSON>`, точные поля) —
#76; mihomo `.mrs` (zstd + magic `MRS\x01`, LOUDS domain-set / ipcidr) — #74; geosite/geoip `.dat`
(protobuf v2fly, ручной wire-format) — #73. Из зависимостей: `.mrs` требует zstd на iOS/macOS
(Apple `Compression` его не даёт).

**Версии клиентов — автоматически.** Заголовки для #75 подставляют актуальную версию, подтягивая её
с GitHub Releases по карте `клиент → репозиторий` (Happ, Incy, mihomo, sing-box, v2rayNG, Clash Verge
Rev, Hiddify, Karing, FlClash), с кэшем и бандл-фоллбэком; фактические UA — из наблюдаемого трафика
подписок. Точные форматы Incy/koala-clash/v2raytun/Happ подтверждены.

**Официальные референсы форматов подключены:** `Happ-proxy/routing_generator` (генератор роутинга,
источник правды для #76) и `INCY-DEV/incy-link-encoder` (формат `incy://crypt1`, AES-256-GCM — для
#78 и #72).

**Дополнительные идеи (кандидаты в issue, из эпика #69):** валидатор/генератор ссылок
`vless://`/`trojan://`/`ss://` с QR; проверка целостности Reality-конфига (SNI/dest, pbk/sid, flow,
ALPN); «палевность» конфига (uTLS-fingerprint/ALPN vs браузер, steal-oneself); внешний
аптайм/латентность инбаундов; проверка IP сервера по чёрным спискам/ASN (переиспользовать DNSBL).

---

## M8 · Подготовка и публикация в App Store — запланирована

До сих пор «релиз» в плане был только про технику (M1: privacy-манифест, CI, гонки данных).
M8 — это **фактический выход в App Store**: аккаунт и юридический слой, экспортный контроль
шифрования, прохождение App Review, метаданные и витрина, бета через TestFlight и автоматизация
выката. Веха последняя не потому, что простая, а потому, что бессмысленно подавать движущуюся
цель: набор инструментов должен быть заморожен.

Приложение **нетипичное для стора** и это главный риск: сетевые сканеры (порты, IP-диапазон,
Reality-сканер доменов), целый раздел **для VPN-операторов** и криптоинструменты (Happ Decrypt,
Incy `crypt1`). Поэтому здесь много не про «залить бинарь», а про то, **как объяснить Apple, что
это диагностика и управление своим сервером, а не средство обхода/взлома** — тот же принцип
границы, что во вкладке «Блокировки».

> **Два самых больших ревью-риска — закладываем время на них заранее.**
> 1. **Guideline 5.4 (VPN).** У приложения есть раздел «VPN», но оно **не является** VPN-провайдером
>    и не маршрутизирует трафик — это инструменты диагностики и подготовки конфигов. Ревьюер может
>    решить иначе по одному слову «VPN». Митигируем формулировками в описании и UI (при риске —
>    переименовать раздел в «Инструменты оператора»), подробными заметками ревьюеру и демо-данными.
> 2. **Сетевые сканеры и крипта.** Сканеры на Apple допустимы (пример — Fing), но только с явным
>    согласием и понятной целью — согласие у нас уже гейтом (`SensitiveConsentModifier`). Happ/Incy
>    расшифровывают **собственные** конфиги оператора по опубликованным алгоритмам — это надо явно
>    проговорить в заметках, иначе выглядит подозрительно.

**Экспортный контроль (не пропустить — это блокер подачи).** Кроме стандартного TLS приложение
использует собственную крипту для интероперабельности: ChaCha20-Poly1305, AES-256-GCM, RSA (Happ,
Incy). Это, скорее всего, попадает под mass-market exemption 740.17(b) (стандартные опубликованные
алгоритмы), но требует правильной обработки `ITSAppUsesNonExemptEncryption`, **годового
self-classification report** в BIS/ENC и, при распространении во Франции, декларации ANSSI. Нужна
явная задача с итоговым определением, а не «поставили false и забыли».

### A. Аккаунт, юридический слой, экспортный контроль

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#80](https://github.com/AuthFailed/CheckNet/issues/80) | Enrollment в Apple Developer Program (индивид/организация; для организации — D-U-N-S) | P0 | ⬜ |
| [#81](https://github.com/AuthFailed/CheckNet/issues/81) | Соглашения в App Store Connect (Free Apps Agreement), заполнить Tax & Banking | P0 | ⬜ |
| [#82](https://github.com/AuthFailed/CheckNet/issues/82) | Политика конфиденциальности + Support URL — сверстать и захостить (кандидат: GitHub Pages) | P0 | ⬜ |
| [#83](https://github.com/AuthFailed/CheckNet/issues/83) | Экспортный контроль: определить статус, `ITSAppUsesNonExemptEncryption`, годовой self-classification в BIS/ENC, декларация ANSSI | P0 | ⬜ |
| [#84](https://github.com/AuthFailed/CheckNet/issues/84) | Проверка имени «CheckNet» (товарный знак/коллизии в сторе), резерв bundle ID и App ID с нужными capabilities | P0 | ⬜ |

### B. Соответствие App Review Guidelines

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#85](https://github.com/AuthFailed/CheckNet/issues/85) | Ревью-аудит чувствительных инструментов: сканеры, VPN-раздел, крипта Happ/Incy — легитимная формулировка назначения | P0 | ⬜ |
| [#86](https://github.com/AuthFailed/CheckNet/issues/86) | Заметки ревьюеру (App Review Information): что делает каждый чувствительный инструмент + демо-данные (тестовая подписка, тест-хосты), чтобы ревьюер прогнал VPN-раздел | P0 | ⬜ |
| [#87](https://github.com/AuthFailed/CheckNet/issues/87) | Границы 5.4 VPN: явно показать, что приложение НЕ маршрутизирует трафик (формулировки в описании/UI, при риске — переименовать раздел) | P1 | ⬜ |
| [#88](https://github.com/AuthFailed/CheckNet/issues/88) | 2.5.1 приватные API: аудит на отсутствие непубличных фреймворков/символов (raw sockets, `rt_msghdr2`, CoreWLAN) в iOS-сборке | P1 | ⬜ |
| [#89](https://github.com/AuthFailed/CheckNet/issues/89) | App Privacy («nutrition labels») в ASC: честно задекларировать «Data Not Collected», отсутствие трекинга | P0 | ⬜ |
| [#90](https://github.com/AuthFailed/CheckNet/issues/90) | Возрастной рейтинг (age rating questionnaire) | P1 | ⬜ |
| [#91](https://github.com/AuthFailed/CheckNet/issues/91) | Правовая чистота данных: атрибуции сторонних источников (v2fly geosite/geoip, iperf server list, GitHub Releases), проверка их условий на встраивание | P2 | ⬜ |

### C. Технический релиз-билд

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#92](https://github.com/AuthFailed/CheckNet/issues/92) | Дистрибуционный сертификат + App Store provisioning profile; архив Release реально собирается (`xcodebuild archive`) | P0 | ⬜ |
| [#93](https://github.com/AuthFailed/CheckNet/issues/93) | Аудит entitlements: выключить неполученные (iCloud KV — дормантна, Wi-Fi) так, чтобы подпись прошла; сверить capabilities App ID | P0 | ⬜ |
| [#94](https://github.com/AuthFailed/CheckNet/issues/94) | `PrivacyInfo.xcprivacy`: задекларировать required-reason API (UserDefaults, file timestamp, boot time, disk space) — обязательное требование Apple | P0 | ⬜ |
| [#95](https://github.com/AuthFailed/CheckNet/issues/95) | Бамп версии/билда, выключить debug-логи и тестовые хосты, выгрузка dSYM для символикации | P1 | ⬜ |
| [#96](https://github.com/AuthFailed/CheckNet/issues/96) | Решение по macOS: отдельная подача в Mac App Store (свой профиль/скриншоты) или пока только iOS; notarization если вне стора | P1 | ⬜ |
| [#97](https://github.com/AuthFailed/CheckNet/issues/97) | Санити `Info.plist`: usage-строки (Local Network и др.), ориентации, обоснование background modes, launch screen, min deployment target | P1 | ⬜ |

### D. Метаданные и витрина

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#98](https://github.com/AuthFailed/CheckNet/issues/98) | Тексты стора: имя, подзаголовок, описание, keywords, промо-текст, категория (Утилиты / Разработка), What's New | P1 | ⬜ |
| [#99](https://github.com/AuthFailed/CheckNet/issues/99) | Скриншоты под все обязательные размеры (iPhone 6.9″/6.5″, iPad 13″, + Mac при подаче) + опц. app preview | P1 | ⬜ |
| [#100](https://github.com/AuthFailed/CheckNet/issues/100) | Иконка 1024 без альфы/скруглений; проверка иконок всех размеров в asset catalog | P1 | ⬜ |
| [#101](https://github.com/AuthFailed/CheckNet/issues/101) | Локализация метаданных: минимум основной язык полностью; топ-языки стора по мере сил (13 языков уже в приложении) | P2 | ⬜ |

### E. QA на реальных устройствах

Почти все «device-only» фичи из `CLAUDE.md` (Local Network Privacy, `BGTask`, уведомления, Handoff,
Live Activity) до этого проверялись только на симуляторе или в тестах логики — здесь их наконец
гоняют на живых устройствах.

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#102](https://github.com/AuthFailed/CheckNet/issues/102) | Прогон на реальных iPhone/iPad: Local Network Privacy, `BGTask`-пробуждение, доставка уведомлений, Handoff, Live Activity/Dynamic Island, контролы | P0 | ⬜ |
| [#103](https://github.com/AuthFailed/CheckNet/issues/103) | Стабильность: нет крашей на холодном старте и всех экранах, нет утечек памяти, корректная работа без сети | P0 | ⬜ |
| [#104](https://github.com/AuthFailed/CheckNet/issues/104) | Доступность: VoiceOver-проход по ключевым экранам, Dynamic Type до accessibility-размеров, тап-таргеты ≥44 pt | P1 | ⬜ |
| [#105](https://github.com/AuthFailed/CheckNet/issues/105) | Проверка на «чистом» устройстве без платных entitlement: дормантные фичи (iCloud/Wi-Fi) честно показывают «недоступно», не крашат | P1 | ⬜ |

### F. TestFlight и бета

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#106](https://github.com/AuthFailed/CheckNet/issues/106) | Внутреннее тестирование TestFlight (свои устройства) | P1 | ⬜ |
| [#107](https://github.com/AuthFailed/CheckNet/issues/107) | Внешняя бета (Beta App Review) + сбор фидбэка перед релизом | P2 | ⬜ |

### G. Автоматизация выката

«Возможно автоматизировать какие-то процессы» — да, и это окупается со второй подачи. Ручной путь
для первого релиза допустим, но всё ниже стоит поставить, чтобы обновления не были ручным ритуалом.

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#108](https://github.com/AuthFailed/CheckNet/issues/108) | App Store Connect API key + fastlane (`gym` — архив, `deliver` — метаданные/скриншоты/бинарь, `match` — подпись) | P2 | ⬜ |
| [#109](https://github.com/AuthFailed/CheckNet/issues/109) | Автогенерация скриншотов (fastlane `snapshot` / UI-тест) под все размеры и языки | P2 | ⬜ |
| [#110](https://github.com/AuthFailed/CheckNet/issues/110) | CI: по git-тегу собирать архив и заливать в TestFlight (расширение существующего GitHub Actions) | P3 | ⬜ |
| [#111](https://github.com/AuthFailed/CheckNet/issues/111) | Автопубликация Privacy Policy/Support как статических страниц (GitHub Pages) из репозитория | P3 | ⬜ |

**Порядок.** Сначала блокеры подачи — вся группа A плюс M8.13–M8.15 и M8.10: без аккаунта,
экспортного статуса, дистрибуционной подписи, privacy-манифеста и App-Privacy-меток бинарь просто
не примут. Параллельно с этим готовится юридический слой (политика, support). Затем B (ревью-риски
и заметки ревьюеру) — то, из-за чего именно наше приложение могут развернуть. Дальше D (витрина) и
E (QA на устройстве) идут вместе. F (бета) — репетиция перед релизом. G (автоматизация) — P2/P3, по
мере надобности.

**Зависимость от M7.** Подача осмысленна, когда набор инструментов заморожен — иначе каждый новый
экран тянет новые скриншоты, строки и заметки ревьюеру. M8 стартует, когда M7 закрыта (или её
чувствительные инструменты сознательно спрятаны из релизной сборки). Локальная гигиена из
`CLAUDE.md` (нулевые следы тулчейна в репозитории, коммитах, метаданных стора) действует и здесь.

Задачи заведены как GitHub Issues [#80–#111](https://github.com/AuthFailed/CheckNet/milestone/8) и
подвешены к вехе M8, как остальные.

---

## M9 · Дизайн-редизайн — macOS, VPN-раздел, единый визуальный язык — запланирована

M2 сделал раскладку **адаптивной** (не ломается), но не **красивой**. На macOS это особенно видно:
контент отображается криво, тянется не так, поля и выравнивание съезжают, а раздел «VPN» из M7 на
Mac вовсе отсутствует. M9 — это переход от «работает на широком экране» к «выглядит как родное
Mac-приложение», с единым визуальным языком для каталога, экрана инструмента и карточки результата.

**Дизайн отдаётся Claude Design, не рисуется ad-hoc в SwiftUI** — это правило проекта (иначе снова
получаем 22 почти одинаковых экрана). Поэтому в вехе есть явный шаг «бриф → спека → реализация», а
не «поправить отступы на глаз».

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#113](https://github.com/AuthFailed/CheckNet/issues/113) | Аудит дефектов раскладки на macOS: скриншоты всех экранов в окне разных размеров, каталог проблем | P1 | ⬜ |
| [#114](https://github.com/AuthFailed/CheckNet/issues/114) | Вернуть/адаптировать раздел «VPN» на macOS (условная компиляция/скрытый таб) | P1 | ⬜ |
| [#115](https://github.com/AuthFailed/CheckNet/issues/115) | Ширина и поведение окна на Mac: ограничение ширины, поля, ресайз, минимальный размер | P1 | ⬜ |
| [#116](https://github.com/AuthFailed/CheckNet/issues/116) | Дизайн-бриф для Claude Design: единый язык каталог/инструмент/результат под macOS 26 + ревизия iOS | P1 | ⬜ |
| [#117](https://github.com/AuthFailed/CheckNet/issues/117) | Реализация редизайна по спеке | P1 | ⬜ |
| [#118](https://github.com/AuthFailed/CheckNet/issues/118) | Нативные тулбары, меню, горячие клавиши и поведение окон на Mac | P2 | ⬜ |
| [#119](https://github.com/AuthFailed/CheckNet/issues/119) | Ревизия пустых состояний и карточек результата под новый язык | P2 | ⬜ |
| [#120](https://github.com/AuthFailed/CheckNet/issues/120) | Приёмка редизайна на матрице: iPhone/iPad/Mac, светлая/тёмная, Dynamic Type, RTL | P2 | ⬜ |

**Порядок:** #113 (собрать дефекты) + #114/#115 (починить самое грубое на Mac) → #116 (бриф) →
#117 (реализация по спеке) → #118/#119 → #120 (приёмка). Приёмку удобно гонять инструментом
дизайн-QA из M11 (#132/#133).

---

## M10 · Локализация и тон — полный перевод, деловой голос, релиз-гейт — запланирована

Два разных долга под одной крышей: **полнота** перевода и **качество** текста. Сейчас каталог
покрывает 13 языков, но часть строк движков в чужой локали остаётся русской (категория из закрытого
#60, которую факт-состояние всё ещё числит открытой), а тон местами машинный. M10 доводит перевод
до 100% по всем языкам, приводит все тексты к **живой деловой официальной речи на «вы»** и ставит
**автоматический гейт**, который перед каждым релизом проверяет, что переводы на месте и корректны.

Тон закрепляется «в гайдлайнах»: гайд голоса + глоссарий в `docs/STYLE.md` и новый принцип №6 в
конце этого файла.

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#121](https://github.com/AuthFailed/CheckNet/issues/121) | Гайд тона голоса (деловая официальная речь на «вы») + единый глоссарий → `docs/STYLE.md` | P1 | ⬜ |
| [#122](https://github.com/AuthFailed/CheckNet/issues/122) | Аудит русских исходных строк на тон: убрать канцелярит/машинность, унифицировать термины | P1 | ⬜ |
| [#123](https://github.com/AuthFailed/CheckNet/issues/123) | Verbatim-строки движков (`LocalizedStringKey(переменная)`, `Text(model.string)`, `%lld`) — продолжить #60 | P1 | ⬜ |
| [#124](https://github.com/AuthFailed/CheckNet/issues/124) | Инвентаризация полноты перевода: отчёт покрытия по каждому из 13 языков | P1 | ⬜ |
| [#125](https://github.com/AuthFailed/CheckNet/issues/125) | Довести перевод до 100% по всем языкам + вычитка по глоссарию | P1 | ⬜ |
| [#126](https://github.com/AuthFailed/CheckNet/issues/126) | Релиз-гейт локализации: перед деплоем падать, если есть непереведённые/пустые/verbatim строки | P1 | ⬜ |
| [#127](https://github.com/AuthFailed/CheckNet/issues/127) | Длинные переводы и RTL: вёрстка не клипается, зеркалится корректно | P2 | ⬜ |
| [#128](https://github.com/AuthFailed/CheckNet/issues/128) | Вычитка ключевых языков носителями/качественным источником | P2 | ⬜ |

**Порядок:** #121 (задаёт тон и термины) → #122/#123 (правим исходник и verbatim) →
#124 (инвентаризация) → #125 (доперевод) → #126 (гейт, чтобы не деградировало) → #127/#128.
Релиз-гейт #126 встраивается в пре-релизный прогон рядом с автоматизацией выката M8.

---

## M11 · Конкурентный отрыв и дизайн-лидерство — запланирована

Форвардная веха: не «довести до релиза», а «оставаться лучше конкурентов после релиза». Три нити.

- **Продукт.** Найти и перенять то, чего нам не хватает у конкурентов (Speedtest, Network Analyzer,
  iNetTools, Fing, He.net) — не копировать всё подряд, а брать осмысленное для нашей ниши.
- **Дизайн.** Использовать «последнее слово» Apple-дизайна (новые API, паттерны, Liquid Glass) —
  чтобы приложение всегда выглядело нативно-современным, а не отставшим на версию ОС.
- **Автоматический дизайн-QA.** Инструмент, который **сам находит недостатки вёрстки**: прогоняет
  каждый экран на матрице устройств/тем/размеров шрифта и репортит дефекты. Кандидат на
  агента/воркфлоу — прогон по экранам параллелится.

| # | Задача | Приоритет | Статус |
|---|---|---|---|
| [#129](https://github.com/AuthFailed/CheckNet/issues/129) | Конкурентный аудит: матрица «есть у них — нет у нас» (Speedtest, Network Analyzer, iNetTools, Fing, He.net) | P2 | ⬜ |
| [#130](https://github.com/AuthFailed/CheckNet/issues/130) | Завести issue на выбранные новые инструменты (пополнить бэклог #49) | P2 | ⬜ |
| [#131](https://github.com/AuthFailed/CheckNet/issues/131) | Внедрение последнего слова Apple-дизайна: отслеживать новые API/паттерны, план внедрения | P3 | ⬜ |
| [#132](https://github.com/AuthFailed/CheckNet/issues/132) | Скриншот-харнесс: по deep-link снимать каждый инструмент на матрице (iPhone/iPad/Mac, светлая/тёмная, Dynamic Type) | P2 | ⬜ |
| [#133](https://github.com/AuthFailed/CheckNet/issues/133) | Дизайн-ревью-агент/воркфлоу: искать в скриншотах клиппинг, overflow, контраст, съехавшее выравнивание | P2 | ⬜ |
| [#134](https://github.com/AuthFailed/CheckNet/issues/134) | Снапшот-регресс вёрстки: эталоны + падение при непреднамеренных визуальных изменениях | P3 | ⬜ |
| [#135](https://github.com/AuthFailed/CheckNet/issues/135) | Дизайн-QA в пре-релизном пайплайне: отчёт с дефектами перед деплоем | P3 | ⬜ |
| [#136](https://github.com/AuthFailed/CheckNet/issues/136) | Killer-фичи из #49: выбрать 1–2 (IPv6-готовность, QUIC/HTTP-3, дневник качества, автоотчёт провайдеру) | P3 | ⬜ |

**Порядок:** #129 → #130 (продукт: аудит → задачи) идут независимо от дизайн-нити. В дизайн-нити
#132 (харнесс) — фундамент: на нём стоят #133 (агент), #134 (регресс) и #135 (интеграция в
пайплайн). #131 (слежение за Apple) и #136 (killer-фича) — фоновые, тянутся постоянно.
Дизайн-QA (#132/#133) переиспользуется для приёмки редизайна в M9 (#120).

**Почему форвардная, а не блокер релиза.** Первый релиз (M8) обходится без этого — набор
инструментов уже конкурентоспособен. Но чтобы «быть на коне» дальше, нужен постоянный приток фич и
автоматический глаз на вёрстку, иначе дизайн-долг снова накопится, как это было с 22 почти
одинаковыми экранами.

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
6. **Единый голос и полная локализация.** Тексты — живая деловая официальная речь на «вы», без
   канцелярита и штампов, с единым глоссарием терминов (`docs/STYLE.md`). Приложение переведено на
   все заявленные языки на 100%; перед каждым релизом полнота и корректность переводов проверяются
   автоматическим гейтом — строк на исходном языке в чужой локали быть не должно.
