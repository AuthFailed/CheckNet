# Технический аудит перед подачей (#88 / #93 / #94 / #95 / #97)

Фактические выводы по коду на ветке M8. Где нужен собранный бинарь — помечено «pending build».

## #94 · PrivacyInfo.xcprivacy (required-reason API)

Манифесты есть: `App/Resources/PrivacyInfo.xcprivacy` и `Widgets/PrivacyInfo.xcprivacy`. Оба:
`NSPrivacyTracking=false`, нет собираемых типов, объявлен только UserDefaults (`CA92.1`).

Аудит использования required-reason API в **Swift-коде** (App/Shared/NetworkKit):

| Категория | Найдено | Нужно объявлять? |
|---|---|---|
| UserDefaults | да | **да — уже есть `CA92.1`** ✅ |
| File timestamp | нет (`modificationDate/creationDate/getattrlist/stat` не встречаются) | нет |
| System boot time | `MonoClock` → `clock_gettime(CLOCK_MONOTONIC_RAW)` — **не в списке Apple** (там `systemUptime`/`mach_absolute_time`) | нет |
| Disk space | только `.fileSizeKey` в `XrayCoreStore` — это размер файла, **не** volume-capacity/`statfs` | нет |
| Active keyboard | нет | нет |

**Вывод:** для Swift-кода манифест корректен и полон. Предположение из ROADMAP (file timestamp /
boot time / disk space) на деле не подтверждается — эти API не используются.

**Открытый пункт — libXray (pending build).** `Frameworks/LibXray.xcframework` — статический Go-core,
**без своего privacy-манифеста**. Go-рантайм может вызывать `stat`/`statfs`/`mach_absolute_time`.
Apple сканирует символы бинаря (ITMS-91053). Нужно после сборки:
```sh
# по iOS-бинарю приложения:
nm -u "$APP/CheckNet" | grep -E '\b(stat|fstat|lstat|statfs|fstatfs|mach_absolute_time|getattrlist)\b'
```
Если символы есть — добавить в `App/Resources/PrivacyInfo.xcprivacy` reason-коды:
- File timestamp → `DDA9.1` (файлы в контейнере приложения);
- Disk space → `E174.1` (проверка места перед записью core-файла);
- System boot time → `35F9.1` (измерение интервалов).
Reason-коды заготовлены; вставлю по факту `nm`.

## #88 · Приватные API (2.5.1)

Рискованные места и их гейтинг:

| API | Файл | Гейт | В iOS-бинаре? |
|---|---|---|---|
| `rt_msghdr2`, `sysctl(NET_RT_FLAGS)` | `NetworkKit/Browser/ARPTable.swift` | `#if os(macOS)` | **нет** ✅ |
| CoreWLAN (`CWWiFiClient`) | `NetworkKit/Info/WiFiInfo.swift` | `#if canImport(CoreWLAN)` (macOS-only) | **нет** ✅ |
| `NEHotspotNetwork.fetchCurrent` | `App/Network/CurrentNetwork.swift` | публичный API (не приватный); за флагом `isSSIDReadable` | да, но это публичный API |
| ICMP `SOCK_DGRAM` | `NetworkKit/Support` | публичный, непривилегированный | да, ок |

**Вывод:** статически чисто — оба macOS-only символа компилируются вне iOS. Финальное
подтверждение — pending build:
```sh
nm "$APP/CheckNet" | grep -iE 'rt_msghdr2|CWWiFiClient|CoreWLAN'   # ожидаем пусто
```

## #97 · Санити Info.plist

Проверено в `App/Info.plist` / `project.yml`:
- Usage-строки на месте: `NSLocalNetworkUsageDescription`, `NSLocationWhenInUseUsageDescription`
  (объясняет, что только для SSID), `NSCameraUsageDescription`. ✅
- `NSBonjourServices` — полный список типов (иначе mDNS молча не работает). ✅
- Ориентации: portrait + оба landscape; `TARGETED_DEVICE_FAMILY=1,2` (iPhone+iPad). ✅
- Background: `UIBackgroundModes=[fetch]` + `BGTaskSchedulerPermittedIdentifiers` — обоснованно
  (мониторинг хостов). ✅ Обоснование для ревью — в `review-notes.md`.
- Deep links (`checknet`), Live Activities, Handoff (`NSUserActivityTypes`) объявлены. ✅
- Min deployment iOS 26 / macOS 26. ✅
- ATS: единственное исключение — `ip-api.com` (HTTP-only геосервис), обосновано комментарием. ✅
- ⚠️ `ITSAppUsesNonExemptEncryption=false` — **см. `export-compliance.md`**: с учётом крипты
  Happ/Incy это значение под вопросом, вероятно `true` + exemption. Решение за тобой.

## #95 · Версия / debug-логи / тестовые хосты / dSYM

- **Debug-логи:** нет `#if DEBUG`, нет отладочных `print()`. Единственный логгер — структурный
  `os.Logger` в `SpotlightIndexer` (норм для релиза). ✅
- **Тестовые хосты:** `example.com` / `8.8.8.8` — это UI-плейсхолдеры и дефолты полей ввода,
  `127.0.0.1` — локальный SOCKS-бинд теста. Не артефакты, удалять не нужно. ✅
- **Версия:** `MARKETING_VERSION=1.0`, `CURRENT_PROJECT_VERSION=1` — корректно для первой подачи.
- **dSYM (pending build):** для Release `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym` (дефолт Release) —
  dSYM попадёт в архив; выгрузится вместе с бинарём. Проверить после `xcodebuild archive`.

## #93 · Entitlements audit

- **iOS** (`App/CheckNet.entitlements`): сейчас только app-group. Дормантные (`wifi-info`,
  `ubiquity-kvstore-identifier`, `usernotifications.time-sensitive`) намеренно отсутствуют — с ними
  без Team ID/capabilities сборка не подписывается. Добавляю **вместе** с Team ID и включением
  capability на App ID (иначе ломается и локальная, и CI-сборка).
- **macOS** (`App/CheckNet-macOS.entitlements`): sandbox + network client/server — верно, ad-hoc
  сборка проходит.
- **Widgets**: app-group — верно.
- **Вывод:** текущий набор собирается. Приведение к App ID (включение дормантных) — шаг с Team ID,
  автоматическая подпись Xcode до-создаст профиль.

## Pending — что докручивается на сборке/Team ID

1. `nm`-скан iOS-бинаря → финал #88 и libXray-часть #94.
2. Добавление дормантных entitlements (#93 + задача 1) — после Team ID + capabilities на App ID.
3. `xcodebuild archive` c Team ID (#92), проверка dSYM (#95).
4. Решение по `ITSAppUsesNonExemptEncryption` (#83) → правка одного поля.
