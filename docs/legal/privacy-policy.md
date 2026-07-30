# Политика конфиденциальности CheckNet

_Дата вступления в силу: <ДАТА>. Контакт: <SUPPORT_EMAIL>._

> Черновик для публикации через GitHub Pages (#82/#111). Перед публикацией заполни `<ДАТА>` и
> `<SUPPORT_EMAIL>` (не хардкодим личную почту в репозиторий без твоего решения).

CheckNet — приложение сетевой диагностики. Оно спроектировано так, чтобы **не собирать о вас
никаких данных**.

## Что мы собираем

**Ничего.** У CheckNet нет серверов, аккаунтов, аналитики, рекламы и трекинга. Мы не собираем,
не храним и не передаём ваши персональные данные. Результаты проверок остаются на вашем устройстве.

## Данные на устройстве

Настройки, сохранённые хосты и история проверок хранятся **локально** на устройстве (и, если вы
включите синхронизацию iCloud, в вашем личном хранилище iCloud — оно принадлежит вам, не нам).
Вы можете очистить историю в настройках приложения в любой момент.

## Сетевые запросы, которые вы инициируете

CheckNet — это инструмент диагностики: он по вашей команде обращается к хостам и сервисам, которые
**вы указываете**. При использовании отдельных проверок запросы уходят к сторонним сервисам —
например:

- геолокация IP (внешний геосервис) — отправляется только публичный IP, который вы проверяете;
- «World Ping» и списки серверов скорости — обращение к сторонним каталогам;
- проверка версий инструментов — публичные релизы на GitHub;
- DNS-over-HTTPS резолверы — при проверках DNS/цензуры.

Эти запросы нужны для работы соответствующей проверки. Мы не добавляем к ним идентификаторов и не
получаем их результаты — они идут напрямую с вашего устройства.

Если вы **сами** настроите вебхук, CheckNet отправит результат проверки на **ваш** сервер по
указанному вами адресу. Это выключено по умолчанию.

## Разрешения

- **Локальная сеть** — для обнаружения устройств и Bonjour-сервисов в вашей сети.
- **Геопозиция** (только iOS, если включена соответствующая функция) — нужна исключительно для того,
  чтобы iOS отдала имя текущей Wi-Fi-сети; координаты не используются и никуда не отправляются.
- **Камера** — только для сканирования QR-кода со списком сохранённых хостов; изображения никуда
  не отправляются.
- **Уведомления** — для оповещений мониторинга хостов, если вы его включите.

## Дети

Приложение не предназначено для сбора данных о ком-либо, включая детей, и не собирает их.

## Изменения

Актуальная версия политики публикуется на этой странице; дата вступления в силу указана вверху.

## Контакт

Вопросы по конфиденциальности: <SUPPORT_EMAIL>.

---

# CheckNet Privacy Policy (English)

_Effective date: <DATE>. Contact: <SUPPORT_EMAIL>._

CheckNet is a network-diagnostics app designed to **collect no data about you**.

**What we collect:** nothing. CheckNet has no servers, accounts, analytics, ads, or tracking.
Results stay on your device.

**On-device data:** settings, saved hosts, and check history are stored locally (and, if you turn
on iCloud sync, in your own iCloud — which belongs to you, not us). You can clear history anytime.

**Requests you start:** CheckNet is a diagnostic tool — on your command it contacts hosts and
services you specify. Some checks send requests to third parties (IP geolocation, world-ping and
speed-test server lists, GitHub Releases for version checks, DNS-over-HTTPS resolvers). These go
directly from your device; we attach no identifiers and receive no results. If you configure a
webhook yourself, CheckNet posts a result to your own server (off by default).

**Permissions:** Local Network (device/Bonjour discovery); Location (iOS, only to let iOS return
the current Wi-Fi SSID — coordinates are never used or sent); Camera (only to scan a QR code of
saved hosts); Notifications (host-monitoring alerts, if enabled).

**Children:** the app collects no data from anyone, including children.

**Contact:** <SUPPORT_EMAIL>.
