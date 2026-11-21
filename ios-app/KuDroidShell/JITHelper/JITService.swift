import Foundation
import StikJIT
#if canImport(JITProtocol)
import JITProtocol
#endif

@objc(KDJITService)
@available(iOS 26.0, *)
final class JITService: NSObject, NSExtensionRequestHandling {
    private let queue = DispatchQueue(label: "jit.helper.operations", qos: .userInitiated)

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let data = item.userInfo?["request"] as? Data,
              data.count <= 1024 * 1024,
              let request = try? JSONDecoder().decode(JITHelperRequest.self, from: data),
              request.version == 1,
              request.targetPID > 0 else {
            finish(context, ready: false, message: "Invalid JIT helper request.")
            return
        }
        JITHelperPhase.received.post(identifier: request.progressIdentifier)
        NSLog("JIT helper received operation %@", request.operation.rawValue)
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard let app = Bundle(url: appURL), app.bundleIdentifier == request.bundleIdentifier else {
            finish(context, ready: false, message: "The JIT request does not match this installation.")
            return
        }
        queue.async {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                defer { try? fm.removeItem(at: work) }
                let pairing = work.appendingPathComponent("pairing.plist")
                try request.pairingData.write(to: pairing, options: [.atomic, .completeFileProtection])
                let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                let paths = DDIPaths.default(in: library.appendingPathComponent("DeveloperDiskImage"))
                switch request.operation {
                case .reset:
                    try StikJIT.resetCachedDDI(at: paths)
                    self.finish(context, ready: false, message: "Developer Disk Image cache cleared.")
                case .prepare:
                    switch StikJIT.prepareDevice(pairingFile: pairing, paths: paths,
                                                progress: { self.preparation($0, request: request) }) {
                    case .ready:
                        self.finish(context, ready: true, message: "Device ready for JIT.")
                    case .unreachable(let reason), .preparationFailed(let reason):
                        self.finish(context, ready: false, message: reason)
                    @unknown default:
                        self.finish(context, ready: false, message: "The device returned an unsupported readiness state.")
                    }
                case .enable:
                    #if SWIFT_PACKAGE
                    let resources = Bundle.module
                    #else
                    let resources = Bundle.main
                    #endif
                    guard let script = resources.url(forResource: "jit-bootstrap", withExtension: "js") else {
                        throw NSError(domain: "JITSetup", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "The JIT helper script is missing."])
                    }
                    try StikJIT.enableJIT(targetPID: request.targetPID, pairingFile: pairing,
                                         ddiPaths: paths, script: .custom(script), forceScript: request.requiresMemoryScript,
                                         preparationProgress: { self.preparation($0, request: request) },
                                         progress: { value in
                                             if value.hasPrefix("JIT_STOP:") { NSLog("JIT debugger stop %@", value); return }
                                             let phase: JITHelperPhase
                                             if value == "JIT_ATTACHED" { phase = .attached }
                                             else if value.hasPrefix("Blessed ") { phase = .preparingMemory }
                                             else if value.hasPrefix("JIT script finished") { phase = .finishing }
                                             else { phase = .waitingForAttach }
                                             phase.post(identifier: request.progressIdentifier)
                                         })
                    self.finish(context, ready: true, message: "JIT enabled.")
                }
            } catch {
                self.finish(context, ready: false, message: error.localizedDescription)
            }
        }
    }

    private func preparation(_ stage: StikJIT.PreparationStage, request: JITHelperRequest) {
        let phase: JITHelperPhase
        switch stage {
        case .checkingReachability: phase = .connecting
        case .checkingDDI: phase = .checkingImage
        case .downloadingDDI: phase = .downloadingImage
        case .mountingDDI: phase = .mountingImage
        case .verifyingDDI: phase = .verifyingImage
        case .ready: phase = .waitingForAttach
        @unknown default: return
        }
        phase.post(identifier: request.progressIdentifier)
        NSLog("JIT preparation phase %@", phase.rawValue)
    }

    private func finish(_ context: NSExtensionContext, ready: Bool, message: String) {
        let response = JITHelperResponse(ready: ready, message: message)
        guard let data = try? JSONEncoder().encode(response) else {
            context.cancelRequest(withError: NSError(domain: "JITSetup", code: 2))
            return
        }
        let item = NSExtensionItem()
        item.userInfo = ["response": data]
        DispatchQueue.main.async { context.completeRequest(returningItems: [item]) }
    }
}
