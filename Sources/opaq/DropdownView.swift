import SwiftUI
import AppKit

public struct DropdownView: View {
    @ObservedObject var viewModel: OpaqViewModel

    public init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .frame(width: 360)
        .frame(minHeight: 200, maxHeight: 520)
        .background(.regularMaterial)
        .onAppear {
            viewModel.checkPermissions()
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
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(
                        viewModel.isRefreshing
                            ? .linear(duration: 0.7).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isRefreshing
                    )
            }
            .buttonStyle(GhostIconButtonStyle())
            .disabled(viewModel.isRefreshing)
            .help("Refresh now")

            Button(action: { viewModel.openSettingsWindow() }) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(GhostIconButtonStyle())
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        if viewModel.isQuietHoursActive {
            return "Quiet Hours until \(viewModel.quietHoursSchedule.endTimeFormatted)"
        }
        let waiting = viewModel.unrepliedPastGracePeriod.count
        if waiting == 0 {
            return "All caught up"
        }
        return waiting == 1 ? "1 waiting" : "\(waiting) waiting"
    }

    // MARK: - Content

    private var contentArea: some View {
        List {
            if !viewModel.permissions.hasAllPermissions {
                Section {
                    permissionsBanner
                }
            }

            if viewModel.unrepliedPeople.isEmpty {
                Section {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
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
        .listStyle(.sidebar)
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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !viewModel.permissions.contactsAccess {
                    Button("Contacts") { viewModel.requestContactsAccess() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Retry") { viewModel.retryConnection() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
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
                .buttonStyle(.borderedProminent)
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
