import SwiftUI
import AppKit

public struct MenuBarLabelView: View {
    var viewModel: OpaqViewModel

    public init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: GhostIconGenerator.menuBarGhostImage)

            if !viewModel.permissions.hasAllPermissions {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 8))
                    .symbolRenderingMode(.multicolor)
            } else if let timer = viewModel.menuBarTimerText {
                Text(timer)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .help(viewModel.permissions.hasAllPermissions
              ? "opaq — Anti-Ghosting Monitor"
              : "opaq — Permissions needed")
    }
}
