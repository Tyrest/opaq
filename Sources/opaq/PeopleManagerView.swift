import SwiftUI

struct PeopleManagerView: View {
    @Bindable var viewModel: OpaqViewModel
    @State private var searchText: String = ""
    @State private var searchResults: [ContactCard] = []

    init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
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
        .listStyle(.inset)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search contacts")
        .onChange(of: searchText) { _, newValue in
            searchResults = viewModel.searchContacts(query: newValue, limit: 40)
        }
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        let matching = searchResults
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
                        let person = viewModel.trackedPerson(manualHandle: query)
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
                            avatarData: card.avatarData,
                            cacheKey: card.id
                        )

                        Spacer()

                        if isTracked {
                            Text("Tracked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Track") {
                                let person = viewModel.trackedPerson(from: card)
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
        let title =
            viewModel.trackAllByDefault
            ? "Automatically Tracked (\(viewModel.trackedPeople.count))"
            : "Currently Tracking (\(viewModel.trackedPeople.count))"

        return Section(title) {
            if viewModel.trackedPeople.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.trackAllByDefault ? "No active conversations found" : "No contacts tracked yet")
                    Text(
                        viewModel.trackAllByDefault
                            ? (viewModel.permissions.fullDiskAccess
                                ? "Your 1-on-1 iMessage conversations will automatically appear here."
                                : "Full Disk Access is required to automatically discover conversations.")
                            : "Add someone from the suggestions below, or use the search field."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.trackedPeople) { person in
                    HStack(spacing: 10) {
                        ContactIdentityRow(
                            name: person.displayName,
                            detail: person.primaryHandle,
                            avatarData: person.avatarData,
                            cacheKey: person.id
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
                        avatarData: person.avatarData,
                        cacheKey: person.id
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
                            avatarData: suggestion.person.avatarData,
                            cacheKey: suggestion.person.id
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
