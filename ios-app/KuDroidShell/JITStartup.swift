import Foundation

enum JITMethod: String, CaseIterable, Identifiable {
    case builtIn, stikDebug, wait
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtIn: return "Built-in JIT"
        case .stikDebug: return "StikDebug"
        case .wait: return "External debugger"
        }
    }
}

struct JITStartupPolicy {
    enum Action: Equatable { case none, setup, activate }
    private(set) var attemptedActivation = false

    mutating func next(systemMajor: Int, configured: Bool, method: JITMethod,
                       paired: Bool, active: Bool, busy: Bool, ready: Bool,
                       hosted: Bool = false, debuggerConnected: Bool = false) -> Action {
        guard systemMajor >= 26, active, !busy else { return .none }
        guard !ready, !debuggerConnected else { return .none }
        guard configured else { return .setup }
        guard !hosted else { return .none }
        guard method == .builtIn, !ready, !attemptedActivation else { return .none }
        guard paired else { return .setup }
        attemptedActivation = true
        return .activate
    }
}
