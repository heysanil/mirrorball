import SwiftUI

/// Native Settings window (⌘,). Hosts the launch-at-login toggle and an About
/// section. Grouped form styling matches System Settings.
struct SettingsView: View {
    @Environment(Updater.self) private var updater
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var autoUpdate = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch Mirrorball at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("General")
            } footer: {
                Text("Forwards marked as enabled start automatically when Mirrorball launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Automatically check for updates", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("Mirrorball checks for new versions in the background and asks before installing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Mirrorball", value: versionString)
                Text("A native SSH port-forward manager.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            autoUpdate = updater.automaticallyChecksForUpdates
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            // Revert the toggle to the real state and explain.
            launchAtLogin = LoginItem.isEnabled
            loginError = "Couldn’t update login item: \(error.localizedDescription)"
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}
