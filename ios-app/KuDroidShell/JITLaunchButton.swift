import SwiftUI

struct JITLaunchButton: View {
    let allowed: Bool
    let launch: () -> Void
    @ObservedObject private var status = JITStatusModel.shared
    @State private var showingLegacySetup = false

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                ModernJITLaunchButton(allowed: allowed, launch: launch)
            } else {
                JITLaunchControl(status: status.status, allowed: allowed, attaching: false,
                                 launch: launch, setup: { showingLegacySetup = true })
            }
        }
        .sheet(isPresented: $showingLegacySetup) { LegacyJITSetupView() }
    }
}

@available(iOS 26.0, *)
private struct ModernJITLaunchButton: View {
    let allowed: Bool
    let launch: () -> Void
    @ObservedObject private var status = JITStatusModel.shared
    @ObservedObject private var setup = JITSetupModel.shared

    var body: some View {
        JITLaunchControl(status: status.status, allowed: allowed, attaching: setup.launchBlocked,
                         launch: launch, setup: {
            if status.status.debuggerConnected { setup.activate() }
            else { setup.showSetup() }
        })
    }
}

private struct JITLaunchControl: View {
    let status: JITStatus
    let allowed: Bool
    let attaching: Bool
    let launch: () -> Void
    let setup: () -> Void

    var body: some View {
        Button {
            guard allowed, status.checked, !attaching else { return }
            if status.ready { launch() } else { setup() }
        } label: {
            HStack(spacing: 5) {
                if attaching || !status.checked {
                    ProgressView().tint(ShellStyle.inverse)
                } else if !status.ready {
                    Image(systemName: "bolt.slash.fill").foregroundColor(.red)
                }
                Text(attaching ? "JIT…" : "Open")
            }
            .font(.caption.bold())
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(ShellStyle.ink).foregroundColor(ShellStyle.inverse).cornerRadius(16)
        }
        .disabled(!allowed || attaching || !status.checked)
        .buttonStyle(.borderless)
        .accessibilityLabel(attaching ? "Enabling JIT" : status.ready ? "Open app" : "JIT required. Open setup")
    }
}

private struct LegacyJITSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var status = JITStatusModel.shared
    @State private var error: String?
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Enable JIT")) {
                    Text("Enable JIT with StikDebug or attach an external debugger, then return here. JIT must be enabled again after the app closes.")
                    Button("Open StikDebug") {
                        JITActivation.openStikDebug { opened in
                            if !opened { error = "Install StikDebug and try again." }
                        }
                    }
                    Button("TrollStore JIT") {
                        JITActivation.openTrollStore { opened in
                            if !opened { error = "Could not open TrollStore." }
                        }
                    }
                    if let error { Text(error).foregroundColor(.red) }
                }
            }
            .navigationTitle("JIT setup")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .onChange(of: status.status.ready) { if $0 { dismiss() } }
    }
}
