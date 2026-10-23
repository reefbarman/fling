import SwiftUI

struct TestLinkSettingsPane: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var linkText = ""
    @State private var ruleEditorInput: RuleCreationInput?
    @FocusState private var isLinkFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Test a Link",
                subtitle:
                    "Paste a link to see where Fling would send it. Nothing opens until you click Open Link."
            )

            Divider()

            Form {
                Section {
                    // A visible bordered field: the default grouped-form field is borderless and
                    // right-aligned, so it didn't read as somewhere you can type.
                    HStack(spacing: 8) {
                        TextField(
                            "Link", text: $linkText,
                            prompt: Text("https://github.com/username/repo")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($isLinkFieldFocused)
                        .onSubmit(openLink)

                        Button("Paste") {
                            if let value = NSPasteboard.general.string(forType: .string) {
                                linkText = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            isLinkFieldFocused = true
                        }
                        .help("Paste a link from the clipboard")
                    }
                }

                Section("Result") {
                    preview
                }

                Section("Last Link Fling Handled") {
                    lastHandled
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { isLinkFieldFocused = true }
        .sheet(item: $ruleEditorInput) { input in
            RuleEditorSheet(
                targets: coordinator.config.targets,
                initialInput: input,
                onSave: { updated in
                    coordinator.saveRule(updated)
                    ruleEditorInput = nil
                },
                onCancel: { ruleEditorInput = nil }
            )
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if linkText.trimmingCharacters(in: .whitespaces).isEmpty {
            resultRow(
                symbol: "link",
                title: "Paste a link above",
                detail: "You can leave off https://, for example github.com/username."
            )
        } else if let url = parsedURL {
            switch coordinator.previewRoute(for: url) {
            case .open(let target, _, let matchedRuleID):
                HStack(spacing: 12) {
                    TargetIconView(target: target)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Opens in \(target.displayName)")
                            .fontWeight(.medium)
                        Text("Matched rule: \(ruleName(for: matchedRuleID))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    openButton
                }
            case .presentSelector, .openInChromeIncognito:
                HStack(spacing: 12) {
                    resultRow(
                        symbol: "questionmark.app.dashed",
                        title: "No rule matches",
                        detail: "Fling will show the browser picker."
                    )
                    Spacer()
                    Button("Add Rule…") {
                        ruleEditorInput = RuleCreationInput(
                            url: url,
                            defaultTargetID: coordinator.config.targets.first(where: \.isEnabled)?
                                .id)
                    }
                    .disabled(coordinator.config.targets.isEmpty)
                    openButton
                }
            }
        } else {
            resultRow(
                symbol: "exclamationmark.triangle",
                title: "That doesn't look like a web link",
                detail: "Enter an http or https link."
            )
        }
    }

    private var openButton: some View {
        // Return in the link field already opens via onSubmit, so no default-button shortcut.
        Button("Open Link", action: openLink)
            .disabled(parsedURL == nil)
    }

    private func resultRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Last handled

    @ViewBuilder
    private var lastHandled: some View {
        if let decision = coordinator.lastResolvedRequest {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(description(of: decision))
                        .fontWeight(.medium)
                    Spacer()
                    Button("Test This Link") {
                        linkText = decision.url.absoluteString
                    }
                    .buttonStyle(.link)
                    Button("Clear") {
                        coordinator.clearLastDecision()
                    }
                    .buttonStyle(.link)
                }
                Text(decision.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        } else {
            Text("No links handled since Fling started.")
                .foregroundStyle(.secondary)
        }
    }

    private func description(of decision: RouteDecision) -> String {
        switch decision {
        case .open(let target, _, let matchedRuleID):
            if matchedRuleID == nil {
                return "Opened in \(target.displayName) from the browser picker"
            }
            return "Opened in \(target.displayName) by rule \(ruleName(for: matchedRuleID))"
        case .openInChromeIncognito:
            return "Opened in Chrome Incognito"
        case .presentSelector:
            return "Showed the browser picker"
        }
    }

    // MARK: - Helpers

    /// Accepts `github.com/x` as well as full links.
    private var parsedURL: URL? {
        var value = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://" + value
        }
        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            url.host(percentEncoded: false)?.isEmpty == false
        else { return nil }
        return url
    }

    private func ruleName(for ruleID: String?) -> String {
        coordinator.config.rules.first { $0.id == ruleID }?.displayName ?? "deleted rule"
    }

    private func openLink() {
        guard let url = parsedURL else { return }
        coordinator.routeTestURLString(url.absoluteString)
    }
}
