import AppKit
import SwiftUI

struct DropdownView: View {
    @Bindable var viewModel: OpaqViewModel

    init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchesAtLogin },
            set: { viewModel.setLaunchesAtLogin($0) }
        )
    }

    var body: some View {
        contentArea
            .safeAreaBar(edge: .top) { headerBar }
            .safeAreaBar(edge: .bottom) { footerBar }
            .frame(width: 360)
            .frame(minHeight: dropdownMinHeight, maxHeight: dropdownMaxHeight)
            .onAppear {
                viewModel.checkPermissions()
                viewModel.refreshLaunchAtLoginStatus()
            }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("opaq")
                    .font(.headline)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, isActive: viewModel.isRefreshing)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(viewModel.isRefreshing)
            .help("Refresh now")
            .accessibilityLabel("Refresh")

            Button(action: { viewModel.openSettingsWindow() }) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        if viewModel.databaseError != nil {
            return "Couldn't read Messages"
        }
        if viewModel.isQuietHoursActive {
            return "Quiet Hours until \(viewModel.quietHoursSchedule.endTimeFormatted)"
        }
        let waiting = viewModel.unrepliedPastGracePeriod.count
        if waiting == 0 {
            return "All caught up"
        }
        return waiting == 1 ? "1 waiting" : "\(waiting) waiting"
    }

    private var showsEmptyInbox: Bool {
        viewModel.databaseError == nil && viewModel.unrepliedPeople.isEmpty
    }

    private var emptyDropdownHeight: CGFloat {
        viewModel.permissions.hasAllPermissions ? 360 : 480
    }

    private var dropdownMinHeight: CGFloat {
        showsEmptyInbox ? emptyDropdownHeight : 220
    }

    private var dropdownMaxHeight: CGFloat {
        showsEmptyInbox ? emptyDropdownHeight : 520
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if showsEmptyInbox {
            emptyInbox
        } else {
            conversationList
        }
    }

    private var emptyInbox: some View {
        VStack(spacing: 0) {
            if !viewModel.permissions.hasAllPermissions {
                permissionsBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationList: some View {
        List {
            if !viewModel.permissions.hasAllPermissions {
                Section {
                    permissionsBanner
                }
            }

            if let databaseError = viewModel.databaseError {
                Section("Couldn't read Messages") {
                    databaseErrorSection(databaseError)
                }
            } else {
                if !viewModel.unrepliedPastGracePeriod.isEmpty {
                    Section("Waiting") {
                        ForEach(viewModel.unrepliedPastGracePeriod) { item in
                            personRow(item, isMuted: false)
                        }
                    }
                }

                if !viewModel.unrepliedInGracePeriod.isEmpty {
                    Section("Grace Period") {
                        ForEach(viewModel.unrepliedInGracePeriod) { item in
                            personRow(item, isMuted: true)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func personRow(_ item: UnrepliedPerson, isMuted: Bool) -> some View {
        PersonRowView(
            item: item,
            isMuted: isMuted,
            onReply: { viewModel.openMessages(for: item.primaryHandle) },
            onDismiss: { viewModel.dismissConversation(personId: item.person.id) }
        )
    }

    // MARK: - Permissions Banner

    private var permissionsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permissions needed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)

            Text("Full Disk Access and Contacts are required to monitor replies.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if !viewModel.permissions.fullDiskAccess {
                    Button("Disk Access") { viewModel.openFullDiskAccessSettings() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                if !viewModel.permissions.contactsAccess {
                    Button("Contacts") { viewModel.requestContactsAccess() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                Button("Retry") { viewModel.retryConnection() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Database Error

    private func databaseErrorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry") { viewModel.retryConnection() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            CuteGhostView(size: 44, isHappy: true)
                .opacity(0.9)

            Text("All caught up")
                .font(.headline)

            Text("No one is waiting on a reply")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.trackedPeople.isEmpty {
                Button(viewModel.trackAllByDefault ? "Open Settings" : "Add People to Track") {
                    viewModel.openSettingsWindow()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 6) {
            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .disabled(!viewModel.canConfigureLaunchAtLogin)
                Button("Settings…") { viewModel.openSettingsWindow() }
                Divider()
                Button("Quit opaq") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22, height: 22)
            .help("More")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
