import SwiftUI
import Foundation
import Combine
import UIKit
import Darwin

final class AppMemoryOnboarding: ObservableObject {
    static let shared = AppMemoryOnboarding()
    @Published var presented = false
    @Published private(set) var active = false
    let didFinish = PassthroughSubject<Void, Never>()

    func show() {
        active = true
        presented = true
    }
    func didDismiss() {
        active = false
        didFinish.send()
    }
}

enum AppMemorySettings {
    static var globalConfiguration: MemoryBudgetConfiguration {
        if StandaloneConfiguration.isStandalone {
            return MemoryBudgetConfiguration(
                enabled: Bundle.main.object(forInfoDictionaryKey: "KuDroidMemoryBudgetEnabled") as? Bool ?? false,
                percent: Bundle.main.object(forInfoDictionaryKey: "KuDroidMemoryBudgetPercent") as? Int ?? 70)
        }
        let enabled = UserDefaults.standard.object(forKey: "appMemoryBudgetEnabled") as? Bool
            ?? Bundle.main.object(forInfoDictionaryKey: "KuDroidMemoryBudgetEnabled") as? Bool ?? false
        let percent = UserDefaults.standard.object(forKey: "appMemoryBudgetPercent") as? Int
            ?? Bundle.main.object(forInfoDictionaryKey: "KuDroidMemoryBudgetPercent") as? Int ?? 70
        return MemoryBudgetConfiguration(enabled: enabled, percent: percent)
    }
    static var enabled: Bool { globalConfiguration.enabled }
    static var percent: Int { globalConfiguration.percent }
    static func configuration(for appID: String) -> MemoryBudgetConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "appMemoryBudget." + appID),
              let value = try? JSONDecoder().decode(MemoryBudgetConfiguration.self, from: data) else {
            return globalConfiguration
        }
        return MemoryBudgetConfiguration(enabled: value.enabled, percent: value.percent)
    }
    static func apply(for appID: String? = nil) {
        let value = appID.map { configuration(for: $0) } ?? globalConfiguration
        kudroid_configure_app_memory_budget(value.enabled ? 1 : 0, Int32(value.percent))
    }
    @discardableResult static func save(enabled: Bool, percent: Int) -> Bool {
        guard (0...100).contains(percent) else { return false }
        let value = MemoryBudgetConfiguration(enabled: enabled, percent: percent)
        UserDefaults.standard.set(value.enabled, forKey: "appMemoryBudgetEnabled")
        UserDefaults.standard.set(value.percent, forKey: "appMemoryBudgetPercent")
        apply()
        AppMemoryHardware.changed()
        return true
    }
    @discardableResult static func save(appID: String, enabled: Bool, percent: Int) -> Bool {
        guard (0...100).contains(percent),
              let data = try? JSONEncoder().encode(MemoryBudgetConfiguration(enabled: enabled, percent: percent)) else { return false }
        UserDefaults.standard.set(data, forKey: "appMemoryBudget." + appID)
        AppMemoryHardware.changed()
        return true
    }
    static func initializeNewApp(_ appID: String) {
        MicroGSettings.initializeNewApp(appID)
        guard UserDefaults.standard.data(forKey: "appMemoryBudget." + appID) == nil else { return }
        _ = save(appID: appID, enabled: enabled, percent: percent)
    }
    static func removeApp(_ appID: String) {
        UserDefaults.standard.removeObject(forKey: "appMemoryBudget." + appID)
        UserDefaults.standard.removeObject(forKey: "microG." + appID)
        AppMemoryHardware.changed()
    }
    static func installedIDs() -> Set<String> {
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("android_root/data/app", isDirectory: true),
              let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return Set(entries.filter { $0.hasDirectoryPath }.map { $0.lastPathComponent })
    }
}

final class AppMemoryHardware: ObservableObject {
    static let shared = AppMemoryHardware()
    @Published private(set) var hardware: UInt64 = 0
    @Published private(set) var available: UInt64 = 0
    @Published private(set) var revision = 0
    let model: String
    private init() {
        var info = utsname()
        let count = MemoryLayout.size(ofValue: info.machine)
        if uname(&info) == 0 {
            model = withUnsafePointer(to: &info.machine) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: count) { String(cString: $0) }
            }
        } else { model = UIDevice.current.model }
        refresh()
    }
    func refresh() {
        hardware = kudroid_hardware_memory_bytes()
        available = kudroid_available_app_memory_bytes()
    }
    static func changed() {
        if Thread.isMainThread { shared.revision += 1 }
        else { DispatchQueue.main.async { shared.revision += 1 } }
    }
    func estimate(_ percent: Int) -> UInt64 { MemoryBudgetPolicy.bytes(available: available, percent: percent) }
    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
    func maxLabel(_ percent: Int) -> String {
        available > 0 ? "Max: " + Self.format(estimate(percent)) : "Max: measured on launch"
    }
}

