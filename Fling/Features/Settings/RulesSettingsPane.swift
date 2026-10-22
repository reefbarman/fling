import SwiftUI

struct RulesSettingsPane: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var searchText = ""
    @State private var selection = Set<String>()
    @State private var editorInput: RuleCreationInput?
    @State private var pendingDeletion: Set<String> = []
    @State private var isConfirmingDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Rules",
                subtitle:
                    "Links are checked from top to bottom and the first match wins. Rules limited to a path, like github.com/username, beat broader ones. Drag to reorder."
            ) {
                if !rules.isEmpty {
                    SettingsSearchField(prompt: "Filter rules", text: $searchText)
                }
                Button {
                    addRule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .disabled(coordinator.config.targets.isEmpty)
            }

            Divider()

            content
        }
        .sheet(item: $editorInput) { input in
            RuleEditorSheet(
                targets: coordinator.config.targets,
                initialInput: input,
                onSave: { updated in
                    coordinator.saveRule(updated)
                    editorInput = nil
                },
                onCancel: { editorInput = nil }
            )
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: $isConfirmingDeletion,
            presenting: pendingDeletion
        ) { ids in
            Button("Delete", role: .destructive) {
                coordinator.deleteRules(ids: ids)
                selection.subtract(ids)
            }
        } message: { _ in
            Text(
                "Links these rules matched will go to the next matching rule, or the browser picker."
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if rules.isEmpty {
            ContentUnavailableView {
                Label("No Rules Yet", systemImage: "list.bullet.rectangle")
            } description: {
                Text(
                    "Without rules, every link shows the browser picker. Add a rule here, or use \"Add Rule\" in the picker the next time a link opens."
                )
            } actions: {
                Button("Add Rule") { addRule() }
                    .disabled(coordinator.config.targets.isEmpty)
            }
        } else if filteredRules.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(selection: $selection) {
                ForEach(filteredRules, id: \.id) { rule in
                    RuleRow(
                        rule: rule,
                        position: position(of: rule),
                        target: target(for: rule),
                        onToggle: { setEnabled($0, for: rule) },
                        onEdit: { edit(rule) },
                        onDelete: { confirmDeletion(of: [rule.id]) }
                    )
                    .tag(rule.id)
                }
                .onMove(perform: isFiltering ? nil : moveRules)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: String.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if ids.count == 1, let rule = rule(id: ids.first) {
                    edit(rule)
                }
            }
            .onDeleteCommand {
                confirmDeletion(of: selection)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        if ids.count == 1, let rule = rule(id: ids.first) {
            Button("Edit…") { edit(rule) }
            Button(rule.isEnabled ? "Turn Off" : "Turn On") {
                setEnabled(!rule.isEnabled, for: rule)
            }
            Divider()
        }
        if !ids.isEmpty {
            Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Rules", role: .destructive) {
                confirmDeletion(of: ids)
            }
        }
    }

    // MARK: - Data

    private var rules: [Rule] { coordinator.config.rules }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredRules: [Rule] {
        guard isFiltering else { return rules }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return rules.filter { rule in
            var haystack = [rule.displayName, target(for: rule)?.displayName ?? ""]
            switch rule {
            case .domain(let domainRule): haystack.append(domainRule.domain)
            case .urlRegex(let regexRule): haystack.append(regexRule.pattern)
            }
            return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var deletionTitle: String {
        if pendingDeletion.count == 1, let rule = rule(id: pendingDeletion.first) {
            return "Delete “\(rule.displayName)”?"
        }
        return "Delete \(pendingDeletion.count) rules?"
    }

    private func rule(id: String?) -> Rule? {
        rules.first { $0.id == id }
    }

    private func position(of rule: Rule) -> Int {
        (rules.firstIndex { $0.id == rule.id } ?? 0) + 1
    }

    private func target(for rule: Rule) -> BrowserTarget? {
        coordinator.config.targets.first { $0.id == rule.targetId }
    }

    // MARK: - Actions

    private func addRule() {
        editorInput = .blank(
            defaultTargetID: coordinator.config.targets.first(where: \.isEnabled)?.id)
    }

    private func edit(_ rule: Rule) {
        editorInput = RuleCreationInput(rule: rule)
    }

    private func setEnabled(_ isEnabled: Bool, for rule: Rule) {
        var input = RuleCreationInput(rule: rule)
        input.isEnabled = isEnabled
        coordinator.saveRule(input)
    }

    private func moveRules(_ source: IndexSet, _ destination: Int) {
        coordinator.moveRules(fromOffsets: source, toOffset: destination)
    }

    private func confirmDeletion(of ids: Set<String>) {
        guard !ids.isEmpty else { return }
        pendingDeletion = ids
        isConfirmingDeletion = true
    }
}

private struct RuleRow: View {
    let rule: Rule
    let position: Int
    let target: BrowserTarget?
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 20, alignment: .trailing)

            Image(systemName: kindSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .help(kindDescription)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .fontWeight(.medium)
                    .font(isUnnamedRegex ? .body.monospaced() : .body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(rule.isEnabled ? 1 : 0.5)

            Spacer(minLength: 12)

            RowHoverActions(isVisible: isHovering, onEdit: onEdit, onDelete: onDelete)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            TargetChip(target: target)
                .opacity(rule.isEnabled ? 1 : 0.5)

            Toggle("Enabled", isOn: Binding(get: { rule.isEnabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(rule.isEnabled ? "Turn this rule off" : "Turn this rule on")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var kindSymbol: String {
        switch rule {
        case .domain(let domainRule):
            return domainRule.pathPrefix == nil ? "globe" : "folder"
        case .urlRegex:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var kindDescription: String {
        switch rule {
        case .domain(let domainRule):
            return domainRule.pathPrefix == nil ? "Domain rule" : "Domain rule limited to a path"
        case .urlRegex:
            return "Regular expression rule"
        }
    }

    private var isUnnamedRegex: Bool {
        if case .urlRegex = rule, rule.name?.isEmpty ?? true { return true }
        return false
    }

    private var summary: String {
        var parts: [String] = []
        switch rule {
        case .domain(let domainRule):
            if rule.name?.isEmpty == false { parts.append(domainRule.domain) }
            parts.append(domainRule.matchSubdomains ? "Includes subdomains" : "This domain only")
        case .urlRegex(let regexRule):
            if rule.name?.isEmpty == false { parts.append(regexRule.pattern) }
            parts.append("Regular expression")
        }
        if !rule.isEnabled { parts.append("Off") }
        return parts.joined(separator: " · ")
    }
}
