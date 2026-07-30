import Foundation

/// The curated spread of resources we ask through the proxy. Deliberately drawn
/// from unrelated operators (Cloudflare, Amazon, Google-facing, and a dozen
/// independent echo/geo services) so that a proxy exiting on more than one IP,
/// or a source disagreeing on geo/ASN, shows up instead of hiding behind a
/// single lookup.
public extension EgressResource {
    static let catalog: [EgressResource] = plainEchoes + cloudflare + geoServices

    /// Bare IP-echo endpoints — the widest net, each a different network.
    static let plainEchoes: [EgressResource] = [
        EgressResource(name: "ipify",        category: cat.echo, url: "https://api.ipify.org",       kind: .plain),
        EgressResource(name: "ifconfig.me",  category: cat.echo, url: "https://ifconfig.me/ip",      kind: .plain),
        EgressResource(name: "icanhazip",    category: cat.echo, url: "https://icanhazip.com",       kind: .plain),
        EgressResource(name: "Amazon AWS",   category: cat.echo, url: "https://checkip.amazonaws.com", kind: .plain),
        EgressResource(name: "ident.me",     category: cat.echo, url: "https://ident.me",            kind: .plain),
        EgressResource(name: "ip.sb",        category: cat.echo, url: "https://api.ip.sb/ip",        kind: .plain),
        EgressResource(name: "SeeIP",        category: cat.echo, url: "https://ip.seeip.org",        kind: .plain),
        EgressResource(name: "myexternalip", category: cat.echo, url: "https://myexternalip.com/raw", kind: .plain),
        EgressResource(name: "WTFIsMyIP",    category: cat.echo, url: "https://wtfismyip.com/text",  kind: .plain),
    ]

    /// Cloudflare's own edge view (also reveals country and the serving colo).
    static let cloudflare: [EgressResource] = [
        EgressResource(name: "Cloudflare (1.1.1.1)", category: cat.cloudflare,
                       url: "https://one.one.one.one/cdn-cgi/trace", kind: .trace),
        EgressResource(name: "Cloudflare (www)", category: cat.cloudflare,
                       url: "https://www.cloudflare.com/cdn-cgi/trace", kind: .trace),
    ]

    /// Geo/ASN services — what provider and country each attributes to the exit.
    static let geoServices: [EgressResource] = [
        EgressResource(name: "ip-api.com", category: cat.geo,
                       url: "http://ip-api.com/json/?fields=query,countryCode,country,isp,org,as",
                       kind: .json(ip: ["query"], country: ["countryCode", "country"],
                                   asn: ["as"], org: ["org", "isp"])),
        EgressResource(name: "ipinfo.io", category: cat.geo, url: "https://ipinfo.io/json",
                       kind: .json(ip: ["ip"], country: ["country"], asn: [], org: ["org"])),
        EgressResource(name: "ipwho.is", category: cat.geo, url: "https://ipwho.is/",
                       kind: .json(ip: ["ip"], country: ["country_code", "country"],
                                   asn: ["connection.asn"], org: ["connection.org", "connection.isp"])),
        EgressResource(name: "ipapi.co", category: cat.geo, url: "https://ipapi.co/json/",
                       kind: .json(ip: ["ip"], country: ["country", "country_code"],
                                   asn: ["asn"], org: ["org"])),
        EgressResource(name: "ip.sb geoip", category: cat.geo, url: "https://api.ip.sb/geoip",
                       kind: .json(ip: ["ip"], country: ["country_code", "country"],
                                   asn: ["asn"], org: ["organization", "isp"])),
        EgressResource(name: "GeoJS", category: cat.geo, url: "https://get.geojs.io/v1/ip/geo.json",
                       kind: .json(ip: ["ip"], country: ["country_code", "country"],
                                   asn: ["asn"], org: ["organization_name", "organization"])),
        EgressResource(name: "myip.com", category: cat.geo, url: "https://api.myip.com",
                       kind: .json(ip: ["ip"], country: ["cc", "country"], asn: [], org: [])),
        EgressResource(name: "FreeIPAPI", category: cat.geo, url: "https://freeipapi.com/api/json",
                       kind: .json(ip: ["ipAddress"], country: ["countryCode", "countryName"],
                                   asn: ["asn"], org: ["asnOrganization"])),
    ]

    private enum cat {
        static let echo = "IP-эхо"
        static let cloudflare = "Cloudflare"
        static let geo = "Гео и ASN"
    }
}
