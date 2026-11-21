import Foundation
import UIKit
import Combine
import JITSupport

final class JITStatusModel: ObservableObject {
    static let shared = JITStatusModel()
    @Published private(set) var status = JITStatus()
    private var checking = false
    private var completions: [(JITStatus) -> Void] = []
    private let worker = DispatchQueue(label: "jit.status", qos: .userInitiated)

    func refresh(completion: ((JITStatus) -> Void)? = nil) {
        if let completion { completions.append(completion) }
        guard !checking else { return }
        checking = true
        let systemMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let probeExecutableMemory: Bool
        if #available(iOS 26.0, *) { probeExecutableMemory = JITSetupModel.shared.permitsReadinessProbe }
        else { probeExecutableMemory = true }
        let knownReady = status.ready
        worker.async {
            let connected = KDJITDebuggerConnected()
            let enabled = probeExecutableMemory ? JITReadiness.allowsLaunch(systemMajor: systemMajor,
                debuggerAttached: kudroid_debugger_attached() != 0,
                permanentEntitlement: systemMajor < 26 && kudroid_has_jit_entitlement() != 0,
                executableMemory: { kudroid_is_jit_enabled() != 0 }) : knownReady
            let result = JITStatus(checked: true, ready: enabled, debuggerConnected: connected)
            DispatchQueue.main.async {
                self.checking = false
                if self.status != result { self.status = result }
                let callbacks = self.completions
                self.completions.removeAll()
                for callback in callbacks { callback(result) }
            }
        }
    }
}
