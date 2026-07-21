import Foundation

/// The catalogue of tools that can emit webhooks, and the fields each one
/// exposes. Everything defaults on, so out of the box a webhook carries the
/// tool's full result.
public enum WebhookCatalog {
    public static let schemas: [WebhookSchema] = [ping, blocking, reachability]

    public static func schema(for toolKey: String) -> WebhookSchema? {
        schemas.first { $0.toolKey == toolKey }
    }

    // MARK: - Ping

    public static let ping = WebhookSchema(
        toolKey: "ping",
        toolLabel: "Ping",
        fields: [
            WebhookField("host", "Адрес"),
            WebhookField("resolvedIP", "IP-адрес"),
            WebhookField("avgMillis", "Средний пинг"),
            WebhookField("minMillis", "Минимум"),
            WebhookField("maxMillis", "Максимум"),
            WebhookField("jitterMillis", "Джиттер"),
            WebhookField("stddevMillis", "Стд. отклонение"),
            WebhookField("lossPercent", "Потери, %"),
            WebhookField("transmitted", "Отправлено"),
            WebhookField("received", "Получено"),
            // Intermediate results — off nothing by default, but the whole list
            // and each of its sub-fields can be dropped independently.
            WebhookField("samples", "Промежуточные результаты", children: [
                WebhookField("sequence", "Номер"),
                WebhookField("rttMillis", "Пинг"),
                WebhookField("ttl", "TTL"),
                WebhookField("sourceIP", "Источник")
            ])
        ]
    )

    /// Values for a completed ping run.
    public static func pingValues(_ stats: PingStatistics, samples: [PingReply]) -> [String: WebhookValue] {
        var values: [String: WebhookValue] = [
            "host": .string(stats.host),
            "resolvedIP": .string(stats.resolvedIP),
            "lossPercent": .double(stats.lossPercent),
            "transmitted": .int(stats.transmitted),
            "received": .int(stats.received)
        ]
        values["avgMillis"] = stats.avg.map(WebhookValue.double) ?? .null
        values["minMillis"] = stats.min.map(WebhookValue.double) ?? .null
        values["maxMillis"] = stats.max.map(WebhookValue.double) ?? .null
        values["jitterMillis"] = stats.jitter.map(WebhookValue.double) ?? .null
        values["stddevMillis"] = stats.stddev.map(WebhookValue.double) ?? .null
        values["samples"] = .objects(samples.map { reply in
            [
                "sequence": .int(reply.sequence),
                "rttMillis": .double(reply.rttMillis),
                "ttl": reply.ttl.map(WebhookValue.int) ?? .null,
                "sourceIP": .string(reply.sourceIP)
            ]
        })
        return values
    }

    // MARK: - Blocking checks

    public static let blocking = WebhookSchema(
        toolKey: "blocking",
        toolLabel: "Блокировки",
        fields: [
            WebhookField("check", "Проверка"),
            WebhookField("target", "Цель"),
            WebhookField("verdict", "Вердикт"),
            WebhookField("headline", "Заголовок"),
            WebhookField("detail", "Подробности"),
            WebhookField("evidence", "Данные проверки", children: [
                WebhookField("line", "Строка")
            ])
        ]
    )

    public static func blockingValues(check: String, target: String, finding: CensorshipFinding) -> [String: WebhookValue] {
        [
            "check": .string(check),
            "target": .string(target),
            "verdict": .string(finding.verdict.rawValue),
            "headline": .string(finding.headline),
            "detail": .string(finding.detail),
            "evidence": .objects(finding.evidence.map { ["line": .string($0)] })
        ]
    }

    // MARK: - Reachability

    public static let reachability = WebhookSchema(
        toolKey: "reachability",
        toolLabel: "Доступность",
        fields: [
            WebhookField("scope", "Группа"),
            WebhookField("verdict", "Вердикт"),
            WebhookField("reachable", "Доступно"),
            WebhookField("obstructed", "Обрывов"),
            WebhookField("total", "Всего"),
            WebhookField("nodes", "Узлы", children: [
                WebhookField("host", "Хост"),
                WebhookField("provider", "Провайдер"),
                WebhookField("status", "Статус"),
                WebhookField("handshakeMillis", "Рукопожатие, мс")
            ])
        ]
    )

    public static func reachabilityValues(scope: String, results: [ReachabilityResult], verdict: String) -> [String: WebhookValue] {
        [
            "scope": .string(scope),
            "verdict": .string(verdict),
            "reachable": .int(results.filter { $0.status == .reachable }.count),
            "obstructed": .int(results.filter { $0.status == .obstructed }.count),
            "total": .int(results.count),
            "nodes": .objects(results.map { r in
                [
                    "host": .string(r.target.host),
                    "provider": .string(r.target.provider),
                    "status": .string(r.status.rawValue),
                    "handshakeMillis": r.handshakeMillis.map(WebhookValue.double) ?? .null
                ]
            })
        ]
    }
}
