import SwiftUI

public struct SettingsWindowView: View {
    @ObservedObject var viewModel: OpaqViewModel

    public init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView(selection: $viewModel.settingsPane) {
            PeopleManagerView(viewModel: viewModel)
                .tabItem {
                    Label("People", systemImage: "person.2")
                }
                .tag(SettingsPane.people)

            QuietHoursView(viewModel: viewModel)
                .tabItem {
                    Label("Quiet Hours", systemImage: "moon")
                }
                .tag(SettingsPane.quietHours)

            PreferencesView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsPane.general)
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 440, idealHeight: 520)
    }
}
