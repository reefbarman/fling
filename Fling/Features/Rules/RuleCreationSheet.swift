import SwiftUI

struct RuleCreationSheet: View {
    let url: URL
    let targets: [BrowserTarget]
    let onSave: (RuleCreationInput) -> Void
    let onCancel: () -> Void

    @State private var input: RuleCreationInput

    init(
        url: URL,
        targets: [BrowserTarget],
        defaultTargetID: String? = nil,
        onSave: @escaping (RuleCreationInput) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.url = url
        self.targets = targets
        self.onSave = onSave
        self.onCancel = onCancel
        _input = State(
            initialValue: RuleCreationInput(
                url: url, defaultTargetID: defaultTargetID ?? targets.first?.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create Rule")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Picker("Rule Type", selection: $input.kind) {
                ForEach(RuleCreationInput.RuleKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Picker("Open In", selection: $input.targetID) {
                ForEach(targets) { target in
                    Text(target.displayName).tag(target.id)
                }
            }

            switch input.kind {
            case .domain:
                TextField("Domain", text: $input.domain)
                Toggle("Match subdomains", isOn: $input.matchSubdomains)
                Text("Add a path (e.g. github.com/username) to only match pages under it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .urlRegex:
                TextField("Regular expression", text: $input.regexPattern)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Rule") {
                    onSave(input)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.targetID.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}
