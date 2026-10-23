import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowManager {
    public static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private init() {}

    public func show(viewModel: OpaqViewModel) {
        if let window = self.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindowView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Settings"
        newWindow.toolbarStyle = .preference
        newWindow.center()
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 600, height: 440)
        newWindow.setContentSize(NSSize(width: 680, height: 520))

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
