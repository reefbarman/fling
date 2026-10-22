import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var isDefaultBrowser = false
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "General",
                subtitle: "Make Fling your default browser so it can route the links you click."
            )

            Divider()

            Form {
                Section("Default Browser") {
                    HStack(spacing: 10) {
                        Image(
                            systemName: isDefaultBrowser
                                ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .font(.title3)
                        .foregroundStyle(isDefaultBrowser ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                isDefaultBrowser
                                    ? "Fling is your default browser"
                                    : "Fling isn't your default browser")
                            if !isDefaultBrowser {
                                Text("Links you click won't go through your rules until it is.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !isDefaultBrowser {
                            Button("Make Default…", action: makeDefaultBrowser)
                        }
                    }
                }

                Section("Startup") {
                    Toggle("Open Fling at login", isOn: launchAtLoginBinding)
                }

                Section {
                    LabeledContent("Hold ⌥ Option") {
                        Text("Open the link in Chrome Incognito")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Hold ⇧ Shift") {
                        Text("Skip rules and pick a browser for this link")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Shortcuts")
                } footer: {
                    Text("Hold the key while clicking a link in another app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Configuration") {
                    LabeledContent("Config file") {
                        Text(coordinator.configFileDisplayPath)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button("Show in Finder") {
                            coordinator.revealConfigInFinder()
                        }
                        Button("Reload Config") {
                            coordinator.reloadConfig()
                        }
                        .help("Pick up changes made to config.json by hand")
                        Spacer()
                        Text(versionText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: refreshStatus)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshStatus()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                let manager = LaunchAtLoginManager()
                do {
                    try coordinator.persistLaunchAtLoginPreference(enabled)
                    try manager.setEnabled(enabled)
                } catch {
                    coordinator.setError(
                        "Failed to update launch at login: \(error.localizedDescription)")
                }
                launchAtLogin = manager.isEnabled()
            }
        )
    }

    private var versionText: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "?"
        return "Fling \(version)"
    }

    private func refreshStatus() {
        launchAtLogin = LaunchAtLoginManager().isEnabled()

        guard
            let probe = URL(string: "https://example.com"),
            let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else {
            isDefaultBrowser = false
            return
        }
        isDefaultBrowser = Bundle(url: handlerURL)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm the change.
    private func makeDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        Task { @MainActor in
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: appURL, toOpenURLsWithScheme: "http")
                try await NSWorkspace.shared.setDefaultApplication(
                    at: appURL, toOpenURLsWithScheme: "https")
            } catch {
                // Declining the system prompt also lands here; the status row already says so.
            }
            refreshStatus()
        }
    }
}
