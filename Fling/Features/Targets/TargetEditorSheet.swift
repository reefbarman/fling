import SwiftUI
import UniformTypeIdentifiers

struct TargetEditorInput {
    var id: String?
    var displayName: String
    var bundleIdentifier: String
    var applicationName: String
    var chromeProfileDirectory: String
    var pickerPlacement: BrowserTarget.PickerPlacement
    /// The saved custom icon, cleared when the user resets to the browser icon.
    var customIconFileName: String?
    /// A newly chosen icon, written to disk only when the target is saved.
    var pendingIcon: NSImage?
    var pendingIconIsCircular = false

    init(app: InstalledBrowserApp, chromeProfile: DiscoveredChromeProfile?) {
        self.id = nil
        self.displayName = chromeProfile.map { "\(app.name) \($0.profileName)" } ?? app.name
        self.bundleIdentifier = app.bundleIdentifier
        self.applicationName = app.name
        self.chromeProfileDirectory = chromeProfile?.profileDirectory ?? ""
        self.pickerPlacement = .main
        self.customIconFileName = nil
    }

    init(target: BrowserTarget) {
        self.id = target.id
        self.displayName = target.displayName
        self.bundleIdentifier = target.bundleIdentifier
        self.applicationName = target.applicationName
        self.chromeProfileDirectory = target.profile?.profileDirectory ?? ""
        self.pickerPlacement = target.pickerPlacement
        self.customIconFileName = target.customIconFileName
    }

    var hasCustomIcon: Bool {
        pendingIcon != nil || customIconFileName != nil
    }

    var previewIcon: NSImage? {
        pendingIcon ?? customIconFileName.flatMap(TargetIconStore.image(named:))
    }

    func makeTarget(using chromeProfiles: [DiscoveredChromeProfile], iconFileName: String?)
        -> BrowserTarget
    {
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

        var target = BrowserTarget(
            id: id ?? "target-\(UUID().uuidString.lowercased())",
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            profile: profile,
            isEnabled: true,
            customIconFileName: iconFileName
        )
        target.pickerPlacement = pickerPlacement
        return target
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
    @State private var profilePicture: NSImage?
    @State private var isIconDropTargeted = false
    @State private var iconError: String?

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
                        let previous = input
                        input = TargetEditorInput(app: app, chromeProfile: nil)
                        input.id = previous.id
                        input.pickerPlacement = previous.pickerPlacement
                        input.customIconFileName = previous.customIconFileName
                        input.pendingIcon = previous.pendingIcon
                        input.pendingIconIsCircular = previous.pendingIconIsCircular
                        if !previous.displayName.isEmpty {
                            input.displayName = previous.displayName
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

                    iconRow

                    Picker("In browser picker", selection: $input.pickerPlacement) {
                        ForEach(BrowserTarget.PickerPlacement.allCases) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    HStack(spacing: 10) {
                        if selectedApp != nil {
                            iconPreview.frame(width: 28, height: 28)
                        }
                        Text(initialTarget == nil ? "Add Target" : "Edit Target")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let iconError {
                            Text(iconError)
                                .foregroundStyle(.red)
                        }
                        if selectedApp?.supportsChromeProfiles == true {
                            Text(profileHelp)
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            "Under More keeps rarely used targets out of the way until you click More (or press M) in the picker."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(initialTarget == nil ? "Add Target" : "Save Changes") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 460)
        .onAppear {
            reloadChromeProfiles()
            reloadProfilePicture()
        }
        .onChange(of: input.chromeProfileDirectory) { _, _ in reloadProfilePicture() }
        .onChange(of: selectedBrowserID) { _, _ in reloadProfilePicture() }
    }

    // MARK: - Icon

    private var iconPreview: some View {
        TargetIconImage(icon: input.previewIcon, appIcon: selectedApp?.icon)
    }

    private var iconRow: some View {
        LabeledContent("Icon") {
            HStack(spacing: 10) {
                iconPreview
                    .frame(width: 36, height: 36)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isIconDropTargeted
                                    ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: isIconDropTargeted ? 2 : 1, dash: [3])
                            )
                    )
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first(where: \.isFileURL) else { return false }
                        return useIcon(from: url)
                    } isTargeted: {
                        isIconDropTargeted = $0
                    }
                    .help("Drop an image or app here")

                Button("Choose…") { chooseIcon() }

                if let profilePicture {
                    Button("Use Profile Picture") {
                        setPendingIcon(profilePicture, circular: true)
                    }
                }

                if input.hasCustomIcon {
                    Button("Reset") {
                        input.pendingIcon = nil
                        input.customIconFileName = nil
                        iconError = nil
                    }
                    .help("Go back to the browser's own icon")
                }
            }
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Icon"
        panel.message = "Pick an image (PNG, JPEG, SVG, ICNS…) or an app to borrow its icon."
        panel.allowedContentTypes = [.image, .application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useIcon(from: url)
    }

    @discardableResult
    private func useIcon(from url: URL) -> Bool {
        guard let image = TargetIconStore.loadImage(from: url) else {
            iconError = "Couldn't read an image from “\(url.lastPathComponent)”."
            return false
        }
        setPendingIcon(image, circular: false)
        return true
    }

    private func setPendingIcon(_ image: NSImage, circular: Bool) {
        input.pendingIcon = image
        input.pendingIconIsCircular = circular
        iconError = nil
    }

    private func reloadProfilePicture() {
        guard let selectedApp, selectedApp.supportsChromeProfiles else {
            profilePicture = nil
            return
        }
        profilePicture = ChromiumSupport.profilePicture(
            bundleIdentifier: selectedApp.bundleIdentifier,
            profileDirectory: input.chromeProfileDirectory.trimmingCharacters(
                in: .whitespacesAndNewlines)
        )
    }

    private func save() {
        var iconFileName = input.customIconFileName
        if let pendingIcon = input.pendingIcon {
            do {
                iconFileName = try TargetIconStore.importImage(
                    pendingIcon, circular: input.pendingIconIsCircular)
            } catch {
                iconError = "Couldn't save the icon: \(error.localizedDescription)"
                return
            }
        }
        onSave(input.makeTarget(using: chromeProfiles, iconFileName: iconFileName))
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
