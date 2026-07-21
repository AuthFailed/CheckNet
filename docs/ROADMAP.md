# CheckNet — план развития

Цель: **лучшее приложение для диагностики сети на Apple-платформах** — нативное на iPhone, iPad и Mac,
честное в объяснениях, с проверками, которых нет у конкурентов (Speedtest, Network Analyzer, iNetTools).

Задачи живут в [Issues](https://github.com/AuthFailed/CheckNet/issues) и сгруппированы по вехам.
Этот файл — про **порядок и зависимости**: почему M2 идёт раньше M3, а M4 — раньше M6.

---

## Где мы сейчас

- **22 инструмента** реализованы (движок протестирован + экран), **5 — заглушки «скоро»**
  (`App/Catalog/Tool.swift`): геолокация IP, bufferbloat, Wi-Fi-анализ, сигнал Wi-Fi, World Ping.
  Секция «Wi-Fi» в каталоге пуста целиком.
- **Ядро** `Packages/NetworkKit` — 6 453 строки, 96 XCTest-тестов против реальных хостов.
  Гоняются в CI: детерминированные — блокирующим гейтом, сетевые — информационно
  (см. «Как тесты гоняются в CI»).
- **App-слой** — 8 519 строк, **0 тестов**.
- **Локализация** — 565 ключей × 13 языков, покрытие ≈88,8 %; последние фичи только по-русски.
- **iPad/macOS** — адаптивной раскладки нет: 0 совпадений по `NavigationSplitView`, `horizontalSizeClass`,
  `ViewThatFits`. macOS-таргет собирается и запускается, но приложение открывается на Mac
  вертикальной полоской 488×900 — раскладка остаётся задачей M2.
- **Haptics** — 0 вызовов. **Accessibility** — 13 лейблов на 131 файл.
- Виджет главного экрана **удалён сознательно**: расширение существует только ради Live Activity,
  после установки приложение ничего не навязывает.

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

- **M1 первым** — там блокеры релиза (privacy manifest), потеря данных (гонка в истории) и
  неработающий CI. Строить новое на нестабильном фундаменте дороже.
- **M2 раньше M3** — `ToolScaffold` и `NavigationSplitView` переписывают каркас всех 22 экранов.
  Полировать пустые состояния и анимации до этого — переделывать дважды.
- **M4 параллельно M2/M3** — `ToolRunModel` и `ToolScaffold` это две половины одного рефакторинга;
  вынос логики в NetworkKit делает её тестируемой.
- **M5 и M6 после M4** — новые инструменты и фоновые сценарии садятся на `CheckRunner`,
  единую обработку ошибок и `ToolScaffold`, иначе каждый новый экран снова копирует 200 строк.

---

## M1 · Стабилизация и релиз

Без этого приложение нельзя выпускать: блокеры App Store, потеря данных, нелокализованный UI.

| # | Задача | Приоритет |
|---|---|---|
| [#5](https://github.com/AuthFailed/CheckNet/issues/5) | `PrivacyInfo.xcprivacy` — блокер ревью App Store | P0 |
| [#6](https://github.com/AuthFailed/CheckNet/issues/6) | CI: гонять `swift test` и собирать macOS | P0 |
| [#7](https://github.com/AuthFailed/CheckNet/issues/7) | Починить сборку macOS-таргета | P0 |
| [#8](https://github.com/AuthFailed/CheckNet/issues/8) | История: экспорт CSV/JSON выполняется в `body` | P0 |
| [#9](https://github.com/AuthFailed/CheckNet/issues/9) | История: захардкоженная `ru_RU`-локаль | P0 |
| [#10](https://github.com/AuthFailed/CheckNet/issues/10) | 46 непереведённых ключей в каталоге строк | P0 |
| [#11](https://github.com/AuthFailed/CheckNet/issues/11) | `SharedStore`: гонка при записи истории | P0 |
| [#13](https://github.com/AuthFailed/CheckNet/issues/13) | Профили сети не работают без Wi-Fi-entitlement | P1 |

**Порядок внутри вехи:** #7 → #6 (CI не может собирать сломанный таргет) → остальное параллельно.

---

## M2 · Адаптивный UI (iPad + macOS)

Главный визуальный долг. Сейчас это «растянутый айфон» на всех широких экранах.

| # | Задача | Приоритет |
|---|---|---|
| [#14](https://github.com/AuthFailed/CheckNet/issues/14) | `NavigationSplitView` + `.tabViewStyle(.sidebarAdaptable)` | P1 |
| [#15](https://github.com/AuthFailed/CheckNet/issues/15) | `ToolScaffold` — единый контейнер с ограничением ширины | P1 |
| [#16](https://github.com/AuthFailed/CheckNet/issues/16) | Фиксированные ширины/высоты, ломающие Dynamic Type | P1 |
| [#17](https://github.com/AuthFailed/CheckNet/issues/17) | Sheets без `presentationDetents` | P2 |
| [#18](https://github.com/AuthFailed/CheckNet/issues/18) | macOS: `MenuBarExtra`, `.commands`, сцена `Settings` | P1 |
| [#19](https://github.com/AuthFailed/CheckNet/issues/19) | Landscape на iPhone | P2 |

**Порядок:** #15 (каркас) → #14 (навигация поверх него) → #16 → #17/#19 → #18 (зависит от #7).

---

## M3 · UX-полировка

То, что отличает «работает» от «приятно пользоваться».

| # | Задача | Приоритет |
|---|---|---|
| [#20](https://github.com/AuthFailed/CheckNet/issues/20) | Haptics — сейчас 0 вызовов на весь проект | P1 |
| [#21](https://github.com/AuthFailed/CheckNet/issues/21) | Доступность: статус только цветом, иконки без лейблов | P1 |
| [#22](https://github.com/AuthFailed/CheckNet/issues/22) | Dynamic Type: 39 хардкодов `.font(.system(size:))` | P1 |
| [#23](https://github.com/AuthFailed/CheckNet/issues/23) | Единая обработка ошибок + «Повторить» | P1 |
| [#24](https://github.com/AuthFailed/CheckNet/issues/24) | Idle-состояния на 12 экранах | P2 |
| [#25](https://github.com/AuthFailed/CheckNet/issues/25) | Поиск: синонимы в каталоге, поиск в истории | P2 |
| [#26](https://github.com/AuthFailed/CheckNet/issues/26) | Reduce motion и `numericText` | P2 |
| [#27](https://github.com/AuthFailed/CheckNet/issues/27) | Pull-to-refresh на списках | P3 |
| [#28](https://github.com/AuthFailed/CheckNet/issues/28) | Экраны без ⓘ и асимметрия в Блокировках | P2 |
| [#29](https://github.com/AuthFailed/CheckNet/issues/29) | Заглушка не объясняет, почему инструмент недоступен | P2 |
| [#30](https://github.com/AuthFailed/CheckNet/issues/30) | Онбординг и pre-permission для локальной сети | P2 |
| [#31](https://github.com/AuthFailed/CheckNet/issues/31) | `onTapGesture` вместо `NavigationLink` | P2 |

**Порядок:** #23 (единая фаза/ошибка) → #20 и #24 садятся на неё → #21/#22 → остальное.

---

## M4 · Архитектура и тесты

Убирает дублирование и закрывает самый рискованный непокрытый код.

| # | Задача | Приоритет |
|---|---|---|
| [#32](https://github.com/AuthFailed/CheckNet/issues/32) | `ToolRunModel<T>` — схлопнуть ~15 моделей | P2 |
| [#33](https://github.com/AuthFailed/CheckNet/issues/33) | Вынести `BlockingCheck.run` в NetworkKit | P1 |
| [#34](https://github.com/AuthFailed/CheckNet/issues/34) | Дублирование: `CheckRecord`, `PingConfig`, персистенс | P2 |
| [#35](https://github.com/AuthFailed/CheckNet/issues/35) | Тесты на `X509Parser` (рукописный DER) | P1 |
| [#36](https://github.com/AuthFailed/CheckNet/issues/36) | Тесты на `DNSMessage`, включая pointer loop | P1 |
| [#37](https://github.com/AuthFailed/CheckNet/issues/37) | Таргет `CheckNetTests` для `App/` и `Shared/` | P1 |
| [#38](https://github.com/AuthFailed/CheckNet/issues/38) | Непокрытые движки NetworkKit | P2 |

**Порядок:** #35/#36 (риск безопасности и зависаний) → #37 → #33 → #34 → #32.
#32 делается вместе с #15 — это один рефакторинг с двух сторон.

---

## M5 · Платформенные интеграции

Здесь приложение перестаёт быть «утилитой, которую открывают руками».

| # | Задача | Приоритет |
|---|---|---|
| [#39](https://github.com/AuthFailed/CheckNet/issues/39) | Фоновый мониторинг через `BGTask` | P1 |
| [#40](https://github.com/AuthFailed/CheckNet/issues/40) | Уведомления: actions, time-sensitive, foreground | P2 |
| [#41](https://github.com/AuthFailed/CheckNet/issues/41) | Control Center + Lock Screen виджеты | P2 |
| [#42](https://github.com/AuthFailed/CheckNet/issues/42) | Siri: донат интентов, `AppEntity` хостов | P2 |
| [#43](https://github.com/AuthFailed/CheckNet/issues/43) | iCloud-синхронизация, Handoff, Spotlight | P2 |
| [#44](https://github.com/AuthFailed/CheckNet/issues/44) | Focus filters, интерактивная Live Activity | P3 |
| [#45](https://github.com/AuthFailed/CheckNet/issues/45) | watchOS и visionOS — исследование | P3 |

**Порядок:** #39 → #40 (уведомления осмысленны только при работающем фоне) → #41/#42 → #43 → #44/#45.

> Виджеты в #41 — **только те, что пользователь добавляет сам** (Control Center, локскрин).
> Виджет главного экрана после установки не появляется и появляться не должен.

---

## M6 · Новые инструменты

| # | Задача | Приоритет |
|---|---|---|
| [#46](https://github.com/AuthFailed/CheckNet/issues/46) | Bufferbloat — задержка под нагрузкой | P1 |
| [#47](https://github.com/AuthFailed/CheckNet/issues/47) | Геолокация IP и World Ping — выбрать источник | P2 |
| [#48](https://github.com/AuthFailed/CheckNet/issues/48) | Wi-Fi-анализ на macOS через CoreWLAN | P2 |
| [#49](https://github.com/AuthFailed/CheckNet/issues/49) | Пул идей для конкурентного отрыва | P3 |

**#46 первым** — движок нагрузки уже есть (`IperfClient`, `CloudflareSpeedTest`), а сама проверка
востребована больше остальных: именно bufferbloat объясняет «интернет быстрый, но звонки рвутся».

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
