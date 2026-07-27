import AppKit
import SwiftUI

public enum DeveloperToolkitPlugin {
    @MainActor
    @discardableResult
    public static func openMainWindow() -> Bool {
        DeveloperToolkitRuntime.shared.showMainWindow()
        return true
    }
}

@MainActor
private final class DeveloperToolkitRuntime {
    static let shared = DeveloperToolkitRuntime()

    private var mainWindow: NSWindow?

    private init() {}

    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "研发工具包"
            window.minSize = NSSize(width: 820, height: 560)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DeveloperToolkitRootView())
            window.center()
            mainWindow = window
        }

        if mainWindow?.isMiniaturized == true {
            mainWindow?.deminiaturize(nil)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
