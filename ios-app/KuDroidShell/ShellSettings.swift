import SwiftUI
import UIKit

enum ShellAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ShellStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let inverse = Color(uiColor: .systemBackground)
    static let line = Color(uiColor: .separator).opacity(0.35)
}

struct ShellSettingsView: View {
    @AppStorage("shellAppearance") private var appearance = ShellAppearance.system.rawValue

    var body: some View {
        NavigationView {
            Form {
                AppMemorySettingsSection()
                MicroGSettingsSection()
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearance) {
                        ForEach(ShellAppearance.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }.pickerStyle(.segmented)
                }
                if #available(iOS 26.0, *) {
                    Section(header: Text("JIT")) {
                        NavigationLink("JIT setup") { JITSetupView() }
                    }
                }
                Section(header: Text("About")) {
                    HStack {
                        Label("Kudroid", systemImage: "square.stack.3d.up")
                        Spacer()
                        Text(appVersionDisplay()).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}
