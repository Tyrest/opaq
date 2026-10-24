import SwiftUI

struct PreferencesView: View {
    @Bindable var viewModel: OpaqViewModel

    init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .disabled(!viewModel.canConfigureLaunchAtLogin)

                if viewModel.launchAtLoginNeedsApproval {
                    Button("Allow in System Settings") {
                        viewModel.openLoginItemsSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text(launchAtLoginFooter)
            }

            Section {
                HStack {
                    Text("Threshold")
                    Slider(
                        value: $viewModel.gracePeriodHours,
                        in: 0...24,
                        step: 0.5
                    )
                    Text(formattedGracePeriod(viewModel.gracePeriodHours))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 72, alignment: .trailing)
                }
            } header: {
                Text("Grace Period")
            } footer: {
                Text("Wait this long after receiving a message before showing the timer in the menu bar. Messages inside this window appear under Grace Period in the popover.")
            }

            Section {
                permissionRow(
                    title: "Full Disk Access",
                    subtitle: "Read-only inspection of ~/Library/Messages/chat.db",
                    systemImage: "internaldrive",
                    isGranted: viewModel.permissions.fullDiskAccess,
                    actionTitle: "Open System Settings",
                    action: { viewModel.openFullDiskAccessSettings() }
                )

                permissionRow(
                    title: "Contacts",
                    subtitle: "Matches phone numbers and emails with names and photos",
                    systemImage: "person.crop.circle",
                    isGranted: viewModel.permissions.contactsAccess,
                    actionTitle: "Grant Access",
                    action: { viewModel.requestContactsAccess() }
                )
            } header: {
                Text("System Permissions")
            } footer: {
                Text("opaq operates in strictly read-only mode and never modifies or locks your iMessage database.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.refreshLaunchAtLoginStatus()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchesAtLogin },
            set: { viewModel.setLaunchesAtLogin($0) }
        )
    }

    private var launchAtLoginFooter: String {
        if let message = viewModel.launchAtLoginMessage, !message.isEmpty {
            return message
        }
        if !viewModel.canConfigureLaunchAtLogin {
            return "Open opaq.app to turn this on."
        }
        if viewModel.launchAtLoginNeedsApproval {
            return "Allow opaq in System Settings → General → Login Items. It will open on each login after that."
        }
        if viewModel.launchesAtLogin {
            return "opaq opens in the menu bar whenever you log in to this Mac."
        }
        return "Turn this on to open opaq whenever you log in to this Mac."
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isGranted ? Color.green : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func formattedGracePeriod(_ hours: Double) -> String {
        if hours == 0 {
            return "Instant"
        } else if hours == 1.0 {
            return "1 hour"
        } else if hours == floor(hours) {
            return "\(Int(hours)) hours"
        } else {
            return String(format: "%.1f hours", hours)
        }
    }
}
