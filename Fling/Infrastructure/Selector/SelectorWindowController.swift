import AppKit
import Combine
import SwiftUI

private final class SelectorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SelectorWindowController: NSObject {
    private let coordinator: AppCoordinator
    private let model: SelectorModel
    private let panel: SelectorPanel
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    /// Top-left corner the panel stays pinned to while SwiftUI resizes it.
    private var anchor: NSPoint?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.model = SelectorModel(coordinator: coordinator)
        self.panel = Self.makePanel(coordinator: coordinator, model: model)
        super.init()
        observePanelResize()
        observeCoordinator()
    }

    func show() {
        guard let context = coordinator.activeSelectorContext else { return }
        model.prepare(for: context)

        if !panel.isVisible {
            anchor = Self.anchorNearMouse(for: panel.frame.size)
            repositionToAnchor()
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private static func makePanel(coordinator: AppCoordinator, model: SelectorModel)
        -> SelectorPanel
    {
        let hostingController = NSHostingController(
            rootView: SelectorView(coordinator: coordinator, model: model))
        hostingController.sizingOptions = [.preferredContentSize]

        let panel = SelectorPanel(
            contentRect: NSRect(x: 0, y: 0, width: SelectorView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        return panel
    }

    /// Place the panel just below and centered on the cursor, where the user's attention is.
    private static func anchorNearMouse(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x - size.width / 2, y: mouse.y - 12)
    }

    private func repositionToAnchor() {
        guard let anchor else { return }
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.setFrameTopLeftPoint(anchor)
            return
        }

        let margin: CGFloat = 12
        let x = min(max(anchor.x, visible.minX + margin), visible.maxX - size.width - margin)
        let top = min(max(anchor.y, visible.minY + size.height + margin), visible.maxY - margin)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        panel.invalidateShadow()
    }

    private func observePanelResize() {
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
            .sink { [weak self] _ in self?.repositionToAnchor() }
            .store(in: &cancellables)
    }

    private func observeCoordinator() {
        coordinator.$activeSelectorContext
            .map { $0?.id }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self else { return }
                if id != nil {
                    self.show()
                } else {
                    self.close()
                }
            }
            .store(in: &cancellables)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.model.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}
