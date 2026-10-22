import SwiftUI

struct TargetEditorInput {
    var id: String?
    var displayName: String
    var bundleIdentifier: String
    var applicationName: String
    var chromeProfileDirectory: String
    var isEnabled: Bool

    init(app: InstalledBrowserApp, chromeProfile: DiscoveredChromeProfile?) {
        self.id = nil
        self.displayName = chromeProfile.map { "\(app.name) \($0.profileName)" } ?? app.name
        self.bundleIdentifier = app.bundleIdentifier
        self.applicationName = app.name
        self.chromeProfileDirectory = chromeProfile?.profileDirectory ?? ""
        self.isEnabled = true
    }

    init(target: BrowserTarget) {
        self.id = target.id
        self.displayName = target.displayName
        self.bundleIdentifier = target.bundleIdentifier
        self.applicationName = target.applicationName
        self.chromeProfileDirectory = target.profile?.profileDirectory ?? ""
        self.isEnabled = target.isEnabled
    }

    func makeTarget(using chromeProfiles: [DiscoveredChromeProfile]) -> BrowserTarget {
        let profile: BrowserTarget.ChromeProfile?
        if ChromiumSupport.supportsProfiles(bundleIdentifier: bundleIdentifier)
            && !chromeProfileDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let normalizedDirectory = chromeProfileDirectory.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let profileName =
                chromeProfiles.first(where: { $0.profileDirectory == normalizedDirectory })?
                .profileName
                ?? normalizedDirectory
            profile = BrowserTarget.ChromeProfile(
                profileDirectory: normalizedDirectory,
                profileName: profileName
            )
        } else {
            profile = nil
        }

        return BrowserTarget(
            id: id ?? "target-\(UUID().uuidString.lowercased())",
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            profile: profile,
            isEnabled: isEnabled
        )
    }
}

struct TargetEditorSheet: View {
    let browserApps: [InstalledBrowserApp]
    let profileOverrides: [ChromeProfileOverride]
    let initialTarget: BrowserTarget?
    let onSave: (BrowserTarget) -> Void
    let onCancel: () -> Void

    @State private var selectedBrowserID: String
    @State private var input: TargetEditorInput
    @State private var chromeProfiles: [DiscoveredChromeProfile] = []

    init(
        browserApps: [InstalledBrowserApp],
        profileOverrides: [ChromeProfileOverride],
        initialTarget: BrowserTarget? = nil,
        onSave: @escaping (BrowserTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.browserApps = browserApps
        self.profileOverrides = profileOverrides
        self.initialTarget = initialTarget
        self.onSave = onSave
        self.onCancel = onCancel

        if let initialTarget,
            let initialApp = browserApps.first(where: {
                $0.bundleIdentifier == initialTarget.bundleIdentifier
            })
        {
            _selectedBrowserID = State(initialValue: initialApp.id)
            _input = State(initialValue: TargetEditorInput(target: initialTarget))
        } else {
            let initialApp =
                browserApps.first
                ?? InstalledBrowserApp(
                    id: "com.apple.Safari",
                    bundleIdentifier: "com.apple.Safari",
                    name: "Safari",
                    appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                    icon: NSImage()
                )
            let initialProfile =
                initialApp.supportsChromeProfiles
                ? BrowserDiscovery().chromeProfiles(
                    bundleIdentifier: initialApp.bundleIdentifier, overrides: profileOverrides
                ).first
                : nil
            _selectedBrowserID = State(initialValue: initialApp.id)
            _input = State(
                initialValue: TargetEditorInput(app: initialApp, chromeProfile: initialProfile))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Target Name", text: $input.displayName, prompt: Text("Work"))

                    Picker("Browser", selection: $selectedBrowserID) {
                        ForEach(browserApps) { app in
                            Text(app.name).tag(app.id)
                        }
                    }
                    .onChange(of: selectedBrowserID) { _, newValue in
                        guard let app = browserApps.first(where: { $0.id == newValue }) else {
                            return
                        }
                        let previousEnabled = input.isEnabled
                        let previousID = input.id
                        let previousDisplayName = input.displayName
                        input = TargetEditorInput(app: app, chromeProfile: nil)
                        input.id = previousID
                        input.isEnabled = previousEnabled
                        if !previousDisplayName.isEmpty {
                            input.displayName = previousDisplayName
                        }
                        reloadChromeProfiles()
                    }

                    if selectedApp?.supportsChromeProfiles == true {
                        HStack {
                            TextField(
                                "Profile directory", text: $input.chromeProfileDirectory,
                                prompt: Text("Default or Profile 1"))
                            if !chromeProfiles.isEmpty {
                                Menu("Choose") {
                                    ForEach(chromeProfiles) { profile in
                                        Button(
                                            "\(profile.profileName) (\(profile.profileDirectory))"
                                        ) {
                                            input.chromeProfileDirectory = profile.profileDirectory
                                        }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }

                    Toggle("Show in browser picker", isOn: $input.isEnabled)
                } header: {
                    HStack(spacing: 10) {
                        if let selectedApp {
                            Image(nsImage: selectedApp.icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                        }
                        Text(initialTarget == nil ? "Add Target" : "Edit Target")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                } footer: {
                    if selectedApp?.supportsChromeProfiles == true {
                        Text(profileHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(initialTarget == nil ? "Add Target" : "Save Changes") {
                    onSave(input.makeTarget(using: chromeProfiles))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 340)
        .onAppear(perform: reloadChromeProfiles)
    }

    private var selectedApp: InstalledBrowserApp? {
        browserApps.first(where: { $0.id == selectedBrowserID })
    }

    /// Profiles for the currently selected browser, so switching from Chrome to Brave lists
    /// Brave's profiles.
    private func reloadChromeProfiles() {
        guard let selectedApp, selectedApp.supportsChromeProfiles else {
            chromeProfiles = []
            return
        }
        chromeProfiles = BrowserDiscovery().chromeProfiles(
            bundleIdentifier: selectedApp.bundleIdentifier, overrides: profileOverrides)
    }

    private var profileHelp: String {
        if chromeProfiles.isEmpty {
            return
                "Leave empty to use the browser's last used profile. Profile folders are usually Default, Profile 1, Profile 2 and so on."
        }
        return
            "Pick a profile with Choose, or leave empty to use the browser's last used profile."
    }
}
