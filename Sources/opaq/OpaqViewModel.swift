import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
public final class OpaqViewModel {
    public static let shared = OpaqViewModel()

    // MARK: - Observable State

    public private(set) var trackedPeople: [TrackedPerson] = []
    public var trackAllByDefault: Bool = true {
        didSet {
            saveTrackAllByDefault()
            if !trackAllByDefault && manualAdditions.isEmpty {
                manualAdditions = trackedPeople
                saveManualAdditions()
            }
            refresh()
        }
    }
    public private(set) var excludedPersonIds: Set<String> = []
    public private(set) var excludedPeople: [TrackedPerson] = []
    public private(set) var dismissedTimestamps: [String: Int64] = [:]
    public var gracePeriodHours: Double = 2.0 {
        didSet {
            saveGracePeriod()
            recalculateUnrepliedStatus()
        }
    }
    public var quietHoursSchedule: QuietHoursSchedule = .defaultSchedule {
        didSet {
            saveQuietHoursSchedule()
            updateQuietHoursState()
        }
    }

    public private(set) var unrepliedPeople: [UnrepliedPerson] = []
    public private(set) var suggestedPeople: [SuggestedPerson] = []
    public private(set) var permissions: PermissionStatus = .init(fullDiskAccess: false, contactsAccess: false)
    public private(set) var isQuietHoursActive: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastUpdated: Date? = nil
    public var selectedSettingsPane: SettingsPane = .people

    // Derived lists
    public var unrepliedPastGracePeriod: [UnrepliedPerson] {
        unrepliedPeople.filter { !$0.isInGracePeriod }
    }

    public var unrepliedInGracePeriod: [UnrepliedPerson] {
        unrepliedPeople.filter { $0.isInGracePeriod }
    }

    public var menuBarTimerText: String? {
        guard !isQuietHoursActive else { return nil }
        guard let first = unrepliedPastGracePeriod.first else { return nil }
        return first.formattedDuration
    }

    // MARK: - Private State & Dependencies

    private let contactManager: ContactManager
    private let databaseService: DatabaseService
    private let fileWatcher: FileWatcher

    private var manualAdditions: [TrackedPerson] = []
    private var repeatingTimer: Timer?
    private var rawLatestMessages: [String: LatestMessageInfo] = [:]

    private let userDefaults = UserDefaults.standard
    private let trackAllByDefaultKey = "com.local.opaq.trackAllByDefault"
    private let excludedPersonIdsKey = "com.local.opaq.excludedPersonIds"
    private let trackedPeopleKey = "com.local.opaq.trackedPeople"
    private let dismissedTimestampsKey = "com.local.opaq.dismissedTimestamps"
    private let trackingBaselineKey = "com.local.opaq.trackingBaselineRawAppleDate"
    private let gracePeriodKey = "com.local.opaq.gracePeriodHours"
    private let quietHoursKey = "com.local.opaq.quietHoursSchedule"

    /// Apple `m.date` nanoseconds since 2001-01-01. 0 until first FDA-successful refresh.
    private var trackingBaselineRawAppleDate: Int64 = 0

    // MARK: - Initialization

    public init(
        contactManager: ContactManager = .shared,
        databaseService: DatabaseService = .shared,
        fileWatcher: FileWatcher = FileWatcher()
    ) {
        self.contactManager = contactManager
        self.databaseService = databaseService
        self.fileWatcher = fileWatcher

        loadPersistedState()
        checkPermissions()
        startPeriodicTimer()
        startFileWatcher()
        performLaunchPermissionsCheck()
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if userDefaults.object(forKey: trackAllByDefaultKey) != nil {
            self.trackAllByDefault = userDefaults.bool(forKey: trackAllByDefaultKey)
        } else {
            self.trackAllByDefault = true
        }

        if let array = userDefaults.stringArray(forKey: excludedPersonIdsKey) {
            self.excludedPersonIds = Set(array)
        }

        if let data = userDefaults.data(forKey: trackedPeopleKey),
           let decoded = try? JSONDecoder().decode([TrackedPerson].self, from: data) {
            self.manualAdditions = decoded
            self.trackedPeople = decoded
        }

        if let data = userDefaults.data(forKey: dismissedTimestampsKey),
           let decoded = try? JSONDecoder().decode([String: Int64].self, from: data) {
            self.dismissedTimestamps = decoded
        }

        if let number = userDefaults.object(forKey: trackingBaselineKey) as? NSNumber {
            self.trackingBaselineRawAppleDate = number.int64Value
        }

        if userDefaults.object(forKey: gracePeriodKey) != nil {
            self.gracePeriodHours = userDefaults.double(forKey: gracePeriodKey)
        }

        if let data = userDefaults.data(forKey: quietHoursKey),
           let decoded = try? JSONDecoder().decode(QuietHoursSchedule.self, from: data) {
            self.quietHoursSchedule = decoded
        }

        updateQuietHoursState()
    }

