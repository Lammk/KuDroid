import SwiftUI
import Foundation
import CryptoKit
import Combine

struct SharedPackageCatalog: Decodable {
    let format: Int
    let packages: [Artifact]
    struct Artifact: Decodable {
        let package: String
        let name: String
        let url: URL
        let sha256: String
        let size: Int64
    }
    static func load() throws -> Self {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        guard let url = resources.url(forResource: "catalog", withExtension: "json", subdirectory: "microg") else {
            throw ExportFailure("The microG download catalog is missing.")
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.format == 1, !catalog.packages.isEmpty,
              Set(catalog.packages.map { $0.package }).count == catalog.packages.count,
              catalog.packages.allSatisfy({ InstalledAppStorage.validID($0.package) && $0.url.scheme == "https" &&
                  $0.url.host == "github.com" && $0.size > 0 && $0.sha256.count == 64 }) else {
            throw ExportFailure("Invalid microG download catalog.")
        }
        return catalog
    }
}

enum MicroGSettings {
    static var enabled: Bool {
        if StandaloneConfiguration.isStandalone {
            return Bundle.main.object(forInfoDictionaryKey: "KuDroidMicroGEnabled") as? Bool ?? false
        }
        return UserDefaults.standard.bool(forKey: "microGEnabled")
    }
    static func enabled(for appID: String) -> Bool {
        (UserDefaults.standard.object(forKey: "microG." + appID) as? Bool) ?? enabled
    }
    static func save(appID: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "microG." + appID)
        AppMemoryHardware.changed()
    }
    static func initializeNewApp(_ appID: String) {
        guard UserDefaults.standard.object(forKey: "microG." + appID) == nil else { return }
        save(appID: appID, enabled: enabled)
    }
    static func apply(for appID: String) { kudroid_configure_shared_packages(enabled(for: appID) ? 1 : 0) }
    static func root() throws -> URL {
        guard let path = kudroid_android_root_path() else { throw ExportFailure("Android storage is unavailable.") }
        defer { free(UnsafeMutablePointer(mutating: path)) }
        let value = String(cString: path)
        guard !value.isEmpty else { throw ExportFailure("Android storage is unavailable.") }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    static func installed() -> Bool {
        guard let catalog = try? SharedPackageCatalog.load(), let root = try? root() else { return false }
        return catalog.packages.allSatisfy { artifact in
            let directory = root.appendingPathComponent("data/app/" + artifact.package)
            return (try? String(contentsOf: directory.appendingPathComponent(".kudroid-shared-service"), encoding: .utf8)) == "microg\n" &&
                (try? String(contentsOf: directory.appendingPathComponent(".kudroid-artifact-sha256"), encoding: .utf8)) == artifact.sha256
        }
    }
    static func hasInstalledPackages() -> Bool {
        guard let catalog = try? SharedPackageCatalog.load(), let root = try? root() else { return false }
        return !SharedPackageRemoval.ownedPackages(root: root, identifiers: catalog.packages.map { $0.package }).isEmpty
    }
    static func disableAllApps() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "microGEnabled")
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("microG.") {
            defaults.set(false, forKey: key)
        }
        kudroid_configure_shared_packages(0)
        AppMemoryHardware.changed()
    }
}

