# Поддержка CheckNet

CheckNet — приложение сетевой диагностики для iPhone, iPad и Mac.

## Как получить помощь

- **Вопросы и сообщения об ошибках:** заведите issue —
  [github.com/AuthFailed/CheckNet/issues](https://github.com/AuthFailed/CheckNet/issues)
- **Почта:** roman@chrsnv.ru

При обращении по ошибке полезно указать: версию приложения (Настройки → «О приложении»), модель
устройства и версию iOS/macOS, какой инструмент и с какими данными вы запускали.

## Частые вопросы

**CheckNet — это VPN?**
Нет. CheckNet не создаёт VPN-подключение, не маршрутизирует ваш трафик и не обходит блокировки.
Это набор диагностических проверок; раздел для операторов VPN проверяет **ваш собственный** сервер.

**Приложение собирает мои данные?**
Нет. См. [политику конфиденциальности](privacy-policy.md). Результаты остаются на устройстве.

**Почему инструмент просит разрешение на локальную сеть / геопозицию / камеру?**
Локальная сеть — для поиска устройств и Bonjour-сервисов; геопозиция — только чтобы iOS отдала имя
текущей Wi-Fi-сети (координаты не используются); камера — для сканирования QR со списком хостов.

**Некоторые Wi-Fi-инструменты пишут «доступно на Mac».**
iOS не отдаёт приложениям данные о Wi-Fi-каналах и соседних сетях — это ограничение платформы,
такие проверки работают в версии для Mac.

**Как очистить историю?**
Настройки → История → очистить.

---

# CheckNet Support (English)

CheckNet is a network-diagnostics app for iPhone, iPad, and Mac.

- **Issues / bug reports:** [github.com/AuthFailed/CheckNet/issues](https://github.com/AuthFailed/CheckNet/issues)
- **Email:** roman@chrsnv.ru

Include your app version (Settings → About), device model and OS version, and which tool you ran.

**Is CheckNet a VPN?** No — it doesn't tunnel or route your traffic or bypass restrictions; it's
diagnostics, and the operator section checks your own server.
**Does it collect data?** No — see the Privacy Policy; results stay on device.
