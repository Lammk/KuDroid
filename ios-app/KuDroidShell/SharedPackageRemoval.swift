import Foundation

enum SharedPackageRemoval {
    enum Failure: LocalizedError {
        case invalidPath, ownershipChanged, incomplete
        var errorDescription: String? {
            switch self {
            case .invalidPath: return "The package storage path is invalid."
            case .ownershipChanged: return "The installed package changed. Please retry."
            case .incomplete: return "Some package files could not be removed. Please retry."
            }
        }
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 255 &&
        value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-").contains($0)
        }
    }

    private static func directory(_ relative: String, root: URL) throws -> URL {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let nominal = base.appendingPathComponent(relative).standardizedFileURL
        let target = nominal.resolvingSymlinksInPath().standardizedFileURL
        guard base.path != "/", target.path == nominal.path,
              target.path.hasPrefix(base.path + "/") else { throw Failure.invalidPath }
        return target
    }

    static func ownedPackages(root: URL, identifiers: [String]) -> [String] {
        identifiers.filter { identifier in
            guard validID(identifier),
                  let code = try? directory("data/app/" + identifier, root: root) else { return false }
            return (try? String(contentsOf: code.appendingPathComponent(".kudroid-shared-service"), encoding: .utf8)) == "microg\n"
        }
    }

    static func remove(root: URL, identifiers: [String]) throws -> [String] {
        let fm = FileManager.default
        let packages = ownedPackages(root: root, identifiers: identifiers)
        var targets: [(String, [URL], URL)] = []
        for identifier in packages {
            var data = try ["data/data", "sdcard/Android/data", "sdcard/Android/obb", "sdcard/Android/media"]
                .map { try directory($0 + "/" + identifier, root: root) }
            let cache = try directory("data/dalvik-cache", root: root)
            if fm.fileExists(atPath: cache.path) {
                for entry in try fm.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) {
                    if entry.lastPathComponent == identifier || entry.lastPathComponent.hasPrefix(identifier + "_") {
                        data.append(try directory("data/dalvik-cache/" + entry.lastPathComponent, root: root))
                    }
                }
            }
            targets.append((identifier, data, try directory("data/app/" + identifier, root: root)))
        }
        for (identifier, data, code) in targets {
            guard ownedPackages(root: root, identifiers: [identifier]) == [identifier] else { throw Failure.ownershipChanged }
            for target in data where fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            // Keep ownership metadata until data cleanup succeeds.
            try fm.removeItem(at: code)
            if fm.fileExists(atPath: code.path) || data.contains(where: { fm.fileExists(atPath: $0.path) }) {
                throw Failure.incomplete
            }
        }
        return packages
    }
}
