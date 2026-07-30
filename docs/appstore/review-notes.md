# Заметки ревьюеру и границы App Review (#85 / #86 / #87)

Цель — снять два главных риска ревью: **5.4 (VPN)** и **чувствительные инструменты** (сетевые
сканеры, крипто-разборщики). Приложение — диагностика и подготовка конфигов; оно **не** маршрутизирует
трафик и **не** обходит блокировки.

---

## A. Текст для App Review Information (App Store Connect → «Notes»)

> Копипастить в поле Review Notes. Английский — ревьюер читает на нём. Держать коротким и прямым.

```
CheckNet is a network-diagnostics utility (like Fing/iNet) with an extra section of read-only
tools for people who run their own VPN servers. It does NOT provide a VPN tunnel, does NOT route
or proxy the user's traffic, and does NOT circumvent any network restriction. Every tool is
diagnostic: it measures or inspects, it does not change how the device connects.

Guideline 5.4: The app installs no VPN configuration and contains no NEVPNManager / Network
Extension packet-tunnel. The "VPN" section is a set of checks an operator runs AGAINST a server
they already control (is the inbound reachable, does the TLS/Reality handshake look right, what
egress IP does the proxy show). Nothing tunnels the user's own traffic.

Sensitive tools and why they are safe/legitimate:
- Port scan / IP-range scan / Reality dest scanner: standard diagnostics. They run only after an
  explicit in-app consent dialog that explains what will happen. Intended for the user's own hosts
  and networks (same category as Fing, which is approved).
- "Блокировки" (Censorship checks): transparency/diagnostics only — they DETECT what the local
  network blocks by comparing a probe to a control. They contain NO circumvention (no DPI bypass,
  no SNI fragmentation, no domain fronting).
- Happ Decrypt / Incy link (crypt1): these decode the operator's OWN subscription links using
  PUBLIC keys that ship inside the corresponding open-source clients. Standard algorithms
  (RSA, AES-GCM, ChaCha20-Poly1305) via Apple frameworks. It is a convenience decoder, not an
  attack tool — it only reads data the user already possesses.

Privacy: the app collects nothing. All results stay on device; the only outbound traffic is the
checks the user starts and, if the user configures one, a webhook to a server the user owns.

Demo: no login required. See the "How to try the VPN section" steps below and the demo data.
```

## B. Как ревьюеру прогнать VPN-раздел (демо-данные)

Ревьюер должен суметь нажать и увидеть результат без нашей инфраструктуры. Подготовить:

1. **Демо-хост / подписка**, живущие на время ревью (можно поднять на дешёвом VPS или реюзнуть
   тестовый). Указать в заметках прямо:
   - `Тесты` → `Ping` / `TLS-инспектор`: `1.1.1.1`, `cloudflare.com` — работают без нашей инфры.
   - `VPN` → проверка inbound/Reality: демо-адрес `<DEMO_HOST:PORT>`, SNI `<DEMO_SNI>`.
   - `VPN` → Happ/Incy: приложить **пример ссылки** `incy://crypt1/<...>` и `happ://<...>` —
     ревьюер вставит и увидит, что раскодировалось в обычный URL подписки.
2. **Deep-link для быстрой демонстрации** (уже есть в приложении): `checknet://` +
   `-openTool <tool> -host <h> -run` — можно дать ревьюеру пару готовых ссылок.
3. Явно написать: «no account needed», чтобы не поставили 5.1.1 (login).

> TODO для тебя: решить, поднимаем ли отдельный демо-хост на время ревью или даём публичные цели
> (1.1.1.1 и т. п.) + статические примеры ссылок. Минимально достаточно публичных целей + примеров
> ссылок; демо-хост усиливает шанс с первого раза.

## C. Граница 5.4 — что гарантируем кодом (для #87)

Проверяемые факты (можно показать ревьюеру и держать как самопроверку перед подачей):

- **Нет** `NEVPNManager`, `NETunnelProvider*`, `NEPacketTunnelProvider`, Network Extension таргета.
- **Нет** entitlement `com.apple.developer.networking.networkextension` / `packet-tunnel-provider`.
- libXray используется **in-process** только чтобы поднять локальную проверку inbound/egress и
  тут же погасить — не как системный туннель.
- Прокси-раннер слушает на `127.0.0.1` для локального SOCKS-теста, не перехватывает системный трафик.

Самопроверка (держать зелёной):

```sh
# Должно быть пусто:
grep -rn "NEVPNManager\|NETunnelProvider\|NEPacketTunnel\|packet-tunnel" App Shared Packages Widgets \
  | grep -v "\.build/"
```

**Митигация при риске:** если ревьюер цепляется к слову «VPN», переименовать раздел в
«Инструменты оператора» (строка заголовка вкладки) — контент не меняется. Держать это как запасной
ход, не делать превентивно (раздел честно про VPN-серверы).

## D. Формулировки в описании стора (см. `store-metadata.md`)

- Не писать «VPN» как категорию/фичу без слова «диагностика/инструменты».
- Явная строка в описании: «CheckNet не является VPN, не маршрутизирует трафик и не обходит
  блокировки — это диагностика и подготовка конфигов».
- Не обещать обход блокировок нигде в метаданных (иначе 5.4 + вероятный реджект).
