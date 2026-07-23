import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// IP-literal validation shared by the app, the widget and the QR importer.
enum IPAddress {
    /// True when `value` is a valid IPv4 or IPv6 literal.
    static func isValid(_ value: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }
}
