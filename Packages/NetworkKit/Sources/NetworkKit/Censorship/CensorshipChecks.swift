import Foundation

public enum CensorshipVerdict: String, Sendable, Codable {
    case clean          // no restriction observed
    case restricted     // restriction observed
    case inconclusive   // couldn't determine (e.g. control also failed)
}

public struct CensorshipFinding: Sendable {
    public let verdict: CensorshipVerdict
    public let headline: String
    public let detail: String
    public let evidence: [String]

    public init(verdict: CensorshipVerdict, headline: String, detail: String, evidence: [String]) {
        self.verdict = verdict
        self.headline = headline
        self.detail = detail
        self.evidence = evidence
    }
}

/// Client-side detection of local ISP restrictions, always comparing the user's
/// connection against a trusted control (OONI-style). Pure diagnostics.
public struct CensorshipChecks: Sendable {
    public init() {}

    // Canary resources (transparency test targets; not circumvention).
    public static let blockedCanaries = ["rutracker.org", "x.com", "www.tor-project.org"]
    public static let whitelistAnchors = ["gosuslugi.ru", "yandex.ru", "vk.ru", "sberbank.ru", "mail.ru"]
    public static let foreignControls = ["example.com", "wikipedia.org", "www.google.com"]
    static let blockPageMarkers = ["доступ ограничен", "ограничен доступ", "роскомнадзор",
                                   "149-фз", "заблокирован", "запрещ", "единый реестр"]

    // MARK: 1. DNS spoofing / substitution

    public func checkDNSSpoofing(domain: String = "rutracker.org") async -> CensorshipFinding {
        // IPv4 on purpose: compared against DoH A records below, so both sides
        // must be A records for the spoofing check to be apples-to-apples.
        let systemIPs = (try? await HostResolver.resolve(host: domain, family: .ipv4).map(\.ipString)) ?? []
        let dohIPs = (try? await DoHClient().resolveA(domain)) ?? []

        var evidence = ["Системный DNS: \(systemIPs.isEmpty ? "нет ответа" : systemIPs.joined(separator: ", "))",
                        "DoH 1.1.1.1: \(dohIPs.isEmpty ? "нет ответа" : dohIPs.joined(separator: ", "))"]

        if dohIPs.isEmpty {
            return CensorshipFinding(verdict: .inconclusive, headline: "Не удалось проверить",
                                     detail: "Эталонный резолвер (DoH) недоступен.", evidence: evidence)
        }
        if systemIPs.isEmpty {
            return CensorshipFinding(verdict: .restricted, headline: "Домен не резолвится провайдером",
                                     detail: "Ваш DNS не вернул адрес, а эталонный вернул — вероятна блокировка на уровне DNS.",
                                     evidence: evidence)
        }
        let systemSet = Set(systemIPs), dohSet = Set(dohIPs)
        if systemSet.isDisjoint(with: dohSet) {
            let privateInjected = systemIPs.contains { DNSClient.isPrivateOrLoopback($0) }
            evidence.append(privateInjected ? "Системный ответ указывает в приватную сеть — инъекция." : "Ответы полностью различаются.")
            return CensorshipFinding(verdict: .restricted, headline: "Похоже на подмену DNS",
                                     detail: "Провайдерский резолвер вернул другой адрес, чем эталонный. Это типичный признак DNS-подмены.",
                                     evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "Подмены DNS не обнаружено",
                                 detail: "Ответы провайдера и эталона совпадают.", evidence: evidence)
    }

    // MARK: 2. IP blocking

    public func checkIPBlocking(domain: String = "x.com") async -> CensorshipFinding {
        let dohIPs = (try? await DoHClient().resolveA(domain)) ?? []
        guard let targetIP = dohIPs.first else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Не удалось проверить",
                                     detail: "Не удалось получить реальный адрес домена.", evidence: [])
        }
        let scanner = PortScanner()
        let target = await scanner.check(host: targetIP, port: 443, timeout: 4)
        let control = await scanner.check(host: "1.1.1.1", port: 443, timeout: 4)

        let evidence = ["Цель \(targetIP):443 — \(target.isOpen ? "доступен" : "недоступен")",
                        "Контроль 1.1.1.1:443 — \(control.isOpen ? "доступен" : "недоступен")"]

        if !control.isOpen {
            return CensorshipFinding(verdict: .inconclusive, headline: "Нет связи",
                                     detail: "Даже контрольный адрес недоступен — проверьте подключение.", evidence: evidence)
        }
        if !target.isOpen {
            return CensorshipFinding(verdict: .restricted, headline: "IP-адрес заблокирован",
                                     detail: "Прямое подключение к реальному адресу домена не проходит, хотя контрольный адрес доступен.",
                                     evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "IP-блокировки нет",
                                 detail: "Реальный адрес домена доступен напрямую.", evidence: evidence)
    }

    // MARK: 3. SNI / TLS blocking (RST injection or drop)

