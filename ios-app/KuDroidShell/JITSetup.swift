import Foundation
import SwiftUI
import UIKit
import BackgroundTasks
import UniformTypeIdentifiers
import Network
import Combine
import JITSupport
#if canImport(JITProtocol)
import JITProtocol
#endif

@available(iOS 26.0, *)
final class JITSetupModel: NSObject, ObservableObject, NetServiceDelegate {
    static let shared = JITSetupModel()
    @Published var method: JITMethod = JITMethod(rawValue: UserDefaults.standard.string(forKey: "jitMethod") ?? "") ?? .stikDebug {
        didSet {
            if method == .builtIn && !canUseBuiltIn { method = .stikDebug }
            UserDefaults.standard.set(method.rawValue, forKey: "jitMethod")
        }
    }
    @Published private(set) var busy = false
    @Published private(set) var pairing = false
    @Published private(set) var pin: String?
    @Published private(set) var message = "Choose a JIT method."
    @Published private(set) var error: String?
    @Published private(set) var paired = false
    @Published private(set) var ready = false
    @Published private(set) var hasCompletedSetup = UserDefaults.standard.bool(forKey: "jitSetupCompleted")
    @Published var showingFirstSetup = false
    @Published private(set) var notificationsEnabled = true
    private var nativePairing: OpaquePointer?
    private var service: NetService?
    private var timer: Timer?
    private var helper: KDJITExtensionSession?
    private var timeout: DispatchWorkItem?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var continuedTask: BGContinuedProcessingTask?
    private var backgroundRegistered = false
    private var generation = UUID()
    private var pendingVPN = false
    private var startup = JITStartupPolicy()
    private var connection: NWConnection?
    private var readinessTimer: Timer?
    private var checkingReadiness = false
    private var lastHelperPhase: JITHelperPhase?
    private var statusSubscription: AnyCancellable?