private struct MemoryHardwareAdvice: View {
    @ObservedObject private var hardware = AppMemoryHardware.shared
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(MemoryBudgetPolicy.recommendation(hardwareBytes: hardware.hardware))
            if hardware.hardware > 0 {
                Text("\(hardware.model) · \(AppMemoryHardware.format(hardware.hardware)) hardware RAM · \(AppMemoryHardware.format(hardware.available)) available")
            }
        }.font(.caption).foregroundColor(.secondary)
        .onAppear { hardware.refresh() }
        .onReceive(timer) { _ in if UIApplication.shared.applicationState == .active { hardware.refresh() } }
    }
}

private struct MemoryBudgetControls: View {
    @Binding var enabled: Bool
    @Binding var text: String
    @FocusState private var editing: Bool
    @ObservedObject private var hardware = AppMemoryHardware.shared
    private var percent: Int { MemoryBudgetValidation.parse(text).percent ?? 70 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        Toggle("Budget memory", isOn: $enabled)
            .onChange(of: enabled) { if $0 && (percent == 0 || percent == 100) { text = "70" } }
        MemoryHardwareAdvice()
        HStack {
            Text("Available memory")
            Spacer()
            if editing {
                TextField("Percent", text: $text)
                    .keyboardType(.numbersAndPunctuation).focused($editing)
                    .multilineTextAlignment(.trailing).frame(width: 80)
                    .onSubmit { editing = false }
                Text("%")
            } else {
                Button(text + "%") { editing = true }
                    .monospacedDigit().accessibilityLabel("Enter a memory percentage")
            }
        }
        Slider(value: Binding(get: { Double(min(95, max(40, percent))) }, set: { text = String(Int($0.rounded())) }), in: 40...95, step: 1)
            .disabled(!enabled).accessibilityLabel("Memory budget, recommended range 40 to 95 percent")
        if MemoryBudgetValidation.parse(text) == .invalid {
            Text("Enter a whole percentage from 0 to 100.").font(.caption).foregroundColor(.red)
        } else if percent == 0 || percent == 100 {
            Text("0% and 100% turn budgeting off.").font(.caption).foregroundColor(.secondary)
        } else if enabled && hardware.available > 0 {
            Text("Estimated budget: \(AppMemoryHardware.format(hardware.estimate(percent)))")
                .font(.caption).foregroundColor(.secondary)
        }
        }
        .onChange(of: text) { _ in if percent == 0 || percent == 100 { enabled = false } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } } }
    }
}

struct MemoryBudgetEditor: View {
    let title: String
    let backTitle: String
    let save: (Bool, Int) -> Void
    let appID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var text: String
    @State private var confirm = false
    @State private var microG = false
    @ObservedObject private var hardware = AppMemoryHardware.shared
    init(title: String, configuration: MemoryBudgetConfiguration, backTitle: String = "Cancel", appID: String? = nil, save: @escaping (Bool, Int) -> Void) {
        self.title = title; self.save = save
        self.backTitle = backTitle
        self.appID = appID
        _enabled = State(initialValue: configuration.enabled)
        _text = State(initialValue: String(configuration.percent))
        _microG = State(initialValue: appID.map { MicroGSettings.enabled(for: $0) } ?? false)
    }
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(title)) { MemoryBudgetControls(enabled: $enabled, text: $text) }
                if appID != nil {
                    Section(header: Text("microG")) {
                        Toggle("Use microG", isOn: $microG).disabled(!MicroGSettings.installed() && !microG)
                        if !MicroGSettings.installed() { Text("Install microG in Settings first.").font(.caption).foregroundColor(.secondary) }
                    }
                }
                Section { Text("Measured again when the app opens. Apps can exceed this budget. Changes apply on the next launch.").foregroundColor(.secondary) }
            }
            .navigationTitle(appID == nil ? "Max memory budget" : "Configure")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(backTitle) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { requestSave() }.disabled(MemoryBudgetValidation.parse(text) == .invalid) }
            }
            .alert("Configuration not recommended", isPresented: $confirm) {
                Button("Yes") { finish() }
                Button("No", role: .cancel) { text = "40" }
            } message: {
                Text("This configuration isn't recommended because it would currently give \(title) \(AppMemoryHardware.format(hardware.estimate(MemoryBudgetValidation.parse(text).percent ?? 40))). Are you sure?")
            }
        }.navigationViewStyle(.stack)
    }
    private func requestSave() {
        if enabled, case .confirmation = MemoryBudgetValidation.parse(text) { hardware.refresh(); confirm = true }
        else { finish() }
    }
    private func finish() {
        guard let percent = MemoryBudgetValidation.parse(text).percent else { return }
        save(enabled, percent)
        if let appID = appID { MicroGSettings.save(appID: appID, enabled: microG) }
        dismiss()
    }
}

