import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject {
    private let coordinator: AppCoordinator
    private var windowController: NSWindowController?
    private var closeObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        NSApp.setActivationPolicy(.regular)

        if let window = windowController?.window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // The window owns its size. Hosting via a content view controller lets SwiftUI resize the
        // window to the list's full height and caused an AppKit layout recursion.
        let hostingView = NSHostingView(rootView: SettingsView(coordinator: coordinator))
        hostingView.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fling Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.contentView = hostingView
        // Remembers size and position between openings once the user moves it.
        let autosaveName = "FlingSettingsWindow.v2"
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }

        let controller = NSWindowController(window: window)
        self.windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