    private func saveTrackAllByDefault() {
        userDefaults.set(trackAllByDefault, forKey: trackAllByDefaultKey)
    }

    private func saveExcludedPersonIds() {
        userDefaults.set(Array(excludedPersonIds), forKey: excludedPersonIdsKey)
    }

    private func saveManualAdditions() {
        if let encoded = try? JSONEncoder().encode(manualAdditions) {
            userDefaults.set(encoded, forKey: trackedPeopleKey)
        }
    }

    private func saveTrackedPeople() {
        if let encoded = try? JSONEncoder().encode(trackedPeople) {
            userDefaults.set(encoded, forKey: trackedPeopleKey)
        }
    }

    private func saveDismissedTimestamps() {
        if let encoded = try? JSONEncoder().encode(dismissedTimestamps) {
            userDefaults.set(encoded, forKey: dismissedTimestampsKey)
        }
    }

    private func saveTrackingBaseline() {
        userDefaults.set(NSNumber(value: trackingBaselineRawAppleDate), forKey: trackingBaselineKey)
    }

    /// Set once on the first refresh that actually has Full Disk Access — not at process init.
    private func ensureTrackingBaselineIfNeeded() {
        guard userDefaults.object(forKey: trackingBaselineKey) == nil else { return }
        let appleEpochOffset: TimeInterval = 978_307_200
        trackingBaselineRawAppleDate = Int64((Date().timeIntervalSince1970 - appleEpochOffset) * 1_000_000_000)
        saveTrackingBaseline()
    }

    /// First time a person is seen while tracked, ignore threads whose latest message is at or
    /// before the first-connect baseline. Do not seed post-baseline inbound or it would swallow
    /// the message that should start the timer.
    private func seedFirstSeenDismissedTimestamps() {
        guard trackingBaselineRawAppleDate > 0 else { return }
        var didChange = false
        for person in trackedPeople {
            guard dismissedTimestamps[person.id] == nil else { continue }
            guard let latest = rawLatestMessages[person.id] else { continue }
            guard latest.rawAppleDate <= trackingBaselineRawAppleDate else { continue }
            dismissedTimestamps[person.id] = latest.rawAppleDate
            didChange = true
        }
        if didChange {
            saveDismissedTimestamps()
        }
    }

    private func saveGracePeriod() {
        userDefaults.set(gracePeriodHours, forKey: gracePeriodKey)
    }

    private func saveQuietHoursSchedule() {
        if let encoded = try? JSONEncoder().encode(quietHoursSchedule) {
            userDefaults.set(encoded, forKey: quietHoursKey)
        }
    }

    // MARK: - Periodic Timer & Real-Time Monitoring

