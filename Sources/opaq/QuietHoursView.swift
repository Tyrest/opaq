import SwiftUI

public struct QuietHoursView: View {
    @Bindable var viewModel: OpaqViewModel

    private let weekdayDays: [(id: Int, label: String, fullName: String)] = [
        (2, "Mon", "Monday"),
        (3, "Tue", "Tuesday"),
        (4, "Wed", "Wednesday"),
        (5, "Thu", "Thursday"),
        (6, "Fri", "Friday"),
        (7, "Sat", "Saturday"),
        (1, "Sun", "Sunday")
    ]

    public init(viewModel: OpaqViewModel) {
        self.viewModel = viewModel
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.quietHoursSchedule.startHour
                components.minute = viewModel.quietHoursSchedule.startMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                viewModel.quietHoursSchedule.startHour = Calendar.current.component(.hour, from: newDate)
                viewModel.quietHoursSchedule.startMinute = Calendar.current.component(.minute, from: newDate)
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = viewModel.quietHoursSchedule.endHour
                components.minute = viewModel.quietHoursSchedule.endMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                viewModel.quietHoursSchedule.endHour = Calendar.current.component(.hour, from: newDate)
                viewModel.quietHoursSchedule.endMinute = Calendar.current.component(.minute, from: newDate)
            }
        )
    }

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $viewModel.quietHoursSchedule.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause Timer During Quiet Hours")
                        Text("Hides the menu bar countdown during focus or working windows.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Label {
                    Text(statusText)
                } icon: {
                    Image(systemName: viewModel.isQuietHoursActive ? "moon.fill" : "moon")
                }
                .foregroundStyle(viewModel.isQuietHoursActive ? Color.green : Color.secondary)
            }

            Section {
                HStack(spacing: 6) {
                    ForEach(weekdayDays, id: \.id) { day in
                        Toggle(day.label, isOn: weekdayBinding(day.id))
                            .toggleStyle(.button)
                            .disabled(!viewModel.quietHoursSchedule.isEnabled)
                            .help(day.fullName)
                            .accessibilityLabel(day.fullName)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                Text("Active Days")
            } footer: {
                Text("Select recurring weekdays when quiet hours apply.")
            }

            Section {
                DatePicker(
                    "Start",
                    selection: startTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!viewModel.quietHoursSchedule.isEnabled)

                DatePicker(
                    "End",
                    selection: endTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!viewModel.quietHoursSchedule.isEnabled)
            } header: {
                Text("Active Hours")
            } footer: {
                Text("During Quiet Hours, the menu bar shows only the ghost icon. You can still open the popover at any time.")
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        if !viewModel.quietHoursSchedule.isEnabled {
            return "Quiet Hours schedule is disabled"
        }
        if viewModel.isQuietHoursActive {
            return "Quiet Hours are currently active — menu bar timer is paused"
        }
        return "Quiet Hours are currently inactive — timer will display when unreplied"
    }

    private func weekdayBinding(_ dayId: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.quietHoursSchedule.activeWeekdays.contains(dayId) },
            set: { isOn in
                if isOn {
                    viewModel.quietHoursSchedule.activeWeekdays.insert(dayId)
                } else {
                    viewModel.quietHoursSchedule.activeWeekdays.remove(dayId)
                }
            }
        )
    }
}
