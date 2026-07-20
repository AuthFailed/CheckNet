import Foundation

/// A host to probe, and what it stands for.
///
/// Probing a *provider* means probing a host that happens to live in that
/// provider's address space — the filtering is keyed on destination network, so
/// any host inside it will do. That's why the hostnames below are unremarkable
/// third-party sites rather than the providers' own front pages.
public struct ProbeTarget: Sendable, Codable, Hashable, Identifiable {
    public enum Category: String, Sendable, Codable, CaseIterable {
        /// Foreign hosting/CDN — where transfer cutoffs are reported.
        case foreignInfrastructure
        /// Russian hosting — the control group; cutoffs are not reported here.
        case russianInfrastructure
        /// Sites users notice breaking first.
        case webService
        /// Push delivery. Silent notifications are a very common symptom and
        /// almost nobody connects them to filtering.
        case pushNotification

        public var label: String {
            switch self {
            case .foreignInfrastructure: "Зарубежные провайдеры"
            case .russianInfrastructure: "Российские провайдеры"
            case .webService: "Популярные сервисы"
            case .pushNotification: "Push-уведомления"
            }
        }
    }

    public let id: String
    public let provider: String
    /// ISO country code, or nil where it isn't meaningful.
    public let country: String?
    public let host: String
    public let category: Category

    /// Domestic destinations are the control arm for the transfer-cutoff check,
    /// so running that check *against* them proves nothing.
    public var skipTransferCutoff: Bool { category == .russianInfrastructure }

    public init(id: String, provider: String, country: String?, host: String, category: Category) {
        self.id = id
        self.provider = provider
        self.country = country
        self.host = host
        self.category = category
    }
}

/// Built-in probe targets, grouped by what they represent.
///
/// The foreign-infrastructure set is adapted from the `dpi-checkers` project by
/// hyperion-cs (Apache-2.0), which maintains it as a live measurement suite:
/// https://github.com/hyperion-cs/dpi-checkers
///
/// These hostnames go stale — sites move providers and disappear. Every probe
/// therefore reports liveness separately from interference, so a dead host reads
/// as "не проверено", never as "заблокировано".
public enum ProbeCatalog {
    /// When this list was last reconciled with upstream. Surfaced in the UI so a
    /// stale catalogue is visible rather than silently misleading.
    public static let revision = "2026-07-20"

    public static let all: [ProbeTarget] = foreign + russian + webServices + push

    public static func targets(in category: ProbeTarget.Category) -> [ProbeTarget] {
        all.filter { $0.category == category }
    }

    public static func target(id: String) -> ProbeTarget? {
        all.first { $0.id == id }
    }