private final class SharedPackageDownload: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let maximum: Int64
    let progress: (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var outcome: Result<URL, Error>?
    private var session: URLSession?
    private var reportedPercent = -1
    init(destination: URL, maximum: Int64, progress: @escaping (Double) -> Void) {
        self.destination = destination; self.maximum = maximum; self.progress = progress
    }
    func run(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 900
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum { downloadTask.cancel(); return }
        let fraction = min(1, Double(totalBytesWritten) / Double(maximum))
        let percent = Int(fraction * 100)
        if percent != reportedPercent { reportedPercent = percent; progress(fraction) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https" else { throw ExportFailure("The official APK download failed.") }
            try FileManager.default.moveItem(at: location, to: destination)
            outcome = .success(destination)
        } catch { outcome = .failure(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = error.map { Result<URL, Error>.failure($0) } ?? outcome ?? .failure(ExportFailure("Download incomplete."))
        let pending = continuation; continuation = nil
        session.finishTasksAndInvalidate(); self.session = nil
        pending?.resume(with: result)
    }
}

@MainActor final class MicroGInstaller: ObservableObject {
    static let shared = MicroGInstaller()
    @Published private(set) var busy = false
    @Published private(set) var stage = ""
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    func install(completion: @escaping () -> Void = {}) {
        guard Thread.isMainThread, !busy, !APKInstallModel.shared.busy else { return }
        busy = true; error = nil; stage = "Preparing microG download…"
        APKInstallModel.shared.busy = true; APKInstallModel.shared.stage = stage
        Task {
            do {
                let catalog = try SharedPackageCatalog.load()
                let root = try MicroGSettings.root()
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("SharedPackages-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }
                for artifact in catalog.packages {
                    let local = work.appendingPathComponent(artifact.package + ".apk")
                    let download = SharedPackageDownload(destination: local, maximum: artifact.size) { fraction in
                        DispatchQueue.main.async { self.report("Downloading \(artifact.name): \(Int(fraction * 100))%") }
                    }
                    _ = try await download.run(artifact.url)
                    await MainActor.run { self.report("Verifying and installing " + artifact.name + "…") }
                    try await Self.install(local, artifact: artifact, root: root)
                }
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "microGEnabled")
                    self.busy = false; APKInstallModel.shared.busy = false
                    self.stage = "microG installed"; self.revision += 1; completion()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription; self.busy = false; APKInstallModel.shared.busy = false
                    self.stage = "Installation incomplete"; self.revision += 1
                }
            }
        }
    }
    private func report(_ message: String) { stage = message; APKInstallModel.shared.stage = message }
    func remove() {
        guard !busy, !APKInstallModel.shared.busy, !AppDataResetModel.shared.busy, MicroGSettings.hasInstalledPackages() else { return }
        busy = true; error = nil
        APKInstallModel.shared.busy = true
        report("Removing microG…")
        MicroGSettings.disableAllApps()
        Task {
            do {
                let catalog = try SharedPackageCatalog.load()
                let root = try MicroGSettings.root()
                let removed = try await Self.remove(root: root, identifiers: catalog.packages.map { $0.package })
                for identifier in removed {
                    AppDataResetModel.shared.forget(identifier)
                    AppMemorySettings.removeApp(identifier)
                }
                stage = "microG removed"
                busy = false; APKInstallModel.shared.busy = false; revision += 1
            } catch {
                self.error = error.localizedDescription
                stage = "Removal incomplete"
                busy = false; APKInstallModel.shared.busy = false; revision += 1
            }
        }
    }
    nonisolated private static func remove(root: URL, identifiers: [String]) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try SharedPackageRemoval.remove(root: root, identifiers: identifiers)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    nonisolated private static func install(_ url: URL, artifact: SharedPackageCatalog.Artifact, root: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    var hash = SHA256(); var size: Int64 = 0
                    while let bytes = try file.read(upToCount: 1 << 20), !bytes.isEmpty {
                        size += Int64(bytes.count); hash.update(data: bytes)
                    }
                    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                    guard size == artifact.size, digest == artifact.sha256 else { throw ExportFailure("Official APK integrity check failed.") }
                    let log = installAPK(at: url)
                    guard log.contains("APK extracted successfully"), !log.contains("ERROR"), !log.contains("INSTALL FAILED") else {
                        throw ExportFailure(log)
                    }
                    let directory = root.appendingPathComponent("data/app/" + artifact.package)
                    let info = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("app_info.json"))) as? [String: Any]
                    guard info?["package"] as? String == artifact.package else { throw ExportFailure("Installed package identity mismatch.") }
                    try artifact.sha256.write(to: directory.appendingPathComponent(".kudroid-artifact-sha256"), atomically: true, encoding: .utf8)
                    try "microg\n".write(to: directory.appendingPathComponent(".kudroid-shared-service"), atomically: true, encoding: .utf8)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct MicroGSetupView: View {
    let complete: () -> Void
    @ObservedObject private var installer = MicroGInstaller.shared
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Install microG?")) {
                    Text("Download the official signed microG APKs and install them for Android apps. Signature spoofing is granted to the installed service packages that request it.")
                    Text("You can disable microG for each app in Configure.").font(.caption).foregroundColor(.secondary)
                }
                if installer.busy { Section { ProgressView(); Text(installer.stage) } }
                if let error = installer.error { Section { Text(error).foregroundColor(.red) } }
                Section {
                    Button(installer.error == nil ? "Yes — download and install" : "Retry download") { installer.install { finish() } }.disabled(installer.busy)
                    Button(installer.error == nil ? "No" : "Skip for now") {
                        UserDefaults.standard.set(false, forKey: "microGEnabled"); finish()
                    }.disabled(installer.busy)
                }
                Section { Text("Apache License 2.0. Licenses and notices are included. Android service compatibility is still under development.").font(.caption).foregroundColor(.secondary) }
            }.navigationTitle("microG")
        }.navigationViewStyle(.stack).interactiveDismissDisabled()
    }
    private func finish() { UserDefaults.standard.set(true, forKey: "microGSetupCompleted"); complete() }
}

struct MicroGSettingsSection: View {
    @ObservedObject private var installer = MicroGInstaller.shared
    @AppStorage("microGEnabled") private var enabled = false
    @EnvironmentObject private var session: AppSession
    @State private var confirmRemoval = false
    var body: some View {
        Section(header: Text("microG"), footer: Text("New apps inherit this default. Hold an app and choose Configure to change it. Changes apply on the next launch.")) {
            Toggle("Use microG for new apps", isOn: $enabled).disabled(!MicroGSettings.installed() && !enabled)
            Button(MicroGSettings.installed() ? "Reinstall official microG" : "Download and install microG") { installer.install() }
                .disabled(installer.busy || session.libraryBusy || !session.activeGuestApp.isEmpty || session.isSoRunning)
            if MicroGSettings.hasInstalledPackages() {
                Button("Remove microG", role: .destructive) { confirmRemoval = true }
                    .disabled(installer.busy || session.libraryBusy || AppDataResetModel.shared.busy || !session.activeGuestApp.isEmpty || session.isSoRunning)
            }
            if !installer.stage.isEmpty { Text(installer.stage).font(.caption) }
            if let error = installer.error { Text(error).font(.caption).foregroundColor(.red) }
        }
        .alert("Remove microG?", isPresented: $confirmRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                guard !session.libraryBusy, session.activeGuestApp.isEmpty, !session.isSoRunning else { return }
                installer.remove()
            }
        } message: {
            Text("This removes the shared microG packages, accounts and service data, and turns microG off for all apps. Your other apps and their data stay installed.")
        }
    }
}
