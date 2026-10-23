import SwiftUI

public struct PeopleManagerView: View {
    @ObservedObject var viewModel: OpaqViewModel
    @State private var searchText: String = ""

    public init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                TextField("Search contacts by name, phone, or email", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResultsSection
            } else {
                defaultTrackingToggleSection
                currentlyTrackingSection
                if viewModel.trackAllByDefault {
                    if !viewModel.excludedPeople.isEmpty {
                        excludedPeopleSection
                    }
                } else {
                    suggestedPeopleSection
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        let matching = ContactManager.shared.searchContacts(query: searchText)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return Section("Search Results") {
            if matching.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No matching contacts found")
                            .foregroundStyle(.secondary)
                        Text("You can track “\(query)” directly as a manual handle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Track Directly") {
                        let person = ContactManager.shared.makeTrackedPerson(manualHandle: query)
                        viewModel.addTrackedPerson(person)
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                ForEach(matching) { card in
                    let isTracked = viewModel.trackedPeople.contains { $0.id == card.id }
                    HStack(spacing: 10) {
                        ContactIdentityRow(
                            name: card.displayName,
                            detail: card.allHandles.prefix(2).joined(separator: ", "),
                            avatarData: card.avatarData
                        )

                        Spacer()

                        if isTracked {
                            Text("Tracked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Track") {
                                let person = ContactManager.shared.makeTrackedPerson(from: card)
                                viewModel.addTrackedPerson(person)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Default Tracking Toggle

    private var defaultTrackingToggleSection: some View {
        Section {
            Toggle(isOn: $viewModel.trackAllByDefault) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track Everyone by Default")
                    Text("Automatically monitor all 1-on-1 iMessage conversations. Only messages sent after you first connected opaq start the timer. You can exclude specific contacts below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Currently Tracking

    private var currentlyTrackingSection: some View {
        let title = viewModel.trackAllByDefault
            ? "Automatically Tracked (\(viewModel.trackedPeople.count))"
            : "Currently Tracking (\(viewModel.trackedPeople.count))"

        return Section(title) {
            if viewModel.trackedPeople.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.trackAllByDefault ? "No active conversations found" : "No contacts tracked yet")
                    Text(viewModel.trackAllByDefault
                         ? (viewModel.permissions.fullDiskAccess
                            ? "Your 1-on-1 iMessage conversations will automatically appear here."
                            : "Full Disk Access is required to automatically discover conversations.")
                         : "Add someone from the suggestions below or search above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.trackedPeople) { person in
                    HStack(spacing: 10) {
                        ContactIdentityRow(
                            name: person.displayName,
                            detail: person.primaryHandle,
                            avatarData: person.avatarData
                        )

                        Spacer()

                        Button(viewModel.trackAllByDefault ? "Exclude" : "Remove") {
                            viewModel.removeTrackedPerson(id: person.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Excluded People

    private var excludedPeopleSection: some View {
        Section("Excluded from Tracking (\(viewModel.excludedPeople.count))") {
            ForEach(viewModel.excludedPeople) { person in
                HStack(spacing: 10) {
                    ContactIdentityRow(
                        name: person.displayName,
                        detail: person.primaryHandle,
                        avatarData: person.avatarData
                    )

                    Spacer()

                    Button("Track") {
                        viewModel.addTrackedPerson(person)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Suggested People

    private var suggestedPeopleSection: some View {
        Section("Suggested from iMessage") {
            if viewModel.suggestedPeople.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No suggestions available")
                    Text("Top 1-on-1 conversations from iMessage will automatically appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.suggestedPeople) { suggestion in
                    HStack(spacing: 10) {
                        ContactIdentityRow(
                            name: suggestion.person.displayName,
                            detail: suggestion.person.primaryHandle,
                            avatarData: suggestion.person.avatarData
                        )

                        Spacer()

                        Text("\(suggestion.totalMessages) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Track") {
                            viewModel.addTrackedPerson(suggestion.person)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
