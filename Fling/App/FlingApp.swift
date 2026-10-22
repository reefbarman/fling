import SwiftUI

@main
struct FlingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared

    var body: some Scene {
        Settings {
            SettingsView(coordinator: coordinator)
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}
