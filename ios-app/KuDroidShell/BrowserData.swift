import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func browserLocation(_ value: String?) -> String {
    guard let value, var url = URLComponents(string: value), let scheme = url.scheme?.lowercased() else { return "unknown" }
    guard ["http", "https"].contains(scheme), url.host != nil else { return scheme + ":" }
    url.query = nil; url.fragment = nil; url.user = nil; url.password = nil; url.path = ""
    return url.string ?? scheme + ":"
}

func browserCookieHeader(_ values: [HTTPCookie], url text: String?) -> String? {
    let url = text.flatMap(URL.init(string:))
    let host = url?.host?.lowercased() ?? ""
    let path = url?.path.isEmpty == false ? url!.path : "/"
    let matching = values.filter { cookie in
        if let expiry = cookie.expiresDate, expiry <= Date() { return false }
        if text == nil { return true }
        let domain = cookie.domain.lowercased()
        let domainMatches = domain.hasPrefix(".") ? host == String(domain.dropFirst()) || host.hasSuffix(domain) : host == domain
        let pathMatches = path == cookie.path || path.hasPrefix(cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/")
        return domainMatches && pathMatches && (!cookie.isSecure || url?.scheme?.lowercased() == "https")
    }.sorted { $0.path.count > $1.path.count }
    return matching.isEmpty ? nil : matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
}

struct BrowserCookieFile {
    private let root: String
    private let file: URL
    init(dataDirectory: String) {
        let directory = URL(fileURLWithPath: dataDirectory).standardizedFileURL
        root = directory.resolvingSymlinksInPath().path + "/"
        file = directory.appendingPathComponent("app_webview/Cookies.plist")
    }
    private func validate() throws {
        guard file.resolvingSymlinksInPath().path.hasPrefix(root),
              file.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(root) else {
            throw CocoaError(.fileReadNoPermission)
        }
    }
    func load() throws -> [HTTPCookie] {
        try validate()
        if !FileManager.default.fileExists(atPath: file.path) { return [] }
        let data = try Data(contentsOf: file)
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: String]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return values.flatMap { value -> [HTTPCookie] in
            guard let address = value["origin"], let origin = URL(string: address), let header = value["cookie"] else { return [] }
            return HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: origin)
        }
            .filter { $0.expiresDate.map { $0 > Date() } ?? true }
    }
    func save(_ cookies: [HTTPCookie]) throws {
        try validate()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let properties = try cookies.map { cookie -> [String: String] in
            var origin = URLComponents()
            origin.scheme = cookie.isSecure ? "https" : "http"
            origin.host = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            origin.path = cookie.path
            guard let address = origin.string else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
            var header = "\(cookie.name)=\(cookie.value); Path=\(cookie.path)"
            if cookie.domain.hasPrefix(".") { header += "; Domain=\(cookie.domain)" }
            if cookie.isSecure { header += "; Secure" }
            if cookie.isHTTPOnly { header += "; HttpOnly" }
            if let expiration = cookie.expiresDate { header += "; Expires=\(formatter.string(from: expiration))" }
            return ["origin": address, "cookie": header]
        }
        let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try validate()
        try data.write(to: file, options: .atomic)
        #if canImport(UIKit)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        #endif
    }
}