struct AppMemorySettingsSection: View {
    @ObservedObject private var hardware = AppMemoryHardware.shared
    @State private var configure = false
    var body: some View {
        let value = AppMemorySettings.globalConfiguration
        return Section(header: Text("App memory"), footer: Text("New apps inherit this default. Hold an app to change its memory budget or turn it off. Existing per-app choices stay unchanged.")) {
            Toggle("Max memory for app", isOn: Binding(get: { AppMemorySettings.enabled }, set: { enabled in
                let percent = value.percent == 0 || value.percent == 100 ? 70 : value.percent
                AppMemorySettings.save(enabled: enabled, percent: percent)
            }))
            MemoryHardwareAdvice()
            Button("Configure default: \(value.percent)%") { configure = true }
        }
        .sheet(isPresented: $configure) {
            MemoryBudgetEditor(title: "New Android apps", configuration: AppMemorySettings.globalConfiguration) { AppMemorySettings.save(enabled: $0, percent: $1) }
        }
    }
}

struct AppMemorySetupView: View {
    let complete: () -> Void
    @State private var enabled = true
    @State private var text = String((40...95).contains(AppMemorySettings.percent) ? AppMemorySettings.percent : 70)
    @State private var confirm = false
    @ObservedObject private var hardware = AppMemoryHardware.shared
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Max memory for app")) {
                    Text("Show Android apps a share of the memory iOS makes available. This can help apps choose smaller heaps and caches.")
                    MemoryBudgetControls(enabled: $enabled, text: $text)
                }
                Section { Text("New apps inherit this default. Each app can use its own budget. Apps receive a low-memory warning near the budget, but can still exceed it.").foregroundColor(.secondary) }
                Section {
                    Button(enabled ? "Use \(text)% budget" : "Continue without budget") { requestSave() }
                        .disabled(MemoryBudgetValidation.parse(text) == .invalid)
                    Button("Leave off") { finish(enabled: false, percent: 70) }
                }
            }.navigationTitle("App memory")
            .alert("Configuration not recommended", isPresented: $confirm) {
                Button("Yes") { if let percent = MemoryBudgetValidation.parse(text).percent { finish(enabled: enabled, percent: percent) } }
                Button("No", role: .cancel) { text = "40" }
            } message: {
                Text("This configuration isn't recommended because it would currently give Android apps \(AppMemoryHardware.format(hardware.estimate(MemoryBudgetValidation.parse(text).percent ?? 40))). Are you sure?")
            }
        }.navigationViewStyle(.stack).interactiveDismissDisabled()
    }
    private func requestSave() {
        if enabled, case .confirmation = MemoryBudgetValidation.parse(text) { hardware.refresh(); confirm = true }
        else if let percent = MemoryBudgetValidation.parse(text).percent { finish(enabled: enabled, percent: percent) }
    }
    private func finish(enabled: Bool, percent: Int) {
        guard AppMemorySettings.save(enabled: enabled, percent: percent) else { return }
        UserDefaults.standard.set(true, forKey: "appMemoryBudgetSetupCompleted"); complete()
    }
}

struct AppFirstOpenSetupView: View {
    let complete: () -> Void
    @State private var memoryComplete = UserDefaults.standard.bool(forKey: "appMemoryBudgetSetupCompleted")
    @State private var microGComplete = UserDefaults.standard.bool(forKey: "microGSetupCompleted")
    var body: some View {
        if !memoryComplete { AppMemorySetupView { memoryComplete = true } }
        else if !microGComplete { MicroGSetupView { microGComplete = true; complete() } }
        else { Color.clear.onAppear(perform: complete) }
    }
}
