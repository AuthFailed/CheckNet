# App Store: подготовка к подаче

Рабочий индекс по вехе M8. Здесь два слоя:

- **Что уже сделано в коде/конфиге** — можно проверять в репозитории.
- **Что делаешь ты руками** — в Apple Developer / App Store Connect (ASC) / на GitHub Pages.
  Для каждого такого пункта ниже есть отдельный файл-черновик и пошаговый список «что нажать».

Черновики намеренно лежат в репозитории как обычные проектные документы. Публичными становятся
только `docs/legal/*` (политика и поддержка) — их публикуем через GitHub Pages.

## Всплывшие блокеры (важно)

- **CI был сломан.** С момента подключения libXray сборки iOS/macOS/CodeQL падали в CI (framework
  не фетчился). Исправлено на ветке `feat/m7-vpn-operator-tools` (шаг `Fetch libXray core`). После
  зелёного прогона PR #112 мержится в `main` (локализационный джоб остаётся красным → M10, по
  решению).
- **Иконки приложения нет вообще** (#100). Нет asset catalog, нет `AppIcon`, нет 1024 — hard-блокер
  подачи. Это дизайн-задача → готовый дизайн-бриф в `store-metadata.md`. Как получим
  иконку — завожу asset catalog и прописываю в `project.yml`.
- **`ITSAppUsesNonExemptEncryption=false`** может быть некорректным при крипте Happ/Incy — решение
  в `export-compliance.md`.

## Что нужно от тебя, чтобы снять оставшиеся блокеры

| Нужно | Зачем | Где взять |
|---|---|---|
| ~~Apple Team ID~~ **`A63H349525`** ✅ получен | Подпись релизного архива, capabilities App ID | — |
| Подтвердить bundle ID | Уже стоит `com.chrsnv.checknet` (виджеты `.widgets`, группа `group.com.chrsnv.checknet`) | — |
| Включить capabilities на App ID | Дормантные фичи (iCloud KVS, Wi-Fi Info, Time-Sensitive) физически не подпишутся без этого | developer.apple.com → Identifiers |
| Разрешить локальные сборки | `xcodebuild archive` / `nm`-аудит iOS-бинаря (#88, #92) | подтвердить в сессии |

## Статус по задачам M8

### A — код/конфиг (я)
| # | Что | Статус |
|---|---|---|
| 1 · iCloud sync | флаг `CloudHostSync.isAvailable`, тесты `SavedHostMerge.union` | код-половина готова, тесты есть; **ждёт entitlement (Team ID + capability)** |
| 1 · Wi-Fi SSID | флаг `CurrentNetwork.isSSIDReadable`, iOS-путь | код-половина готова; **ждёт entitlement** |
| 1 · Time-sensitive | `HostNotifier` уже ставит `.timeSensitive` | код готов; **ждёт entitlement** |
| #94 privacy manifest | required-reason API | Swift-код чист (только UserDefaults `CA92.1`, уже задекларировано). **Открыт libXray** — нужен `nm` по бинарю |
| #93 entitlements audit | привести capabilities к App ID | текущие файлы собираются; дормантные — добавляю вместе с Team ID |
| #97 Info.plist sanity | usage-строки, ориентации, background modes | в порядке; см. `audit-findings.md` |
| #88 приватные API | raw sockets, `rt_msghdr2`, CoreWLAN | статически чисто (всё под `#if os(macOS)` / `canImport(CoreWLAN)`); **`nm` по iOS-бинарю pending** |
| #95 версия/логи/dSYM | debug-логи, тест-хосты | чисто: нет `#if DEBUG`, нет debug-`print`, хосты — это UI-плейсхолдеры. Версия 1.0/build 1 ок для первой подачи. dSYM — на этапе архива |
| #92 релизный архив | подпись Team ID, `xcodebuild archive` | **ждёт Team ID** |

### B — твои действия (черновики готовлю я)
| # | Что | Файл-черновик |
|---|---|---|
| #82 | Политика конфиденциальности + Support | `../legal/privacy-policy.md`, `../legal/support.md` |
| #83 | Экспортный контроль шифрования | `export-compliance.md` |
| #85/#86/#87 | Заметки ревьюеру, граница 5.4 VPN, крипта/сканеры, демо-данные | `review-notes.md` |
| #89 | App Privacy («Data Not Collected») | `app-privacy.md` |
| #90 | Возрастной рейтинг | `age-rating.md` |
| #98–#101 | Метаданные стора, скриншоты, иконка | `store-metadata.md` |
| #102–#105 | QA на устройстве | `device-qa-checklist.md` |

## Порядок

1. **Блокеры подачи (A группа + технический билд):** аккаунт/соглашения (#80/#81, ты), экспортный
   статус (#83), дистрибуционная подпись (#92/#93), privacy-манифест (#94), App-Privacy-метки (#89).
2. **Юридический слой параллельно:** политика + support на Pages (#82/#111).
3. **Ревью-риски (B):** заметки ревьюеру и граница 5.4 (#85/#86/#87) — из-за чего именно наше
   приложение могут развернуть.
4. **Витрина + QA:** метаданные/скриншоты (#98–#101) и прогон на устройстве (#102–#105).
5. **Бета:** TestFlight (#106/#107). **Автоматизация:** fastlane/CI (#108–#111), по мере надобности.