    private func startPeriodicTimer() {
        repeatingTimer?.invalidate()
        repeatingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.periodicHeartbeat()
            }
        }
    }

    private func startFileWatcher() {
        fileWatcher.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func periodicHeartbeat() {
        updateQuietHoursState()
        recalculateUnrepliedStatus()
    }

    private func updateQuietHoursState() {
        let active = quietHoursSchedule.isCurrentlyActive()
        if active != isQuietHoursActive {
            isQuietHoursActive = active
        }
    }

    // MARK: - Permissions & Setup

    public func performLaunchPermissionsCheck() {
        Task { @MainActor in
            // 1. Actively request Contacts permission if not determined (triggers macOS system prompt)
            let contactsGranted = await contactManager.requestAccessIfNeeded()
            if contactsGranted {
                self.contactManager.reloadContacts()
            }

            // 2. Re-evaluate permission status
            self.checkPermissions()

            // 3. If either permission is missing, open Settings so setup is a normal window
            if !self.permissions.hasAllPermissions {
                self.openSettingsWindow(pane: .general)
            }

            // 4. Refresh data
            self.refresh()
        }
    }

    public func checkPermissions() {
        let fda = databaseService.checkFullDiskAccess()
        let contacts = contactManager.checkAuthorizationStatus()
        let next = PermissionStatus(fullDiskAccess: fda, contactsAccess: contacts)
        if next != permissions {
            permissions = next
        }
    }

    public func retryConnection() {
        Task { @MainActor in
            if !self.permissions.contactsAccess {
                _ = await self.contactManager.requestAccessIfNeeded()
            }
            self.checkPermissions()
            if self.permissions.contactsAccess {
                self.contactManager.reloadContacts()
            }
            self.refresh()
        }
    }

    public func requestContactsAccess() {
        Task { @MainActor in
            let granted = await contactManager.requestOrOpenSettings()
            self.permissions.contactsAccess = granted
            if granted {
                self.contactManager.reloadContacts()
                self.checkPermissions()
                self.refresh()
            }
        }
    }

    public func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openContactsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Refresh Data

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        checkPermissions()
        updateQuietHoursState()

        let currentManual = self.manualAdditions
        let currentExcludedIds = self.excludedPersonIds
        let isTrackAll = self.trackAllByDefault
        let fdaGranted = permissions.fullDiskAccess

        Task { [databaseService, contactManager] in
            let (newTracked, newExcluded, suggestions, latestMap) = await Task.detached(priority: .userInitiated) { () -> ([TrackedPerson], [TrackedPerson], [SuggestedPerson], [String: LatestMessageInfo]) in
                var finalTracked: [TrackedPerson] = []
                var finalExcluded: [TrackedPerson] = []
                var sugg: [SuggestedPerson] = []
                var map: [String: LatestMessageInfo] = [:]

                if fdaGranted {
                    if isTrackAll {
                        let allRecords = databaseService.fetchAllChatPeople(contactManager: contactManager)
                        var seenIds = Set<String>()

                        for record in allRecords {
                            seenIds.insert(record.person.id)
                            if currentExcludedIds.contains(record.person.id) {
                                finalExcluded.append(record.person)
                            } else {
                                finalTracked.append(record.person)
                            }
                        }

                        for person in currentManual {
                            if !seenIds.contains(person.id) {
                                seenIds.insert(person.id)
                                if currentExcludedIds.contains(person.id) {
                                    finalExcluded.append(person)
                                } else {
                                    finalTracked.append(person)
                                }
                            }
                        }

                        // Batch fetch Query B for all tracked people
                        map = databaseService.fetchLatestMessages(for: finalTracked)
                    } else {
                        finalTracked = currentManual
                        map = databaseService.fetchLatestMessages(for: finalTracked)
                        sugg = databaseService.fetchTimeDecayedSuggestions(
                            trackedPeople: finalTracked,
                            contactManager: contactManager
                        )
                    }
                } else {
                    finalTracked = currentManual
                }

                return (finalTracked, finalExcluded, sugg, map)
            }.value

            if Self.peopleChanged(trackedPeople, newTracked) {
                self.trackedPeople = newTracked
            }
            if Self.peopleChanged(excludedPeople, newExcluded) {
                self.excludedPeople = newExcluded
            }
            if Self.suggestionsChanged(suggestedPeople, suggestions) {
                self.suggestedPeople = suggestions
            }
            self.rawLatestMessages = latestMap
            if fdaGranted {
                self.ensureTrackingBaselineIfNeeded()
                self.seedFirstSeenDismissedTimestamps()
            }
            self.recalculateUnrepliedStatus()
            self.lastUpdated = Date()
            self.isRefreshing = false
        }
    }

    // MARK: - Ghosting & Unreplied Logic

    private func recalculateUnrepliedStatus() {
        let nowUnix = Date().timeIntervalSince1970
        let gracePeriodSeconds = gracePeriodHours * 3600.0

        var unrepliedList: [UnrepliedPerson] = []

        for person in trackedPeople {
            guard let latest = rawLatestMessages[person.id] else {
                continue
            }

            // Must be from them (is_from_me == 0)
            guard !latest.isFromMe else {
                continue
            }

            // Must be newer than Conversation Ended and the first-connect tracking baseline
            let dismissedTimestamp = dismissedTimestamps[person.id] ?? 0
            let effectiveFloor = max(dismissedTimestamp, trackingBaselineRawAppleDate)
            guard latest.rawAppleDate > effectiveFloor else {
                continue
            }

            let waitTime = max(0, nowUnix - latest.unixTimestamp)
            let formatted = Self.formatDuration(seconds: waitTime)
            let inGrace = waitTime < gracePeriodSeconds

            let unreplied = UnrepliedPerson(
                person: person,
                latestMessage: latest,
                waitTimeSeconds: waitTime,
                formattedDuration: formatted,
                isInGracePeriod: inGrace,
                primaryHandle: person.primaryHandle
            )
            unrepliedList.append(unreplied)
        }

        // Sort ascending by unix_timestamp (longest waiting / oldest message is #1 at top)
        unrepliedList.sort { $0.latestMessage.unixTimestamp < $1.latestMessage.unixTimestamp }

        if unrepliedList != unrepliedPeople {
            unrepliedPeople = unrepliedList
        }
    }

    private static func peopleChanged(_ current: [TrackedPerson], _ next: [TrackedPerson]) -> Bool {
        guard current.count == next.count else { return true }
        for (lhs, rhs) in zip(current, next) {
            if lhs.id != rhs.id || lhs.displayName != rhs.displayName || lhs.handles != rhs.handles {
                return true
            }
        }
        return false
    }

    private static func suggestionsChanged(_ current: [SuggestedPerson], _ next: [SuggestedPerson]) -> Bool {
        guard current.count == next.count else { return true }
        for (lhs, rhs) in zip(current, next) {
            if lhs.person.id != rhs.person.id
                || lhs.person.displayName != rhs.person.displayName
                || lhs.totalMessages != rhs.totalMessages {
                return true
            }
        }
        return false
    }

    // MARK: - Actions

    public func addTrackedPerson(_ person: TrackedPerson) {
        if excludedPersonIds.contains(person.id) {
            excludedPersonIds.remove(person.id)
            saveExcludedPersonIds()
        }
        if !manualAdditions.contains(where: { $0.id == person.id }) {
            manualAdditions.append(person)
            saveManualAdditions()
        }
        if !trackedPeople.contains(where: { $0.id == person.id }) {
            trackedPeople.append(person)
        }
        refresh()
    }

    public func removeTrackedPerson(id: String) {
        if trackAllByDefault {
            excludedPersonIds.insert(id)
            saveExcludedPersonIds()
        }
        manualAdditions.removeAll { $0.id == id }
        saveManualAdditions()
        trackedPeople.removeAll { $0.id == id }
        dismissedTimestamps.removeValue(forKey: id)
        rawLatestMessages.removeValue(forKey: id)
        saveDismissedTimestamps()
        recalculateUnrepliedStatus()
        refresh()
    }

    public func dismissConversation(personId: String) {
        guard let latest = rawLatestMessages[personId] else { return }
        dismissedTimestamps[personId] = latest.rawAppleDate
        saveDismissedTimestamps()
        recalculateUnrepliedStatus()
    }

    public func openMessages(for handle: String) {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "imessage://\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSettingsWindow(pane: SettingsPane? = nil) {
        if let pane {
            selectedSettingsPane = pane
        }
        if let open = SettingsOpener.open {
            open()
        } else {
            DispatchQueue.main.async { [weak self] in
                SettingsOpener.open?()
                NSApp.activate(ignoringOtherApps: true)
                _ = self
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Duration Formatting

    public static func formatDuration(seconds: Double) -> String {
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            let m = Int(seconds / 60)
            return "\(m)m"
        } else if seconds < 86400 {
            let h = Int(seconds / 3600)
            let m = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            let d = Int(seconds / 86400)
            let h = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
            return h > 0 ? "\(d)d \(h)h" : "\(d)d"
        }
    }
}
