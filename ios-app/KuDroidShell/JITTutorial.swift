import SwiftUI
import UIKit
import Combine

@available(iOS 26.0, *)
struct JITTutorial: View {
    let method: JITMethod
    let displayName: String

    var body: some View {
        Section(header: Text("How to set up JIT")) {
            switch method {
            case .builtIn:
                if #available(iOS 27.0, *) {
                    step("1. Pair this iPhone", "Tap Pair on this iPhone below and allow Local Network access. In iOS Settings → Privacy & Security → Developer Mode, choose Pair with \(displayName), then enter the displayed code.")
                } else {
                    step("1. Import your pairing file", "On iOS 26, import a remote pairing file created for this iPhone. Keep Wi-Fi and Developer Mode enabled.")
                }
                step("2. Connect LocalDevVPN", "Install LocalDevVPN and allow it to add its VPN configuration. Connect it once. This tunnel stays on your device.")
                step("3. Enable JIT", "Tap Enable JIT. The first setup may download a Developer Disk Image and take several minutes. Wait for JIT enabled before launching an app.")
                Text("After setup, built-in JIT starts automatically when you open this app. It reuses an active tunnel; when the tunnel is off, LocalDevVPN opens to connect and return.")
                    .font(.footnote).foregroundColor(.secondary)
                step("Connect without opening LocalDevVPN", "In Shortcuts → Automation, create an App automation for when \(displayName) is opened. Choose Run Immediately and add the Start LocalDevVPN action. Keep this automation enabled so the tunnel connects before JIT starts.")
                Link("Get LocalDevVPN", destination: URL(string: "https://apps.apple.com/app/id6755608044")!)
            case .stikDebug:
                if JITEnvironment.isHosted {
                    step("Running inside LiveContainer", "Enable JIT for the LiveContainer process with StikDebug and universal.js, then return here. Built-in JIT is unavailable inside a host app.")
                }
                step("1. Set up StikDebug", "Install StikDebug, then pair this iPhone using its setup instructions. Connect LocalDevVPN if StikDebug requests it.")
                step("2. Enable JIT", "Tap Enable JIT below. This app opens StikDebug and selects universal.js automatically. Return here when activation finishes.")
                step("3. Launch your app", "Wait for JIT enabled, then launch the app you want to use. Repeat activation after closing this app from the app switcher.")
            case .wait:
                step("Attach your debugger", "Use your computer or another debugger to attach to this app. Tap Enable JIT here to check for the attachment, then wait for JIT enabled.")
            }
        }
    }

    private func step(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundColor(.secondary)
        }.padding(.vertical, 4)
    }
}

@available(iOS 26.0, *)
private struct JITStartupModifier: ViewModifier {
    var suspended = false
    @ObservedObject private var model = JITSetupModel.shared
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.showingFirstSetup, onDismiss: { if !suspended { model.applicationBecameActive() } }) {
                JITSetupView(onboarding: true).interactiveDismissDisabled()
            }
            .onAppear { if !suspended { model.applicationBecameActive() } }
            .onChange(of: phase) { if $0 == .active && !suspended { model.applicationBecameActive() } }
            .onChange(of: suspended) { if !$0 && phase == .active { model.applicationBecameActive() } }
            .onReceive(timer) { _ in if phase == .active && !suspended { model.applicationBecameActive() } }
    }
}

private struct JITMonitoringModifier: ViewModifier {
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    func body(content: Content) -> some View {
        content
            .onAppear { JITStatusModel.shared.refresh() }
            .onChange(of: phase) { if $0 == .active { JITStatusModel.shared.refresh() } }
            .onReceive(timer) { _ in if phase == .active { JITStatusModel.shared.refresh() } }
    }
}

extension View {
    @ViewBuilder func jitStartup(suspended: Bool = false) -> some View {
        if #available(iOS 26.0, *), !StandaloneConfiguration.isStandalone { modifier(JITStartupModifier(suspended: suspended)) }
        else { modifier(JITMonitoringModifier()) }
    }
}
