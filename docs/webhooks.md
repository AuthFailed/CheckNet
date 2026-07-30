# CheckNet Webhooks

CheckNet can send check results to your server. Disabled by default: sending data means disclosing it, so it is enabled manually in **Settings → Integrations → Webhooks**.

## Request

```
POST <your address>
Content-Type: application/json
User-Agent: CheckNet/1.0
X-CheckNet-Event: blocking.transferCutoff
X-CheckNet-Version: 1
X-CheckNet-Signature: sha256=<hex>   # only if a secret is set
```

The address must be `https`. The exception is `localhost` / `127.0.0.1`, so that you can debug reception locally; sending to any other host over `http` is not allowed, otherwise results would go out in the clear.

`Content-Type` depends on the selected format (see below).

## Format

In the settings you choose one of three body formats:

| Format | Content-Type | Description |
|---|---|---|
| JSON (nested) | `application/json` | default; nested lists remain arrays of objects |
| JSON (flat) | `application/json` | lists are expanded into keys `samples.0.rttMillis` |
| Form URL-encoded | `application/x-www-form-urlencoded` | `key=value&…`, list elements as `samples[0][rttMillis]` |

Types are preserved: numbers as numbers, booleans as booleans, dates as ISO-8601 UTC.

## Field selection

By default **all** fields the tool can provide are sent. In the settings any field can be disabled, and for intermediate results (for example ping samples) you can disable either the whole list or individual subfields in each element. A disabled field does not appear in the payload.

## Body

```json
{
  "version": 1,
  "event": "blocking.transferCutoff",
  "timestamp": "2026-07-20T18:24:05Z",
  "host": "cloudflare.com",
  "succeeded": false,
  "verdict": "restricted",
  "headline": "Connection is cut off by packet count",
  "detail": "A small request went through in a single packet, but stalled when the same bytes were sent as 33 packets.",
  "latencyMillis": 12.5,
  "lossPercent": 0,
  "metadata": { "source": "settings" }
}
```

| Field | Type | Always | Meaning |
|---|---|---|---|
| `version` | int | yes | Format version. Currently `1`. |
| `event` | string | yes | Event type, see below. |
| `timestamp` | string | yes | ISO-8601, UTC. |
| `host` | string | yes | The check target. |
| `succeeded` | bool | yes | `false` if the check found a problem. |
| `verdict` | string? | no | `clean` / `restricted` / `inconclusive`. |
| `headline` | string? | no | Brief conclusion. |
| `detail` | string? | no | Detailed explanation. |
| `latencyMillis` | number? | no | Latency, if measured. |
| `lossPercent` | number? | no | Loss, if measured. |
| `metadata` | object? | no | Additional fields. The top level stays stable; anything non-standard lives here. |

The top-level fields are a public contract. Renaming them would break third-party integrations, so it would require a bump of `version`.

## Event types

| `event` | When |
|---|---|
| `check.ping` | A ping finished |
| `blocking.dnsSpoofing` | DNS spoofing check |
| `blocking.httpBlock` | Block-page check |
| `blocking.sniBlocking` | SNI blocking check |
| `blocking.ipBlocking` | IP blocking check |
| `blocking.whitelist` | Whitelist check |
| `blocking.siberian` | "Siberian" blocking |
| `blocking.transferCutoff` | Cutoff at 16–20 KB |
| `test.ping` | Test event from settings |

Filter in the settings: **all checks**, **problems only** (`succeeded == false`), or **blocking only** (`event` starts with `blocking.`).

## Signature verification

If a secret is set, the `X-CheckNet-Signature` header contains `sha256=` and the HMAC-SHA256 of **the request body exactly as it arrived**, in lowercase hex.

Compute the HMAC over the raw body bytes, not over re-parsed JSON — the key order and whitespace must match.

```python
import hmac, hashlib

def verify(raw_body: bytes, header: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header)   # constant-time comparison
```

```js
import { createHmac, timingSafeEqual } from "node:crypto";

function verify(rawBody, header, secret) {
  const expected = "sha256=" + createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(expected), b = Buffer.from(header);
  return a.length === b.length && timingSafeEqual(a, b);
}
```

## Responses and retries

| Response | Behavior |
|---|---|
| `2xx` | Delivered. |
| `4xx` | Treated as a rejection by the receiver. **No retries** — the payload won't change, and retries would only multiply the noise. |
| `5xx`, timeout, drop | Up to 3 attempts with a growing pause (0.3 s → 1.2 s). |

The request timeout is 10 s. Sending happens in the background and never blocks the interface, so a slow or dead receiver won't hang the app.

## Local debugging

```sh
python3 -m http.server 8080
```

Point it at `http://localhost:8080/hook` and press "Send test event". A simple `http.server` will respond `501` to a POST — that's enough to see the request itself in the log; to verify the signature you need a receiver that responds `200`.
