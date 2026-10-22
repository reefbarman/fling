import SwiftUI

struct TargetsSettingsPane: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var selection = Set<String>()
    @State private var isShowingAddTarget = false
    @State private var editingTarget: BrowserTarget?
    @State private var pendingDeletion: BrowserTarget?

    private let browserDiscovery = BrowserDiscovery()

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Targets",
                subtitle:
                    "The browsers and profiles links can open in. They appear in the browser picker in this order, and turned-off targets are hidden from it. Drag to reorder."
            ) {
                Button {
                    isShowingAddTarget = true
                } label: {
                    Label("Add Target", systemImage: "plus")
                }
            }

            Divider()

            content
        }
        .sheet(isPresented: $isShowingAddTarget) {
            TargetEditorSheet(
                browserApps: browserDiscovery.installedBrowsers(),
                profileOverrides: coordinator.config.chromeProfileOverrides,
                onSave: { target in
                    coordinator.saveTarget(target)
                    isShowingAddTarget = false
                },
                onCancel: { isShowingAddTarget = false }
            )
        }
        .sheet(item: $editingTarget) { target in
            TargetEditorSheet(
                browserApps: browserDiscovery.installedBrowsers(),
                profileOverrides: coordinator.config.chromeProfileOverrides,
                initialTarget: target,
                onSave: { updated in
                    coordinator.updateTarget(updated)
                    editingTarget = nil
                },
                onCancel: { editingTarget = nil }
            )
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.displayName ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { target in
            Button(deleteButtonTitle(for: target), role: .destructive) {
                coordinator.deleteTarget(id: target.id)
                selection.remove(target.id)
            }
        } message: { target in
            let count = ruleCount(for: target)
            if count > 0 {
                Text(
                    "\(count) \(count == 1 ? "rule opens" : "rules open") links in this target and will also be deleted."
                )
            } else {
                Text("No rules use this target.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if targets.isEmpty {
            ContentUnavailableView {
                Label("No Targets", systemImage: "macwindow.on.rectangle")
            } description: {
                Text(
                    "Add a browser, or a specific Chrome, Brave or Edge profile, for links to open in."
                )
            } actions: {
                Button("Add Target") { isShowingAddTarget = true }
            }
        } else {
            List(selection: $selection) {
                ForEach(targets) { target in
                    TargetRow(
                        target: target,
                        ruleCount: ruleCount(for: target),
                        onToggle: { setEnabled($0, for: target) },
                        onEdit: { editingTarget = target },
                        onDelete: { pendingDeletion = target }
                    )
                    .tag(target.id)
                }
                .onMove { source, destination in
                    coordinator.moveTargets(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let target = target(id: ids.first) {
                    Button("Edit…") { editingTarget = target }
                    Button(target.isEnabled ? "Turn Off" : "Turn On") {
                        setEnabled(!target.isEnabled, for: target)
                    }
                    Divider()
                    Button("Delete", role: .destructive) { pendingDeletion = target }
                }
            } primaryAction: { ids in
                if ids.count == 1, let target = target(id: ids.first) {
                    editingTarget = target
                }
            }
            .onDeleteCommand {
                if selection.count == 1, let target = target(id: selection.first) {
                    pendingDeletion = target
                }
            }
        }
    }

    private var targets: [BrowserTarget] { coordinator.config.targets }

    private func target(id: String?) -> BrowserTarget? {
        targets.first { $0.id == id }
    }

    private func ruleCount(for target: BrowserTarget) -> Int {
        coordinator.config.rules.filter { $0.targetId == target.id }.count
    }

    private func deleteButtonTitle(for target: BrowserTarget) -> String {
        let count = ruleCount(for: target)
        guard count > 0 else { return "Delete" }
        return "Delete Target and \(count) \(count == 1 ? "Rule" : "Rules")"
    }

    private func setEnabled(_ isEnabled: Bool, for target: BrowserTarget) {
        var updated = target
        updated.isEnabled = isEnabled
        coordinator.updateTarget(updated)
    }
}

private struct TargetRow: View {
    let target: BrowserTarget
    let ruleCount: Int
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            TargetIconView(target: target)
                .frame(width: 32, height: 32)
                .saturation(target.isEnabled ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(target.isEnabled ? 1 : 0.5)

            Spacer(minLength: 12)

            RowHoverActions(isVisible: isHovering, onEdit: onEdit, onDelete: onDelete)

            Toggle("Enabled", isOn: Binding(get: { target.isEnabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(
                    target.isEnabled ? "Hide from the browser picker" : "Show in the browser picker"
                )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var details: String {
        var parts: [String] = []
        if let profile = target.profile {
            parts.append("\(target.applicationName) · \(profile.profileName)")
        } else if target.displayName != target.applicationName {
            parts.append(target.applicationName)
        }
        switch ruleCount {
        case 0: parts.append("No rules")
        case 1: parts.append("1 rule")
        default: parts.append("\(ruleCount) rules")
        }
        if !target.isEnabled { parts.append("Hidden from picker") }
        return parts.joined(separator: " · ")
    }
}
