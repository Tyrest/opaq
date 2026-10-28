import Foundation

// MARK: - Tracked Person Model

struct TrackedPerson: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var displayName: String
    var handles: [String]
    /// Runtime-only contact photo. Omitted from persistence so old payloads can still decode.
    var avatarData: Data? = nil

    var primaryHandle: String {
        if let phone = handles.first(where: { !$0.contains("@") }) {
            return phone
        }
        return handles.first ?? id
    }

    init(id: String, displayName: String, handles: [String], avatarData: Data? = nil) {
        self.id = id
        self.displayName = displayName
        self.handles = handles
        self.avatarData = avatarData
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case handles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        handles = try container.decode([String].self, forKey: .handles)
        avatarData = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(handles, forKey: .handles)
    }

    static func == (lhs: TrackedPerson, rhs: TrackedPerson) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Quiet Hours Schedule

struct QuietHoursSchedule: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var activeWeekdays: Set<Int>
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    static let defaultSchedule = QuietHoursSchedule(
        isEnabled: true,
        activeWeekdays: [2, 3, 4, 5, 6],  // Monday through Friday (Calendar weekday: 1=Sun, 2=Mon... 7=Sat)
        startHour: 9,
        startMinute: 0,
        endHour: 17,
        endMinute: 0
    )

    init(
        isEnabled: Bool = true,
        activeWeekdays: Set<Int> = [2, 3, 4, 5, 6],
        startHour: Int = 9,
        startMinute: Int = 0,
        endHour: Int = 17,
        endMinute: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.activeWeekdays = activeWeekdays
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    func isCurrentlyActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }

        let weekday = calendar.component(.weekday, from: date)
        guard activeWeekdays.contains(weekday) else { return false }

        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)

        let currentMinutes = currentHour * 60 + currentMinute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight window (e.g. 22:00 to 07:00)
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    var startTimeFormatted: String {
        Self.formatTime(hour: startHour, minute: startMinute)
    }

    var endTimeFormatted: String {
        Self.formatTime(hour: endHour, minute: endMinute)
    }

    static func formatTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let calendar = Calendar.current
        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

// MARK: - Message Query Result

struct LatestMessageInfo: Equatable, Sendable {
    let chatIdentifier: String
    let messageId: Int64
    let isFromMe: Bool
    let rawAppleDate: Int64
    let unixTimestamp: Double
}

// MARK: - Urgency & Unreplied Person

enum UrgencyLevel: Equatable, Sendable {
    case normal  // < 24 hours (secondary/gray)
    case warning  // 24 – 72 hours (yellow/amber)
    case critical  // > 72 hours (red/coral)
}

struct UnrepliedPerson: Identifiable, Equatable, Sendable {
    var id: String { person.id }
    let person: TrackedPerson
    let latestMessage: LatestMessageInfo
    let waitTimeSeconds: Double
    let formattedDuration: String
    let isInGracePeriod: Bool
    let primaryHandle: String

    var urgency: UrgencyLevel {
        if waitTimeSeconds >= 72.0 * 3600.0 {
            return .critical
        } else if waitTimeSeconds >= 24.0 * 3600.0 {
            return .warning
        } else {
            return .normal
        }
    }

    init(
        person: TrackedPerson,
        latestMessage: LatestMessageInfo,
        waitTimeSeconds: Double,
        formattedDuration: String,
        isInGracePeriod: Bool,
        primaryHandle: String
    ) {
        self.person = person
        self.latestMessage = latestMessage
        self.waitTimeSeconds = waitTimeSeconds
        self.formattedDuration = formattedDuration
        self.isInGracePeriod = isInGracePeriod
        self.primaryHandle = primaryHandle
    }
}

// MARK: - Permission Status

struct PermissionStatus: Equatable, Sendable {
    var fullDiskAccess: Bool
    var contactsAccess: Bool

    var hasAllPermissions: Bool {
        fullDiskAccess && contactsAccess
    }

    init(fullDiskAccess: Bool = false, contactsAccess: Bool = false) {
        self.fullDiskAccess = fullDiskAccess
        self.contactsAccess = contactsAccess
    }
}

// MARK: - Contact Card (For CNContact resolution & searching)

struct ContactCard: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let phoneNumbers: [String]
    let emailAddresses: [String]
    let avatarData: Data?

    var allHandles: [String] {
        var handles = phoneNumbers
        handles.append(contentsOf: emailAddresses)
        return handles
    }

    init(
        id: String,
        displayName: String,
        phoneNumbers: [String],
        emailAddresses: [String],
        avatarData: Data? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.avatarData = avatarData
    }
}
