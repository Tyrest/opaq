import AppKit
import SwiftUI

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func show(_ viewModel: OpaqViewModel) {
        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: SettingsWindowView(viewModel: viewModel))
            let created = NSWindow(contentViewController: hosting)
            created.title = "Settings"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            created.titlebarAppearsTransparent = false
            created.toolbarStyle = .unified
            created.setContentSize(NSSize(width: 900, height: 640))
            created.contentMinSize = NSSize(width: 780, height: 520)
            created.isReleasedWhenClosed = false
            created.identifier = NSUserInterfaceItemIdentifier("settings")
            self.window = created
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