    public func checkSNIBlocking(blockedDomain: String = "www.tor-project.org") async -> CensorshipFinding {
        let dohIPs = (try? await DoHClient().resolveA(blockedDomain)) ?? []
        guard let ip = dohIPs.first else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Не удалось проверить",
                                     detail: "Не удалось получить адрес домена.", evidence: [])
        }
        // Same IP, two SNIs: the blocked name vs a benign control name.
        let blocked = await tlsSucceeds(ip: ip, sni: blockedDomain)
        let control = await tlsSucceeds(ip: ip, sni: "example.com")

        let evidence = ["TLS к \(ip) с SNI=\(blockedDomain): \(blocked ? "успех" : "сброс/таймаут")",
                        "TLS к \(ip) с SNI=example.com: \(control ? "успех" : "сброс/таймаут")"]

        if !blocked && control {
            return CensorshipFinding(verdict: .restricted, headline: "Блокировка по SNI",
                                     detail: "Соединение с тем же IP рвётся только при «запрещённом» имени в TLS — это DPI-фильтрация по SNI.",
                                     evidence: evidence)
        }
        if !blocked && !control {
            return CensorshipFinding(verdict: .inconclusive, headline: "Хост недоступен",
                                     detail: "Оба соединения не прошли — вероятно, IP-блокировка или хост недоступен.", evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "SNI-блокировки нет",
                                 detail: "TLS-соединение с «запрещённым» именем проходит нормально.", evidence: evidence)
    }

    // MARK: 4. HTTP block page injection

    public func checkHTTPBlockPage(domain: String = "rutracker.org") async -> CensorshipFinding {
        guard let body = await httpBody(domain: domain) else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Нет ответа",
                                     detail: "HTTP-запрос не вернул тело.", evidence: ["GET http://\(domain)"])
        }
        let lower = body.lowercased()
        let hit = Self.blockPageMarkers.first { lower.contains($0) }
        if let hit {
            return CensorshipFinding(verdict: .restricted, headline: "Страница-заглушка блокировки",
                                     detail: "Провайдер подменил ответ страницей блокировки.",
                                     evidence: ["Найден маркер: «\(hit)»", "GET http://\(domain)"])
        }
        return CensorshipFinding(verdict: .clean, headline: "Заглушки не обнаружено",
                                 detail: "HTTP-ответ не содержит маркеров страницы блокировки.", evidence: ["GET http://\(domain)"])
    }

    // MARK: 5. Whitelist mode

    public func checkWhitelistMode() async -> CensorshipFinding {
        var anchorOK = 0, controlOK = 0
        var evidence: [String] = []
        for host in Self.whitelistAnchors {
            let ok = await PortScanner().check(host: host, port: 443, timeout: 4).isOpen
            if ok { anchorOK += 1 }
        }
        for host in Self.foreignControls {
            let ok = await PortScanner().check(host: host, port: 443, timeout: 4).isOpen
            if ok { controlOK += 1 }
        }
        // IP-layer control removes DNS from the equation.
        let ipControl = await PortScanner().check(host: "1.1.1.1", port: 443, timeout: 4).isOpen

        evidence.append("Из белого списка доступно: \(anchorOK)/\(Self.whitelistAnchors.count)")
        evidence.append("Зарубежных контролей доступно: \(controlOK)/\(Self.foreignControls.count)")
        evidence.append("Прямой IP 1.1.1.1:443: \(ipControl ? "доступен" : "недоступен")")

        if anchorOK >= 2 && controlOK == 0 && !ipControl {
            return CensorshipFinding(verdict: .restricted, headline: "Режим белого списка",
                                     detail: "Доступны только «разрешённые» ресурсы, всё остальное закрыто — похоже на whitelist-режим (региональный шатдаун).",
                                     evidence: evidence)
        }
        if controlOK == 0 && anchorOK == 0 {
            return CensorshipFinding(verdict: .inconclusive, headline: "Нет связи",
                                     detail: "Ничего не доступно — проверьте подключение.", evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "Белого списка нет",
                                 detail: "Зарубежные ресурсы доступны наравне с локальными.", evidence: evidence)
    }

    // MARK: 6. Siberian block (stateful TLS-flood throttle)

    public func checkSiberianBlock(host: String = "www.tor-project.org", bursts: Int = 30) async -> CensorshipFinding {
        let dohIPs = (try? await DoHClient().resolveA(host)) ?? []
        guard let ip = dohIPs.first else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Не удалось проверить",
                                     detail: "Не удалось получить адрес.", evidence: [])
        }
        // Fire many parallel TLS handshakes to the same host in a short window.
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<bursts {
                group.addTask { await self.tlsSucceeds(ip: ip, sni: host, timeout: 6) }
            }
            var r: [Bool] = []
            for await ok in group { r.append(ok) }
            return r
        }
        let ok = results.filter { $0 }.count
        let failed = results.count - ok
        let evidence = ["Параллельных TLS: \(results.count)", "Успешно: \(ok)", "Сорвалось: \(failed)"]

        // A stateful flood throttle lets the first handshakes through, then drops the rest.
        if ok >= 3 && failed >= max(5, bursts / 3) {
            return CensorshipFinding(verdict: .restricted, headline: "Похоже на «сибирскую» блокировку",
                                     detail: "Часть параллельных TLS-соединений к одному хосту срывается — характерно для DPI-троттлинга по количеству TLS-сессий. Обычно сбрасывается через ~2 минуты.",
                                     evidence: evidence)
        }
        if ok == 0 {
            return CensorshipFinding(verdict: .inconclusive, headline: "Хост недоступен",
                                     detail: "Ни одно соединение не прошло — вероятно, другая блокировка или хост недоступен.", evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "Троттлинга TLS не обнаружено",
                                 detail: "Все параллельные соединения прошли нормально.", evidence: evidence)
    }

    // MARK: Helpers

    private func tlsSucceeds(ip: String, sni: String, timeout: TimeInterval = 5) async -> Bool {
        do {
            _ = try await TLSInspector().inspect(host: ip, port: 443, serverName: sni,
                                                 alpnProtocols: ["h2", "http/1.1"], timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    private func httpBody(domain: String, timeout: TimeInterval = 6) async -> String? {
        guard let url = URL(string: "http://\(domain)/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return String(decoding: data.prefix(20_000), as: UTF8.self)
    }
}
