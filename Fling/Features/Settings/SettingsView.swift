import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case rules
    case targets
    case testLink
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: return "Rules"
        case .targets: return "Targets"
        case .testLink: return "Test a Link"
        case .general: return "General"
        }
    }

    var systemImage: String {
        switch self {
        case .rules: return "list.bullet.rectangle"
        case .targets: return "macwindow.on.rectangle"
        case .testLink: return "link"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("settings.selectedPane") private var selectedPane: SettingsPane = .rules

    var body: some View {
        // A plain HStack rather than NavigationSplitView: the split view expects a SwiftUI-managed
        // window and rendered blank/offset inside this AppKit-hosted one.
        HStack(spacing: 0) {
            List(selection: selectionBinding) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .badge(badge(for: pane))
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            Group {
                switch selectedPane {
                case .rules:
                    RulesSettingsPane(coordinator: coordinator)
                case .targets:
                    TargetsSettingsPane(coordinator: coordinator)
                case .testLink:
                    TestLinkSettingsPane(coordinator: coordinator)
                case .general:
                    GeneralSettingsPane(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { coordinator.lastErrorMessage != nil },
                set: { if !$0 { coordinator.clearLastError() } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    coordinator.clearLastError()
                }
            },
            message: {
                Text(coordinator.lastErrorMessage ?? "Unknown error")
            }
        )
    }

    /// The sidebar List needs an optional selection; never let it become nil.
    private var selectionBinding: Binding<SettingsPane?> {
        Binding(
            get: { selectedPane },
            set: { if let newValue = $0 { selectedPane = newValue } }
        )
    }

    private func badge(for pane: SettingsPane) -> Int {
        switch pane {
        case .rules: return coordinator.config.rules.count
        case .targets: return coordinator.config.targets.count
        case .testLink, .general: return 0
        }
    }
}
