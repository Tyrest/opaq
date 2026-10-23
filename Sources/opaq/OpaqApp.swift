import SwiftUI

@main
struct OpaqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = OpaqViewModel.shared

    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
                .background(SettingsOpenBridge())
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    viewModel.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Settings", id: SettingsOpenBridge.windowID) {
            SettingsWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultLaunchBehavior(.suppressed)
    }
}

struct SettingsOpenBridge: View {
    static let windowID = "settings"

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                SettingsOpener.open = {
                    openWindow(id: Self.windowID)
                }
            }
    }
}

@MainActor
enum SettingsOpener {
    static var open: (@MainActor () -> Void)?
}
