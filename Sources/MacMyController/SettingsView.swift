import MacMyControllerCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: Preferences

    @State private var launchAtLogin = LoginItem.isRegistered
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Controls") {
                slider(
                    "Pointer speed", value: $preferences.settings.pointerSpeed,
                    range: ControlSettings.speedRange)
                slider(
                    "Scroll speed", value: $preferences.settings.scrollSpeed,
                    range: ControlSettings.speedRange)
                slider(
                    "Keyboard and wheel size", value: $preferences.settings.overlayScale,
                    range: ControlSettings.scaleRange)
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { preferences.resetSettings() }
                        .disabled(preferences.settings == ControlSettings())
                }
            }

            Section("General") {
                Toggle("Open MacMyController at login", isOn: loginBinding)
                if loginStatus == .requiresApproval {
                    Text("Allow it in System Settings → General → Login Items.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }

            Section("Apps") {
                if preferences.appChoices.isEmpty {
                    Text(
                        "No saved choices. Bring an app to the front, then use the menu bar icon to choose how the controller behaves there."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(sortedApps, id: \.self) { bundleID in
                        appRow(bundleID)
                    }
                    HStack {
                        Spacer()
                        Button("Forget All") { preferences.forgetAllApps() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sortedApps: [String] {
        preferences.appChoices.keys.sorted {
            name(for: $0).localizedCaseInsensitiveCompare(name(for: $1)) == .orderedAscending
        }
    }

    private func name(for bundleID: String) -> String {
        preferences.appNames[bundleID] ?? bundleID
    }

    private func appRow(_ bundleID: String) -> some View {
        let name = name(for: bundleID)
        let choice = Binding<HandoffChoice>(
            get: { preferences.appChoices[bundleID] ?? .desktop },
            set: { preferences.setChoice($0, for: bundleID, name: name) })
        return HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: choice) {
                Text("Desktop controls").tag(HandoffChoice.desktop)
                Text("Controller goes to app").tag(HandoffChoice.native)
            }
            .labelsHidden()
            .fixedSize()
            Button("Forget") { preferences.setChoice(nil, for: bundleID, name: name) }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>)
        -> some View
    {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
            .frame(width: 260)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    try LoginItem.set(enabled)
                    loginError = nil
                } catch {
                    loginError = "Couldn't change the login item: \(error.localizedDescription)"
                }
                launchAtLogin = LoginItem.isRegistered
                loginStatus = LoginItem.status
            })
    }
}
