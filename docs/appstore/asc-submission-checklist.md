# App Store Connect: чек-лист подачи 1.0

Пошагово, в порядке экранов ASC. Значения готовы — копируй. **Блокеры** помечены ⛔ (без них
кнопка Submit не разблокируется). Источники: остальные файлы в этой папке.

App: **CheckNet** · bundle `com.chrsnv.checknet` · SKU `checknet-ios` · app id 6796268067.

---

## A. Уровень приложения (заполняется один раз)

### A1. App Information (левое меню → General → App Information)
- **Category**: Primary **Utilities (Утилиты)**, Secondary **Developer Tools** (опц.).
- **Content Rights**: «Does not contain, show, or access third-party content» → у нас свои проверки;
  но мы показываем сторонние источники (geosite/geoip, iperf-list, bgp.tools). Отметь, что права на
  контент есть/не требуются (это наши запросы к публичным сервисам). Если сомнение — «Yes, contains
  third-party content» и в заметках объясни (см. #91).
- ⛔ **Privacy Policy URL**: нужен захостенный URL (см. блок «Что от меня» ниже). Поле обязательно.
- **Localizations**: основной — Russian. English можно добавить (метаданные ниже двуязычны).

### A2. App Privacy (левое меню → App Privacy) — см. `app-privacy.md`
- «Do you or your third-party partners collect data from this app?» → **No, we do not collect data**.
- Подтвердить метку **Data Not Collected**. Трекинга нет (ничего дополнительно не включать).

### A3. Age Rating (в разделе версии / App Information → Age Rating) — см. `age-rating.md`
- Все категории → **None**. **Unrestricted Web Access → No**. Kids Category — не заявлять.
- Ожидаемый итог: **4+**.

### A4. Pricing and Availability (левое меню)
- **Price**: Free (0). Проверить, что принят **Free Apps Agreement** (иначе поле недоступно).
- **Availability**: все страны (или по желанию). Для Франции крипта-декларация ANSSI — отдельно
  (см. `export-compliance.md`), подачу в Apple не блокирует.

---

## B. Уровень версии 1.0 (левое меню → iOS App → 1.0 Prepare for Submission)

### B1. Тексты — см. `store-metadata.md`
- **Promotional Text (170)**:
  `Сетевой комбайн для iPhone, iPad и Mac: пинг, трассировка, DNS, TLS, сканеры портов, проверки блокировок и инструменты для владельцев VPN-серверов. Всё на устройстве, без сбора данных.`
- **Description**: блок из `store-metadata.md` (#98).
- **Keywords (100)**:
  `ping,traceroute,dns,tls,ssl,порт,сканер,сеть,диагностика,mtr,whois,ip,bonjour,iperf,скорость,dnsbl`
- **Subtitle (30)**: `Пинг, DNS, TLS, порты и др.`
- ⛔ **Support URL**: захостенный URL (см. ниже). Обязателен.
- **Marketing URL**: опционально (можно тот же Pages-сайт).
- **What's New in This Version**: для 1.0 не показывается; если поле есть — `Первый релиз CheckNet.`

### B2. ⛔ Скриншоты (#99)
- Обязательные размеры: **iPhone 6.9″** (1320×2868) и **iPad 13″** (2064×2752).
- Ещё не сняты. Могу сгенерировать детерминированно через deep-link-харнесс на симуляторе
  (`-openTool <tool> -run`) — см. блок «Что от меня».

### B3. ⛔ Build
- Выбрать обработанный билд 1.0 (1) в секции **Build** (появится после окончания обработки).
- Иконку 1024 ASC берёт из билда (single-size AppIcon в asset catalog) — отдельно грузить не нужно.

### B4. App Review Information — см. `review-notes.md`
- **Sign-in required?** → **No** (аккаунта нет).
- **Contact**: имя, фамилия, телефон, email (твои — ASC требует контакт ревьюера).
- **Notes**: вставить английский блок из `review-notes.md` (раздел A) — про 5.4 (не VPN, не
  маршрутизируем трафик), сканеры (с согласием, как Fing), Happ/Incy (публичные ключи), приватность.
- **Demo / attachments**: публичные цели (1.1.1.1, cloudflare.com) + примеры ссылок `incy://crypt1/…`,
  `happ://…` для проверки декодеров (см. `review-notes.md` раздел B).

### B5. Export Compliance
- В билде стоит `ITSAppUsesNonExemptEncryption = false` → ASC **не спросит** дополнительно.
  Если всё же появится вопрос — «uses standard/exempt encryption», exemption (см. `export-compliance.md`).

### B6. Version Information
- **Copyright**: напр. `2026 <твоё имя/бренд>`.
- **Routing App Coverage / Marketing**: не требуется.

---

## C. Submit for Review
- Нажать **Add for Review** → **Submit to App Review**.
- После сабмита статус: Waiting for Review → In Review. Первое ревью обычно 24–48 ч.

---

## Что от меня (могу сделать сам)

1. **Скриншоты (#99)** — сгенерирую набор на симуляторе через deep-link по нескольким инструментам
   (ping/DNS/TLS/сканер/Блокировки/VPN/Текущая сеть Wi-Fi) в нужных размерах. Скажи — запускаю.
2. **GitHub Pages** для Privacy Policy + Support (#82/#111) — как дашь `<SUPPORT_EMAIL>` и дату,
   заполню `docs/legal/*`, включу Pages и дам тебе готовые URL для полей A1 и B1.

## Что только твоё
- Контакт ревьюера (имя/тел/email) в B4.
- Приём Free Apps Agreement (если ещё не принят) для A4.
- Финальный Submit (кнопка).
