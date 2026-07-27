import AppKit
import SwiftData
import SwiftUI

@MainActor
final class MainWindowPresenter {
    static let shared = MainWindowPresenter()

    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?

    private init() {}

    func show(appState: AppState, modelContainer: ModelContainer) {
        if let existingWindow = NSApp.windows.first(where: { $0.title == "MindAnchor" && $0.isVisible }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            AppLog.app.info("main_window_existing_activated")
            return
        }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            AppLog.app.info("main_window_reused")
            return
        }

        let rootView = MainWindowView(appState: appState)
            .modelContainer(modelContainer)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MindAnchor"
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
            AppLog.app.info("main_window_closed")
        }
        window.delegate = delegate
        windowDelegate = delegate

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.app.info("main_window_opened")
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
