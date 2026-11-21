import Foundation

enum JITReadiness {
    static func allowsLaunch(systemMajor: Int, debuggerAttached: Bool, permanentEntitlement: Bool,
                             executableMemory: () -> Bool) -> Bool {
        if systemMajor >= 26 { return executableMemory() }
        if debuggerAttached { return true }
        return permanentEntitlement && executableMemory()
    }
}

enum JITEnvironment {
    static var isHosted: Bool { ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil }
    static func supportsBuiltIn(hosted: Bool, standaloneGuest: Bool) -> Bool {
        !hosted && !standaloneGuest
    }
}

struct JITStatus: Equatable {
    var checked = false
    var ready = false
    var debuggerConnected = false
}
