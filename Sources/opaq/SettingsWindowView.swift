import SwiftUI

struct SettingsWindowView: View {
    @Bindable var viewModel: OpaqViewModel

    init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedSettingsPane) {
                Section {
                    ForEach(SettingsPane.allCases, id: \.self) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            destination(for: viewModel.selectedSettingsPane)
                .navigationTitle(viewModel.selectedSettingsPane.title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    // People hosts a search field in this slot. Keep the same
                    // toolbar height on the other panes so the traffic lights stay put.
                    if viewModel.selectedSettingsPane != .people {
                        ToolbarItem(placement: .primaryAction) {
                            Color.clear
                                .frame(width: 1, height: 24)
                                .accessibilityHidden(true)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.visible, for: .windowToolbar)
        .frame(minWidth: 780, minHeight: 520)
    }

    @ViewBuilder
    private func destination(for pane: SettingsPane) -> some View {
        switch pane {
        case .people:
            PeopleManagerView(viewModel: viewModel)
        case .quietHours:
            QuietHoursView(viewModel: viewModel)
        case .general:
            PreferencesView(viewModel: viewModel)
        }
    }
}
