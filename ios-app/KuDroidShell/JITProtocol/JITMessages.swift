import Foundation
#if canImport(JITNotifications)
import JITNotifications
#endif

public enum JITHelperPhase: String, CaseIterable {
    case received, connecting, checkingImage, downloadingImage, mountingImage, verifyingImage
    case waitingForAttach, attached, preparingMemory, finishing

    public var message: String {
        switch self {
        case .received: return "JIT helper started…"
        case .connecting: return "Connecting to the developer tunnel…"
        case .checkingImage: return "Checking Developer Disk Image…"
        case .downloadingImage: return "Downloading Developer Disk Image…"
        case .mountingImage: return "Mounting Developer Disk Image…"
        case .verifyingImage: return "Verifying Developer Disk Image…"
        case .waitingForAttach: return "Attaching debugger…"
        case .attached, .preparingMemory: return "Preparing executable memory…"
        case .finishing: return "Finishing JIT activation…"
        }
    }

    public func post(identifier: String?) {
        guard let identifier, UUID(uuidString: identifier) != nil else { return }
        #if canImport(JITNotifications)
        let name = "app.jit.progress." + identifier + "." + rawValue
        name.withCString { _ = kudroid_post_jit_progress($0) }
        #endif
    }
}

public enum JITOperation: String, Codable {
    case enable, prepare, reset
}

public struct JITHelperRequest: Codable {
    public let version: Int
    public let operation: JITOperation
    public let targetPID: Int32
    public let bundleIdentifier: String
    public let pairingData: Data
    public let requiresMemoryScript: Bool
    public let progressIdentifier: String?
    public init(version: Int, operation: JITOperation, targetPID: Int32, bundleIdentifier: String, pairingData: Data,
                requiresMemoryScript: Bool = true, progressIdentifier: String? = nil) {
        self.version = version
        self.operation = operation
        self.targetPID = targetPID
        self.bundleIdentifier = bundleIdentifier
        self.pairingData = pairingData
        self.requiresMemoryScript = requiresMemoryScript
        self.progressIdentifier = progressIdentifier
    }
}

public struct JITHelperResponse: Codable {
    public let ready: Bool
    public let message: String
    public init(ready: Bool, message: String) { self.ready = ready; self.message = message }
}