    /// Grouped by provider, preserving catalogue order.
    public static func byProvider(in category: ProbeTarget.Category) -> [(provider: String, targets: [ProbeTarget])] {
        var order: [String] = []
        var buckets: [String: [ProbeTarget]] = [:]
        for target in targets(in: category) {
            if buckets[target.provider] == nil { order.append(target.provider) }
            buckets[target.provider, default: []].append(target)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    // MARK: - Foreign infrastructure

    static let foreign: [ProbeTarget] = [
        .init(id: "PL.AKM-01", provider: "Akamai", country: "PL", host: "www.mobil.com.se", category: .foreignInfrastructure),
        .init(id: "SE.AKM-01", provider: "Akamai", country: "SE", host: "cdn.apple-mapkit.com", category: .foreignInfrastructure),
        .init(id: "DE.AWS-01", provider: "AWS", country: "DE", host: "amplifon.com", category: .foreignInfrastructure),
        .init(id: "US.AWS-01", provider: "AWS", country: "US", host: "optout.aboutads.info", category: .foreignInfrastructure),
        .init(id: "US.CDN77-01", provider: "CDN77", country: "US", host: "cdn.eso.org", category: .foreignInfrastructure),
        .init(id: "CA.CF-01", provider: "Cloudflare", country: "CA", host: "go.coveo.com", category: .foreignInfrastructure),
        .init(id: "US.CF-01", provider: "Cloudflare", country: "US", host: "esm.sh", category: .foreignInfrastructure),
        .init(id: "FR.CNTB-01", provider: "Contabo", country: "FR", host: "antoniotartaglia.it", category: .foreignInfrastructure),
        .init(id: "DE.DO-01", provider: "DigitalOcean", country: "DE", host: "ui-arts.com", category: .foreignInfrastructure),
        .init(id: "UK.DO-01", provider: "DigitalOcean", country: "GB", host: "app.thecuriositylibrary.com", category: .foreignInfrastructure),
        .init(id: "CA.FST-01", provider: "Fastly", country: "CA", host: "ssl.p.jwpcdn.com", category: .foreignInfrastructure),
        .init(id: "US.FST-01", provider: "Fastly", country: "US", host: "www.jetblue.com", category: .foreignInfrastructure),
        .init(id: "US.FTBVM-01", provider: "FT/BuyVM", country: "US", host: "buyvm.net", category: .foreignInfrastructure),
        .init(id: "LU.GCORE-01", provider: "Gcore", country: "LU", host: "gcore.com", category: .foreignInfrastructure),
        .init(id: "US.GC-01", provider: "Google Cloud", country: "US", host: "api.usercentrics.eu", category: .foreignInfrastructure),
        .init(id: "DE.HE-01", provider: "Hetzner", country: "DE", host: "king.hr", category: .foreignInfrastructure),
        .init(id: "FI.HE-01", provider: "Hetzner", country: "FI", host: "nioges.com", category: .foreignInfrastructure),
        .init(id: "FI.HE-03", provider: "Hetzner", country: "FI", host: "net4u.de", category: .foreignInfrastructure),
        .init(id: "US.MBCOM-01", provider: "Melbicom", country: "US", host: "elecane.com", category: .foreignInfrastructure),
        .init(id: "NL.MS-01", provider: "Microsoft/Azure", country: "NL", host: "store.takeda.com", category: .foreignInfrastructure),
        .init(id: "SG.OR-01", provider: "Oracle", country: "SG", host: "ged.com.sg", category: .foreignInfrastructure),
        .init(id: "FR.OVH-01", provider: "OVH", country: "FR", host: "www.adwin.fr", category: .foreignInfrastructure),
        .init(id: "NL.SW-01", provider: "Scaleway", country: "NL", host: "www.velivole.fr", category: .foreignInfrastructure),
        .init(id: "DE.VLTR-01", provider: "Vultr", country: "DE", host: "askit-app.de", category: .foreignInfrastructure)
    ]

    // MARK: - Russian infrastructure (control group)

    static let russian: [ProbeTarget] = [
        .init(id: "RU.SLCT-01", provider: "Selectel", country: "RU", host: "selectel.ru", category: .russianInfrastructure),
        .init(id: "RU.TMWB-01", provider: "Timeweb", country: "RU", host: "timeweb.com", category: .russianInfrastructure),
        .init(id: "RU.REGRU-01", provider: "Reg.ru", country: "RU", host: "www.reg.ru", category: .russianInfrastructure),
        .init(id: "RU.BEGET-01", provider: "Beget", country: "RU", host: "beget.com", category: .russianInfrastructure),
        .init(id: "RU.YC-01", provider: "Yandex Cloud", country: "RU", host: "ya.ru", category: .russianInfrastructure),
        .init(id: "RU.VK-01", provider: "VK Cloud", country: "RU", host: "vk.ru", category: .russianInfrastructure)
    ]

    // MARK: - Web services

    static let webServices: [ProbeTarget] = [
        .init(id: "SVC.YT", provider: "YouTube", country: nil, host: "www.youtube.com", category: .webService),
        .init(id: "SVC.YT-CDN", provider: "YouTube", country: nil, host: "redirector.googlevideo.com", category: .webService),
        .init(id: "SVC.DISCORD", provider: "Discord", country: nil, host: "discord.com", category: .webService),
        .init(id: "SVC.X", provider: "X", country: nil, host: "x.com", category: .webService),
        .init(id: "SVC.TG-WEB", provider: "Telegram", country: nil, host: "web.telegram.org", category: .webService),
        .init(id: "SVC.TG-API", provider: "Telegram", country: nil, host: "api.telegram.org", category: .webService),
        .init(id: "SVC.IG", provider: "Instagram", country: nil, host: "www.instagram.com", category: .webService),
        .init(id: "SVC.WA", provider: "WhatsApp", country: nil, host: "web.whatsapp.com", category: .webService),
        .init(id: "SVC.GH", provider: "GitHub", country: nil, host: "github.com", category: .webService),
        .init(id: "SVC.GH-RAW", provider: "GitHub", country: nil, host: "raw.githubusercontent.com", category: .webService),
        .init(id: "SVC.WIKI", provider: "Wikipedia", country: nil, host: "ru.wikipedia.org", category: .webService),
        .init(id: "SVC.GOSUSLUGI", provider: "Госуслуги", country: "RU", host: "www.gosuslugi.ru", category: .webService)
    ]

    // MARK: - Push notification endpoints

    /// Users report "уведомления не приходят" constantly and almost never link it
    /// to network filtering. On iOS the APNs endpoints are the ones that matter.
    static let push: [ProbeTarget] = [
        .init(id: "PUSH.APNS", provider: "Apple APNs", country: nil, host: "api.push.apple.com", category: .pushNotification),
        .init(id: "PUSH.APNS-DEV", provider: "Apple APNs", country: nil, host: "api.development.push.apple.com", category: .pushNotification),
        .init(id: "PUSH.FCM", provider: "Google FCM", country: nil, host: "fcm.googleapis.com", category: .pushNotification),
        .init(id: "PUSH.FCM-IID", provider: "Google FCM", country: nil, host: "iid.googleapis.com", category: .pushNotification),
        .init(id: "PUSH.MTALK", provider: "Google FCM", country: nil, host: "mtalk.google.com", category: .pushNotification),
        .init(id: "PUSH.FIREBASE", provider: "Google FCM", country: nil, host: "firebaseinstallations.googleapis.com", category: .pushNotification)
    ]
}
