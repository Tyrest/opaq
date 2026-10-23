import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    var viewModel: OpaqViewModel

    init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
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
        .help(
            viewModel.permissions.hasAllPermissions
                ? "opaq — Anti-Ghosting Monitor"
                : "opaq — Permissions needed")
    }
}
