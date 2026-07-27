import AppKit
import SwiftUI

final class AccountWindowController {
    static let shared = AccountWindowController()

    private var window: NSWindow?

    func show(store: AuthenticatorStore) {
        let window = existingOrNewWindow(store: store)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func existingOrNewWindow(store: AuthenticatorStore) -> NSWindow {
        if let window {
            return window
        }

        let contentView = ContentView()
            .environmentObject(store)
            .frame(minWidth: 720, minHeight: 480)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "2FA 验证器"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        return window
    }
}
