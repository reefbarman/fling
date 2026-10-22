import SwiftUI

struct RuleEditorSheet: View {
    let targets: [BrowserTarget]
    let initialInput: RuleCreationInput
    let onSave: (RuleCreationInput) -> Void
    let onCancel: () -> Void

    @State private var input: RuleCreationInput

    init(
        targets: [BrowserTarget],
        initialInput: RuleCreationInput,
        onSave: @escaping (RuleCreationInput) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.targets = targets
        self.initialInput = initialInput
        self.onSave = onSave
        self.onCancel = onCancel
        _input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Rule Name", text: $input.name, prompt: Text("Optional"))
                    Picker("Open In", selection: $input.targetID) {
                        ForEach(selectableTargets) { target in
                            Text(target.displayName).tag(target.id)
                        }
                    }
                    Toggle("Enabled", isOn: $input.isEnabled)
                } header: {
                    Text(input.existingRuleID == nil ? "Add Rule" : "Edit Rule")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }

                Section {
                    Picker("Match By", selection: $input.kind) {
                        ForEach(RuleCreationInput.RuleKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch input.kind {
                    case .domain:
                        TextField(
                            "Domain", text: $input.domain,
                            prompt: Text("example.com or github.com/username"))
                        Toggle("Match subdomains", isOn: $input.matchSubdomains)
                    case .urlRegex:
                        TextField(
                            "Pattern", text: $input.regexPattern,
                            prompt: Text("^https://example\\.com/docs")
                        )
                        .font(.body.monospaced())
                    }
                } footer: {
                    Text(matchHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Rule") { onSave(input) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 520, height: 430)
    }

    /// Enabled targets, plus the rule's current target even if it's been turned off, so the
    /// picker never shows a blank selection.
    private var selectableTargets: [BrowserTarget] {
        targets.filter { $0.isEnabled || $0.id == input.targetID }
    }

    private var matchHelp: String {
        switch input.kind {
        case .domain:
            return
                "Add a path to only match pages under it, like github.com/username. A rule with a path beats broader rules for the same site. You can paste a full link."
        case .urlRegex:
            return "Matched against the full link, including https://."
        }
    }

    private var canSave: Bool {
        guard !input.targetID.isEmpty else { return false }

        switch input.kind {
        case .domain:
            return !input.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .urlRegex:
            return !input.regexPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