    private var pairingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JIT/pairing.plist")
    }
    private var backgroundIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.kudroid.shell") + ".pairing.session"
    }
    var canUseBuiltIn: Bool {
        JITEnvironment.supportsBuiltIn(hosted: JITEnvironment.isHosted,
                                      standaloneGuest: StandaloneConfiguration.isStandalone)
    }
    var launchBlocked: Bool { method == .builtIn && busy && !pairing }
    var permitsReadinessProbe: Bool {
        helper == nil || ready || lastHelperPhase == .attached ||
            lastHelperPhase == .preparingMemory || lastHelperPhase == .finishing
    }
    var availableMethods: [JITMethod] { JITMethod.allCases.filter { $0 != .builtIn || canUseBuiltIn } }
    var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "JIT Host"
    }
    private var callbackScheme: String? {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.first(where: { $0["CFBundleURLName"] as? String == "JIT Setup" })
            .flatMap { ($0["CFBundleURLSchemes"] as? [String])?.first }
    }

    private override init() {
        super.init()
        if !canUseBuiltIn && method == .builtIn { method = .stikDebug }
        PairingNotifications.shared.clear()
        refreshPairing()
        statusSubscription = JITStatusModel.shared.$status.sink { [weak self] status in
            guard let self, status.checked else { return }
            self.ready = status.ready
            if status.ready {
                self.error = nil
                self.message = "JIT is enabled for this session."
                self.showingFirstSetup = false
            } else if status.debuggerConnected && self.helper == nil {
                self.showingFirstSetup = false
            }
        }
    }

    func applicationBecameActive() {
        JITStatusModel.shared.refresh { [weak self] status in
            guard let self, UIApplication.shared.applicationState == .active else { return }
            if self.pendingVPN { self.resumeAfterVPN(); return }
            guard !self.showingFirstSetup else { return }
            self.refreshPairing()
            switch self.startup.next(systemMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                                    configured: self.hasCompletedSetup, method: self.method, paired: self.paired,
                                    active: true, busy: self.busy, ready: status.ready,
                                    hosted: !self.canUseBuiltIn, debuggerConnected: status.debuggerConnected) {
            case .none: break
            case .setup: self.showingFirstSetup = true
            case .activate: self.activate()
            }
        }
    }

    func showSetup() {
        guard !ready, !JITStatusModel.shared.status.debuggerConnected, !launchBlocked else { return }
        showingFirstSetup = true
    }

    func completeSetup(skip: Bool = false) {
        if skip { method = .wait }
        UserDefaults.standard.set(true, forKey: "jitSetupCompleted")
        hasCompletedSetup = true
        showingFirstSetup = false
        applicationBecameActive()
    }

    func registerBackgroundPairing() {
        guard canUseBuiltIn, !backgroundRegistered else { return }
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard identifiers.contains(backgroundIdentifier) else { return }
        backgroundRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundIdentifier, using: .main) { [weak self] task in
            guard let self, let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            guard self.pairing else { continued.setTaskCompleted(success: false); return }
            self.continuedTask = continued
            continued.progress.totalUnitCount = 100
            continued.progress.completedUnitCount = 10
            continued.expirationHandler = { [weak self] in
                DispatchQueue.main.async { self?.cancelPairing(reason: "Background pairing ended. Start pairing again.") }
            }
            self.updatePairingBanner()
        }
    }

    func refreshPairing() {
        paired = (try? Data(contentsOf: pairingURL)).flatMap { try? Self.validatePairing($0) } != nil
    }

    private static func validatePairing(_ data: Data) throws -> Data {
        guard data.count <= 1024 * 1024,
              let record = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let publicKey = record["public_key"] as? Data, publicKey.count == 32,
              let privateKey = record["private_key"] as? Data, privateKey.count == 32,
              let identifier = record["identifier"] as? String, !identifier.isEmpty else {
            throw NSError(domain: "JITSetup", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Import a remote pairing file created for on-device JIT."])
        }
        return data
    }

    private func savePairing(_ data: Data) throws {
        let checked = try Self.validatePairing(data)
        var directory = pairingURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try checked.write(to: pairingURL, options: [.atomic, .completeFileProtection])
        paired = true
        method = .builtIn
    }

    func importPairing(_ url: URL) {
        guard canUseBuiltIn, !busy else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try savePairing(Data(contentsOf: url))
            error = nil
            message = "Pairing file imported. Connect LocalDevVPN, then enable JIT."
        } catch { self.error = error.localizedDescription }
    }

    func startPairing() {
        guard #available(iOS 27.0, *), canUseBuiltIn, !busy else { return }
        generation = UUID()
        let token = generation
        busy = true
        error = nil
        message = "Preparing pairing notifications…"
        PairingNotifications.shared.clear()
        PairingNotifications.shared.requestPermission { [weak self] allowed in
            guard let self, self.generation == token else { return }
            self.notificationsEnabled = allowed
            self.busy = false
            self.startPairingListener()
        }
    }

    private func startPairingListener() {
        guard #available(iOS 27.0, *), !busy else { return }
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        var failure: UnsafeMutablePointer<CChar>?
        let handle = displayName.withCString { name in
            identifier.withCString { host in kudroid_pairing_start(name, host, &failure) }
        }
        guard let handle else {
            error = failure.map { String(cString: $0) } ?? "Could not open the pairing listener."
            kudroid_pairing_string_free(failure)
            return
        }
        nativePairing = handle
        do {
            guard let description = kudroid_pairing_description(handle),
                  let data = String(cString: description).data(using: .utf8),
                  let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let port = info["port"] as? Int,
                  let name = info["identifier"] as? String,
                  let txt = info["txt"] as? [String: String] else {
                throw NSError(domain: "JITSetup", code: 2)
            }
            let publication = NetService(domain: "local.", type: "_remotepairing-pairable-host._tcp.", name: name, port: Int32(port))
            guard publication.setTXTRecord(NetService.data(fromTXTRecord: txt.mapValues { Data($0.utf8) })) else {
                throw NSError(domain: "JITSetup", code: 3)
            }
            busy = true
            pairing = true
            error = nil
            pin = nil
            message = "In Settings → Privacy & Security → Developer Mode, choose Pair with " + displayName + "."
            service = publication
            publication.delegate = self
            publication.publish()
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Device pairing") { [weak self] in
                self?.cancelPairing(reason: "Pairing expired in the background. Start again when Settings is ready.")
            }
            if backgroundRegistered {
                let request = BGContinuedProcessingTaskRequest(identifier: backgroundIdentifier,
                    title: "Pair with " + displayName, subtitle: "Waiting for Settings")
                request.strategy = .fail
                try? BGTaskScheduler.shared.submit(request)
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.pollPairing() }
        } catch {
            stopPairing(success: false)
            self.error = error.localizedDescription
        }
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        guard sender === service else { return }
        cancelPairing(reason: "Could not advertise pairing. Allow Local Network access and connect to Wi-Fi.")
    }

    private func pollPairing() {
        guard let handle = nativePairing else { return }
        while let value = kudroid_pairing_poll(handle) {
            let text = String(cString: value)
            kudroid_pairing_string_free(value)
            guard let data = text.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "pin":
                let code = event["value"] as? String
                if let code, code != pin { PairingNotifications.shared.show(code: code, name: displayName) }
                pin = code
                message = "Enter this code in Settings."
                updatePairingBanner()
            case "retry":
                pin = nil
                PairingNotifications.shared.clear()
                message = event["value"] as? String ?? "Select this host again in Settings."
                updatePairingBanner()
            case "paired":
                do {
                    guard let encoded = event["record"] as? String, let bytes = Data(base64Encoded: encoded) else {
                        throw NSError(domain: "JITSetup", code: 4)
                    }
                    try savePairing(bytes)
                    stopPairing(success: true)
                    message = "Paired. Connect LocalDevVPN, then enable JIT."
                } catch { cancelPairing(reason: error.localizedDescription) }
                return
            case "error":
                cancelPairing(reason: event["value"] as? String ?? "Pairing failed.")
                return
            default: break
            }
        }
    }

    private func updatePairingBanner() {
        continuedTask?.progress.completedUnitCount = pin == nil ? 10 : 50
        continuedTask?.updateTitle("Pair with " + displayName, subtitle: pin.map { "Pairing code: " + $0 } ?? "Waiting for Settings")
    }

    private func stopPairing(success: Bool) {
        PairingNotifications.shared.clear()
        timer?.invalidate(); timer = nil
        service?.stop(); service = nil
        if let handle = nativePairing { kudroid_pairing_stop(handle); nativePairing = nil }
        if let task = continuedTask {
            if success { task.progress.completedUnitCount = 100 }
            task.setTaskCompleted(success: success)
            continuedTask = nil
        }
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundIdentifier)
        busy = false
        pairing = false
        pin = nil
    }

    func cancelPairing(reason: String? = nil) {
        stopPairing(success: false)
        error = reason
        message = reason == nil ? "Pairing cancelled." : "Start pairing again when you are ready."
    }

    func openVPN() {
        guard canUseBuiltIn, !busy else { return }
        guard let scheme = callbackScheme else { error = "This installation is missing its JIT return URL."; return }
        var url = URLComponents()
        url.scheme = "localdevvpn"
        url.host = "enable"
        url.queryItems = [URLQueryItem(name: "scheme", value: scheme)]
        guard let request = url.url else { return }
        generation = UUID()
        let token = generation
        pendingVPN = true
        busy = true
        error = nil
        message = "Connecting LocalDevVPN. Return here after it connects."
        scheduleTimeout(seconds: 90, token: token, message: "Return from LocalDevVPN after connecting, then tap Enable JIT to retry.")
        UIApplication.shared.open(request, options: [:]) { [weak self] opened in
            guard let self, self.generation == token, self.pendingVPN else { return }
            if !opened {
                self.cancelHelper()
                self.error = "Install LocalDevVPN to connect the local developer tunnel."
            }
        }
    }

    func handleURL(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme else { return false }
        if pendingVPN { resumeAfterVPN() }
        return true
    }

    private func resumeAfterVPN() {
        guard pendingVPN else { return }
        pendingVPN = false
        timeout?.cancel(); timeout = nil
        busy = false
        if method == .builtIn { checkTunnel(openIfNeeded: false) }
    }

    func activate() {
        guard !busy else { return }
        generation = UUID()
        let token = generation
        busy = true
        error = nil
        message = "Checking JIT…"
        JITStatusModel.shared.refresh { [weak self] status in
            guard let self, self.generation == token else { return }
            self.busy = false
            if status.ready { self.message = "JIT is enabled for this session."; return }
            if status.debuggerConnected { self.waitForDebugger(); return }
            self.beginActivation()
        }
    }

    private func waitForDebugger() {
        generation = UUID()
        busy = true
        message = "A debugger is already attached. Waiting for JIT preparation."
        monitorReadiness(token: generation)
        scheduleTimeout(seconds: 180, token: generation, message: "The attached debugger has not prepared JIT. Finish its setup, then retry.")
    }

    private func beginActivation() {
        guard KDJITCanDebug() else {
            error = "This installation needs get-task-allow. Sign it for development and preserve app extensions."
            return
        }
        switch method {
        case .builtIn:
            guard canUseBuiltIn else { error = "Use the host app or StikDebug to enable JIT."; return }
            guard paired else { error = "Pair this device or import its pairing file first."; return }
            checkTunnel(openIfNeeded: true)
        case .stikDebug:
            generation = UUID()
            let token = generation
            busy = true
            message = "Waiting for StikDebug."
            JITActivation.openStikDebug { [weak self] opened in
                guard let self, self.generation == token else { return }
                if !opened { self.cancelHelper(); self.error = "Install StikDebug to use this JIT method." }
            }
            monitorReadiness(token: token)
            scheduleTimeout(seconds: 180, token: token, message: "JIT is not ready. Return after enabling it in StikDebug, or retry.")
        case .wait:
            generation = UUID()
            busy = true
            message = "Waiting for an external debugger."
            monitorReadiness(token: generation)
            scheduleTimeout(seconds: 180, token: generation, message: "No debugger attached. Attach your debugger and retry.")
        }
    }

    private func checkTunnel(openIfNeeded: Bool) {
        guard !busy else { return }
        generation = UUID()
        let token = generation
        busy = true
        message = "Checking the developer connection…"
        let probe = NWConnection(host: "10.7.0.1", port: 49152, using: .tcp)
        connection = probe
        probe.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.finishTunnelCheck(token: token, connected: true, openIfNeeded: openIfNeeded)
            case .failed: self?.finishTunnelCheck(token: token, connected: false, openIfNeeded: openIfNeeded)
            default: break
            }
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.finishTunnelCheck(token: token, connected: false, openIfNeeded: openIfNeeded)
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
        probe.start(queue: .main)
    }

    private func finishTunnelCheck(token: UUID, connected: Bool, openIfNeeded: Bool) {
        guard generation == token, connection != nil else { return }
        timeout?.cancel(); timeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        busy = false
        if connected { requestHelper(.enable) }
        else if openIfNeeded { openVPN() }
        else { error = "The developer tunnel is not reachable. Connect LocalDevVPN, return here, and tap Enable JIT to retry." }
    }

    private func monitorReadiness(token: UUID) {
        readinessTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.generation == token, !self.checkingReadiness else { return }
            self.checkingReadiness = true
            JITStatusModel.shared.refresh { [weak self] status in
                guard let self else { return }
                self.checkingReadiness = false
                guard self.generation == token, status.ready else { return }
                self.ready = true
                self.message = "JIT is enabled for this session."
                self.readinessTimer?.invalidate(); self.readinessTimer = nil
                if self.helper == nil { self.busy = false; self.timeout?.cancel(); self.timeout = nil }
            }
        }
        readinessTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleTimeout(seconds: TimeInterval, token: UUID, message: String) {
        timeout?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.busy else { return }
            self.cancelHelper()
            self.error = message
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: deadline)
    }

    func prepare() { requestHelper(.prepare) }
    func resetDDI() { requestHelper(.reset) }

    private func requestHelper(_ operation: JITOperation) {
        guard !busy else { return }
        guard canUseBuiltIn else { error = "Built-in JIT needs a standalone installation with its helper extension."; return }
        if operation != .enable { beginHelper(operation); return }
        generation = UUID()
        let token = generation
        busy = true
        message = "Checking JIT…"
        JITStatusModel.shared.refresh { [weak self] status in
            guard let self, self.generation == token else { return }
            self.busy = false
            if status.ready { self.message = "JIT is enabled for this session."; return }
            if status.debuggerConnected { self.waitForDebugger(); return }
            self.beginHelper(operation)
        }
    }

    private func beginHelper(_ operation: JITOperation) {
        guard KDJITCanDebug() else { error = "Sign this app for development with get-task-allow."; return }
        do {
            let data = try Self.validatePairing(Data(contentsOf: pairingURL))
            let plugin = Bundle.main.bundleURL.appendingPathComponent("PlugIns/KuDroidJITHelper.appex")
            guard let bundle = Bundle(url: plugin), let identifier = bundle.bundleIdentifier,
                  let host = Bundle.main.bundleIdentifier else {
                throw NSError(domain: "JITSetup", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "The JIT helper is missing. Reinstall with app extensions preserved."])
            }
            let request = JITHelperRequest(version: 1, operation: operation, targetPID: getpid(),
                                           bundleIdentifier: host, pairingData: data,
                                           requiresMemoryScript: KDJITNeedsMemoryScript(),
                                           progressIdentifier: UUID().uuidString)
            let encoded = try JSONEncoder().encode(request)
            generation = UUID()
            let token = generation
            busy = true
            error = nil
            lastHelperPhase = nil
            message = operation == .reset ? "Clearing Developer Disk Image cache…" : "Preparing device for JIT…"
            helper = KDJITExtensionSession.start(withIdentifier: identifier, payload: encoded, started: {}, progress: { [weak self] value in
                guard let self, self.generation == token, let phase = JITHelperPhase(rawValue: value) else { return }
                guard self.lastHelperPhase != phase else { return }
                self.lastHelperPhase = phase
                self.message = phase.message
                IOSDiagnostics.shared.applicationPhase("jit-helper-" + phase.rawValue)
                if operation == .enable && phase == .attached && self.readinessTimer == nil {
                    self.monitorReadiness(token: token)
                }
            }) { [weak self] reply, failure in
                guard let self, self.generation == token else { return }
                self.timeout?.cancel(); self.timeout = nil
                self.busy = false
                self.helper = nil
                if let failure {
                    self.readinessTimer?.invalidate(); self.readinessTimer = nil
                    if !self.ready { self.error = failure.localizedDescription + " Tap Enable JIT to retry." }
                    return
                }
                guard let reply, let response = try? JSONDecoder().decode(JITHelperResponse.self, from: reply) else {
                    self.readinessTimer?.invalidate(); self.readinessTimer = nil
                    self.error = "The JIT helper returned no result."
                    return
                }
                self.message = self.ready ? "JIT is enabled for this session." : response.message
                if !response.ready && operation != .reset && !self.ready {
                    self.message = "JIT activation failed."
                    self.error = response.message
                }
                if operation != .enable || !response.ready {
                    self.readinessTimer?.invalidate(); self.readinessTimer = nil
                } else if !self.ready {
                    self.busy = true
                    self.message = "Verifying JIT…"
                    self.monitorReadiness(token: token)
                    self.scheduleTimeout(seconds: 15, token: token, message: "JIT did not become ready. Tap Enable JIT to retry.")
                }
            }
            scheduleTimeout(seconds: 900, token: token, message: "JIT setup timed out. Check LocalDevVPN and the pairing file, then retry.")
        } catch {
            self.error = error.localizedDescription
            if !FileManager.default.fileExists(atPath: pairingURL.path) { self.error = "Pair this device or import its pairing file first." }
        }
    }

    func cancelHelper() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        helper?.cancel(); helper = nil
        readinessTimer?.invalidate(); readinessTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        pendingVPN = false
        busy = false
    }
}

