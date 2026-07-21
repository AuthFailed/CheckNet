# Вебхуки CheckNet

CheckNet может отправлять результаты проверок на ваш сервер. Выключено по умолчанию: отправка — это раскрытие данных, поэтому она включается вручную в **Настройки → Интеграции → Вебхуки**.

## Запрос

```
POST <ваш адрес>
Content-Type: application/json
User-Agent: CheckNet/1.0
X-CheckNet-Event: blocking.transferCutoff
X-CheckNet-Version: 1
X-CheckNet-Signature: sha256=<hex>   # только если задан секрет
```

Адрес должен быть `https`. Исключение — `localhost` / `127.0.0.1`, чтобы можно было отладить приём локально; на любой другой хост по `http` отправка не разрешается, иначе результаты ушли бы в открытом виде.

`Content-Type` зависит от выбранного формата (см. ниже).

## Формат

В настройках выбирается один из трёх форматов тела:

| Формат | Content-Type | Вид |
|---|---|---|
| JSON (вложенный) | `application/json` | по умолчанию; вложенные списки остаются массивами объектов |
| JSON (плоский) | `application/json` | списки разворачиваются в ключи `samples.0.rttMillis` |
| Form URL-encoded | `application/x-www-form-urlencoded` | `key=value&…`, элементы списка как `samples[0][rttMillis]` |

Типы сохраняются: числа — числами, булевы — булевыми, даты — ISO-8601 UTC.

## Выбор полей

По умолчанию отправляются **все** поля, которые инструмент умеет отдавать. В настройках любое поле можно отключить, а для промежуточных результатов (например ping-сэмплов) — отключить как весь список, так и отдельные подполя в каждом элементе. Отключённое поле в payload не попадает.

## Тело

```json
{
  "version": 1,
  "event": "blocking.transferCutoff",
  "timestamp": "2026-07-20T18:24:05Z",
  "host": "cloudflare.com",
  "succeeded": false,
  "verdict": "restricted",
  "headline": "Соединение обрывают по числу пакетов",
  "detail": "Мелкий запрос прошёл одним пакетом, но замер, когда те же байты отправлены 33 пакетами.",
  "latencyMillis": 12.5,
  "lossPercent": 0,
  "metadata": { "source": "settings" }
}
```

| Поле | Тип | Всегда | Значение |
|---|---|---|---|
| `version` | int | да | Версия формата. Сейчас `1`. |
| `event` | string | да | Тип события, см. ниже. |
| `timestamp` | string | да | ISO-8601, UTC. |
| `host` | string | да | Цель проверки. |
| `succeeded` | bool | да | `false`, если проверка нашла проблему. |
| `verdict` | string? | нет | `clean` / `restricted` / `inconclusive`. |
| `headline` | string? | нет | Краткий вывод. |
| `detail` | string? | нет | Развёрнутое объяснение. |
| `latencyMillis` | number? | нет | Задержка, если измерялась. |
| `lossPercent` | number? | нет | Потери, если измерялись. |
| `metadata` | object? | нет | Дополнительные поля. Верхний уровень остаётся стабильным, всё нестандартное живёт здесь. |

Поля верхнего уровня — публичный контракт. Их переименование сломает чужие интеграции, поэтому оно потребует роста `version`.

## Типы событий

| `event` | Когда |
|---|---|
| `check.ping` | Завершился ping |
| `blocking.dnsSpoofing` | Проверка подмены DNS |
| `blocking.httpBlock` | Проверка страницы-заглушки |
| `blocking.sniBlocking` | Проверка блокировки по SNI |
| `blocking.ipBlocking` | Проверка блокировки по IP |
| `blocking.whitelist` | Проверка белых списков |
| `blocking.siberian` | «Сибирская» блокировка |
| `blocking.transferCutoff` | Обрыв на 16–20 КБ |
| `test.ping` | Тестовое событие из настроек |

Фильтр в настройках: **все проверки**, **только проблемы** (`succeeded == false`) или **только блокировки** (`event` начинается с `blocking.`).

## Проверка подписи

Если задан секрет, заголовок `X-CheckNet-Signature` содержит `sha256=` и HMAC-SHA256 от **тела запроса в том виде, в котором оно пришло**, в нижнем регистре hex.

Считайте HMAC от сырых байт тела, а не от переразобранного JSON — порядок ключей и пробелы должны совпасть.

```python
import hmac, hashlib

def verify(raw_body: bytes, header: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header)   # сравнение за постоянное время
```

```js
import { createHmac, timingSafeEqual } from "node:crypto";

function verify(rawBody, header, secret) {
  const expected = "sha256=" + createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(expected), b = Buffer.from(header);
  return a.length === b.length && timingSafeEqual(a, b);
}
```

## Ответы и повторы

| Ответ | Поведение |
|---|---|
| `2xx` | Доставлено. |
| `4xx` | Считается отказом получателя. **Повторов нет** — payload не изменится, а повторы только умножат шум. |
| `5xx`, таймаут, обрыв | До 3 попыток с растущей паузой (0,3 с → 1,2 с). |

Таймаут запроса — 10 с. Отправка идёт в фоне и никогда не блокирует интерфейс, поэтому медленный или мёртвый приёмник не подвешивает приложение.

## Локальная отладка

```sh
python3 -m http.server 8080
```

Укажите `http://localhost:8080/hook` и нажмите «Отправить тестовое событие». Простой `http.server` ответит `501` на POST — этого достаточно, чтобы увидеть сам запрос в логе; для проверки подписи нужен приёмник, отвечающий `200`.
