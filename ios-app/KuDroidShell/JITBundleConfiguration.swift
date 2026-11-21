import Foundation

enum JITBundleConfiguration {
    static func configure(_ info: inout [String: Any], identifier: String) {
        var types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        types.removeAll { $0["CFBundleURLName"] as? String == "JIT Setup" }
        types.append(["CFBundleURLName": "JIT Setup", "CFBundleURLSchemes":
            ["kudroid-jit-" + identifier.replacingOccurrences(of: ".", with: "-").lowercased()]])
        info["CFBundleURLTypes"] = types
        var schemes = Set(info["LSApplicationQueriesSchemes"] as? [String] ?? [])
        schemes.formUnion(["localdevvpn", "stikdebug", "apple-magnifier"])
        info["LSApplicationQueriesSchemes"] = schemes.sorted()
        var services = Set(info["NSBonjourServices"] as? [String] ?? [])
        services.insert("_remotepairing-pairable-host._tcp")
        info["NSBonjourServices"] = services.sorted()
        info["BGTaskSchedulerPermittedIdentifiers"] = [identifier + ".pairing.session"]
    }

    static func rewriteHelper(in app: URL, identifier: String) throws {
        let plugin = app.appendingPathComponent("PlugIns/KuDroidJITHelper.appex")
        let file = plugin.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        info["CFBundleIdentifier"] = identifier + ".JITHelper"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: file, options: .atomic)
        for name in ["_CodeSignature", "embedded.mobileprovision"] {
            let path = plugin.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
    }
}
