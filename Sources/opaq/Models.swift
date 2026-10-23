import Foundation

// MARK: - Tracked Person Model

public struct TrackedPerson: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var displayName: String
    public var handles: [String]
    public var avatarData: Data?

    public var primaryHandle: String {
        handles.first ?? id
    }

    public init(id: String, displayName: String, handles: [String], avatarData: Data? = nil) {
        self.id = id
        self.displayName = displayName
        self.handles = handles
        self.avatarData = avatarData
    }

    public static func == (lhs: TrackedPerson, rhs: TrackedPerson) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Quiet Hours Schedule

public struct QuietHoursSchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var activeWeekdays: Set<Int>
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int

    public static let defaultSchedule = QuietHoursSchedule(
        isEnabled: true,
        activeWeekdays: [2, 3, 4, 5, 6], // Monday through Friday (Calendar weekday: 1=Sun, 2=Mon... 7=Sat)
        startHour: 9,
        startMinute: 0,
        endHour: 17,
        endMinute: 0
    )

    public init(
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

    public func isCurrentlyActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
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

    public var startTimeFormatted: String {
        Self.formatTime(hour: startHour, minute: startMinute)
    }

    public var endTimeFormatted: String {
        Self.formatTime(hour: endHour, minute: endMinute)
    }

    public var bannerText: String {
        "🌙 Quiet Hours (\(startTimeFormatted) – \(endTimeFormatted)) • Timer hidden"
    }

    public static func formatTime(hour: Int, minute: Int) -> String {
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

public struct LatestMessageInfo: Equatable, Sendable {
    public let chatIdentifier: String
    public let messageId: Int64
    public let isFromMe: Bool
    public let rawAppleDate: Int64
    public let unixTimestamp: Double

    public init(
        chatIdentifier: String,
        messageId: Int64,
        isFromMe: Bool,
        rawAppleDate: Int64,
        unixTimestamp: Double
    ) {
        self.chatIdentifier = chatIdentifier
        self.messageId = messageId
        self.isFromMe = isFromMe
        self.rawAppleDate = rawAppleDate
        self.unixTimestamp = unixTimestamp
    }
}

// MARK: - Urgency & Unreplied Person

public enum UrgencyLevel: Equatable, Sendable {
    case normal     // < 24 hours (secondary/gray)
    case warning    // 24 – 72 hours (yellow/amber)
    case critical   // > 72 hours (red/coral)
}

public struct UnrepliedPerson: Identifiable, Equatable, Sendable {
    public var id: String { person.id }
    public let person: TrackedPerson
    public let latestMessage: LatestMessageInfo
    public let waitTimeSeconds: Double
    public let formattedDuration: String
    public let isInGracePeriod: Bool
    public let primaryHandle: String

    public var urgency: UrgencyLevel {
        if waitTimeSeconds >= 72.0 * 3600.0 {
            return .critical
        } else if waitTimeSeconds >= 24.0 * 3600.0 {
            return .warning
        } else {
            return .normal
        }
    }

    public init(
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

// MARK: - Suggested Person Model

public struct SuggestedPerson: Identifiable, Equatable, Sendable {
    public var id: String { person.id }
    public let person: TrackedPerson
    public let totalMessages: Int
    public let recencyWeightedScore: Double

    public init(person: TrackedPerson, totalMessages: Int, recencyWeightedScore: Double) {
        self.person = person
        self.totalMessages = totalMessages
        self.recencyWeightedScore = recencyWeightedScore
    }
}

// MARK: - Discovered Person Model (from iMessage history)

public struct DiscoveredPersonRecord: Identifiable, Equatable, Sendable {
    public var id: String { person.id }
    public let person: TrackedPerson
    public let totalMessages: Int
    public let recencyWeightedScore: Double

    public init(person: TrackedPerson, totalMessages: Int, recencyWeightedScore: Double) {
        self.person = person
        self.totalMessages = totalMessages
        self.recencyWeightedScore = recencyWeightedScore
    }
}

// MARK: - Permission Status

public struct PermissionStatus: Equatable, Sendable {
    public var fullDiskAccess: Bool
    public var contactsAccess: Bool

    public var hasAllPermissions: Bool {
        fullDiskAccess && contactsAccess
    }

    public init(fullDiskAccess: Bool = false, contactsAccess: Bool = false) {
        self.fullDiskAccess = fullDiskAccess
        self.contactsAccess = contactsAccess
    }
}

// MARK: - Contact Card (For CNContact resolution & searching)

public struct ContactCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let phoneNumbers: [String]
    public let emailAddresses: [String]
    public let avatarData: Data?

    public var allHandles: [String] {
        var handles = phoneNumbers
        handles.append(contentsOf: emailAddresses)
        return handles
    }

    public init(
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