@available(iOS 26.0, *)
struct JITSetupView: View {
    var onboarding = false
    @ObservedObject private var model = JITSetupModel.shared
    @State private var importing = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            Form {
                if onboarding {
                    Section {
                        Text("Choose how \(model.displayName) enables JIT. Your choice is saved for this installation, and you can change it later in Settings.")
                    }
                }
                Section(header: Text("JIT method")) {
                    Picker("Method", selection: $model.method) {
                        ForEach(model.availableMethods) { method in Text(method.title).tag(method) }
                    }.disabled(model.busy)
                    if JITEnvironment.isHosted {
                        Label("Running inside LiveContainer", systemImage: "shippingbox")
                        Text("Enable JIT for LiveContainer with StikDebug. Built-in JIT is unavailable here.").foregroundColor(.secondary)
                    } else if StandaloneConfiguration.isStandalone {
                        Text("Use StikDebug or attach an external debugger to enable JIT.").foregroundColor(.secondary)
                    }
                }
                JITTutorial(method: model.method, displayName: model.displayName)
                if model.method == .builtIn {
                    Section(header: Text("Pair this device"), footer: Text("Keep Wi-Fi and Developer Mode enabled. This pairing file works only with the device that created it.")) {
                        Label(model.paired ? "Pairing file ready" : "Not paired", systemImage: model.paired ? "checkmark.circle" : "link")
                        if !model.notificationsEnabled {
                            Text("Enable notifications for this app in iOS Settings to see the pairing code while Settings is open.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if #available(iOS 27.0, *) {
                            Button(model.paired ? "Pair again on this iPhone" : "Pair on this iPhone") { model.startPairing() }
                                .disabled(model.busy)
                        } else {
                            Text("On-device pairing is available in iOS 27. On iOS 26, import a remote pairing file.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Button("Import pairing file") { importing = true }.disabled(model.busy)
                        if let pin = model.pin {
                            Text(pin).font(.largeTitle.monospaced().bold()).textSelection(.enabled)
                            Text("Enter this code in Settings → Privacy & Security → Developer Mode → Pair with " + model.displayName + ".")
                        }
                        if model.pairing { Button("Cancel pairing", role: .cancel) { model.cancelPairing() } }
                    }
                    Section(header: Text("Developer connection")) {
                        Button("Connect LocalDevVPN") { model.openVPN() }.disabled(model.busy)
                        Button("Check device setup") { model.prepare() }.disabled(model.busy || !model.paired)
                        Button("Reset Developer Disk Image", role: .destructive) { model.resetDDI() }.disabled(model.busy || !model.paired)
                    }
                }
                Section {
                    if model.ready { Label("JIT enabled", systemImage: "checkmark.circle.fill").foregroundColor(.green) }
                    if model.busy { ProgressView(model.message) } else { Text(model.message) }
                    if let error = model.error { Text(error).foregroundColor(.red) }
                    Button("Enable JIT") { model.activate() }.disabled(model.busy)
                    if model.busy && !model.pairing { Button("Cancel", role: .cancel) { model.cancelHelper() } }
                }
                if onboarding {
                    Section {
                        Button("Save and continue") { model.completeSetup() }
                            .disabled(model.busy || (model.method == .builtIn && !model.paired))
                        Button("Set up later") { model.completeSetup(skip: true) }.disabled(model.busy)
                    }
                }
            }
            .navigationTitle("JIT setup")
            .toolbar {
                if !onboarding { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
        .navigationViewStyle(.stack)
        .documentPicker(isPresented: $importing, types: [.propertyList, .data]) { result in
            if case .success(let url) = result { model.importPairing(url) }
        }
        .onAppear { model.refreshPairing() }
    }
}
