import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class OpaqViewModel {
    static let shared = OpaqViewModel()

    // MARK: - Observable State

    private(set) var trackedPeople: [TrackedPerson] = []
    var trackAllByDefault: Bool = true {
        didSet {
            guard !isLoadingPersistedState else { return }
            saveTrackAllByDefault()
            if !trackAllByDefault && manualAdditions.isEmpty {
                manualAdditions = trackedPeople
                saveManualAdditions()
            }
            refresh()
        }
    }
    private(set) var excludedPersonIds: Set<String> = []
    private(set) var excludedPeople: [TrackedPerson] = []
    private(set) var dismissedTimestamps: [String: Int64] = [:]
    var gracePeriodHours: Double = 2.0 {
        didSet {
            guard !isLoadingPersistedState else { return }
            saveGracePeriod()
            recalculateUnrepliedStatus()
        }
    }
    var quietHoursSchedule: QuietHoursSchedule = .defaultSchedule {
        didSet {
            guard !isLoadingPersistedState else { return }
            saveQuietHoursSchedule()
            updateQuietHoursState()
        }
    }

    private(set) var unrepliedPeople: [UnrepliedPerson] = []
    private(set) var suggestedPeople: [SuggestedPerson] = []
    private(set) var permissions: PermissionStatus = .init(fullDiskAccess: false, contactsAccess: false)
    private(set) var isQuietHoursActive: Bool = false
    private(set) var isRefreshing: Bool = false
    private(set) var lastUpdated: Date? = nil
    /// Chat.db read failure. Stays nil when Full Disk Access has not been granted.
    private(set) var databaseError: String?
    var selectedSettingsPane: SettingsPane = .people

    // Derived lists
    var unrepliedPastGracePeriod: [UnrepliedPerson] {
        unrepliedPeople.filter { !$0.isInGracePeriod }
    }

    var unrepliedInGracePeriod: [UnrepliedPerson] {
        unrepliedPeople.filter { $0.isInGracePeriod }
    }

    var menuBarTimerText: String? {
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
    private var isLoadingPersistedState = false
    private var refreshPending = false

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

    init(
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
        isLoadingPersistedState = true
        defer { isLoadingPersistedState = false }

        let trackAllFallback = trackAllByDefault
        let graceFallback = gracePeriodHours
        let quietFallback = quietHoursSchedule

        let loadedTrackAll: Bool
        if userDefaults.object(forKey: trackAllByDefaultKey) != nil {
            loadedTrackAll = userDefaults.bool(forKey: trackAllByDefaultKey)
        } else {
            loadedTrackAll = trackAllFallback
        }

        let loadedExcluded: Set<String>
        if let array = userDefaults.stringArray(forKey: excludedPersonIdsKey) {
            loadedExcluded = Set(array)
        } else {
            loadedExcluded = []
        }

        let loadedManual: [TrackedPerson]
        if let data = userDefaults.data(forKey: trackedPeopleKey),
            let decoded = try? JSONDecoder().decode([TrackedPerson].self, from: data)
        {
            loadedManual = decoded
        } else {
            loadedManual = []
        }

        let loadedDismissed: [String: Int64]
        if let data = userDefaults.data(forKey: dismissedTimestampsKey),
            let decoded = try? JSONDecoder().decode([String: Int64].self, from: data)
        {
            loadedDismissed = decoded
        } else {
            loadedDismissed = [:]
        }

        let loadedBaseline: Int64
        if let number = userDefaults.object(forKey: trackingBaselineKey) as? NSNumber {
            loadedBaseline = number.int64Value
        } else {
            loadedBaseline = 0
        }

        let loadedGrace: Double
        if userDefaults.object(forKey: gracePeriodKey) != nil {
            loadedGrace = userDefaults.double(forKey: gracePeriodKey)
        } else {
            loadedGrace = graceFallback
        }

        let loadedQuiet: QuietHoursSchedule
        if let data = userDefaults.data(forKey: quietHoursKey),
            let decoded = try? JSONDecoder().decode(QuietHoursSchedule.self, from: data)
        {
            loadedQuiet = decoded
        } else {
            loadedQuiet = quietFallback
        }

        manualAdditions = loadedManual
        trackedPeople = loadedManual
        excludedPersonIds = loadedExcluded
        dismissedTimestamps = loadedDismissed
        trackingBaselineRawAppleDate = loadedBaseline
        gracePeriodHours = loadedGrace
        quietHoursSchedule = loadedQuiet
        trackAllByDefault = loadedTrackAll

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

    func performLaunchPermissionsCheck() {
        Task { @MainActor in
            let contactsGranted = await contactManager.requestAccessIfNeeded()
            if contactsGranted {
                self.contactManager.reloadContacts()
            }

            self.checkPermissions()

            if !self.permissions.hasAllPermissions {
                self.openSettingsWindow(pane: .general)
            }

            self.refresh()
        }
    }

    func checkPermissions() {
        let fda = databaseService.checkFullDiskAccess()
        let contacts = contactManager.checkAuthorizationStatus()
        let next = PermissionStatus(fullDiskAccess: fda, contactsAccess: contacts)
        if next != permissions {
            permissions = next
        }
    }

    func retryConnection() {
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

    func requestContactsAccess() {
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

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openContactsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Refresh Data

    func refresh() {
        if isRefreshing {
            refreshPending = true
            return
        }
        isRefreshing = true
        startRefresh()
    }

    private func startRefresh() {
        checkPermissions()
        updateQuietHoursState()

        let currentManual = manualAdditions
        let currentExcludedIds = excludedPersonIds
        let isTrackAll = trackAllByDefault
        let fdaGranted = permissions.fullDiskAccess

        Task { [databaseService, contactManager] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> RefreshOutcome in
                do {
                    var finalTracked: [TrackedPerson] = []
                    var finalExcluded: [TrackedPerson] = []
                    var sugg: [SuggestedPerson] = []
                    var map: [String: LatestMessageInfo] = [:]

                    if fdaGranted {
                        if isTrackAll {
                            let allRecords = try databaseService.fetchAllChatPeople(contactManager: contactManager)
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

                            map = try databaseService.fetchLatestMessages(for: finalTracked)
                        } else {
                            finalTracked = currentManual
                            map = try databaseService.fetchLatestMessages(for: finalTracked)
                            sugg = try databaseService.fetchTimeDecayedSuggestions(
                                trackedPeople: finalTracked,
                                contactManager: contactManager
                            )
                        }
                    } else {
                        finalTracked = currentManual
                    }

                    return .success(
                        RefreshSnapshot(
                            tracked: finalTracked,
                            excluded: finalExcluded,
                            suggestions: sugg,
                            latest: map
                        ))
                } catch let failure as DatabaseFailure {
                    return .failure(failure.message)
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            switch outcome {
            case .success(let snapshot):
                self.applySnapshot(snapshot, fullDiskAccess: fdaGranted)
            case .failure(let message):
                self.databaseError = message
            }
            self.completeRefresh()
        }
    }

    private func completeRefresh() {
        if refreshPending {
            refreshPending = false
            startRefresh()
        } else {
            isRefreshing = false
        }
    }

    private func applySnapshot(_ snapshot: RefreshSnapshot, fullDiskAccess: Bool) {
        databaseError = nil
        if Self.peopleChanged(trackedPeople, snapshot.tracked) {
            trackedPeople = snapshot.tracked
        }
        if Self.peopleChanged(excludedPeople, snapshot.excluded) {
            excludedPeople = snapshot.excluded
        }
        if Self.suggestionsChanged(suggestedPeople, snapshot.suggestions) {
            suggestedPeople = snapshot.suggestions
        }
        rawLatestMessages = snapshot.latest
        if fullDiskAccess {
            ensureTrackingBaselineIfNeeded()
            seedFirstSeenDismissedTimestamps()
        }
        recalculateUnrepliedStatus()
        lastUpdated = Date()
    }

    // MARK: - Ghosting & Unreplied Logic

    private func recalculateUnrepliedStatus() {
        let next = ConversationStatus.unreplied(
            people: trackedPeople,
            latestMessages: rawLatestMessages,
            dismissedTimestamps: dismissedTimestamps,
            trackingBaselineRawAppleDate: trackingBaselineRawAppleDate,
            now: Date(),
            gracePeriodHours: gracePeriodHours
        )
        if next != unrepliedPeople {
            unrepliedPeople = next
        }
    }

    private static func peopleChanged(_ current: [TrackedPerson], _ next: [TrackedPerson]) -> Bool {
        guard current.count == next.count else { return true }
        for (lhs, rhs) in zip(current, next) {
            if lhs.id != rhs.id
                || lhs.displayName != rhs.displayName
                || lhs.handles != rhs.handles
                || lhs.avatarData != rhs.avatarData
            {
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
                || lhs.totalMessages != rhs.totalMessages
            {
                return true
            }
        }
        return false
    }

    // MARK: - Contacts

    func searchContacts(query: String, limit: Int = 40) -> [ContactCard] {
        contactManager.searchContacts(query: query, limit: limit)
    }

    func trackedPerson(from card: ContactCard) -> TrackedPerson {
        contactManager.makeTrackedPerson(from: card)
    }

    func trackedPerson(manualHandle: String) -> TrackedPerson {
        contactManager.makeTrackedPerson(manualHandle: manualHandle)
    }

    // MARK: - Actions

    func addTrackedPerson(_ person: TrackedPerson) {
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

    func removeTrackedPerson(id: String) {
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

    func dismissConversation(personId: String) {
        guard let latest = rawLatestMessages[personId] else { return }
        dismissedTimestamps[personId] = latest.rawAppleDate
        saveDismissedTimestamps()
        recalculateUnrepliedStatus()
    }

    func openMessages(for handle: String) {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "imessage://\(encoded)")
        {
            NSWorkspace.shared.open(url)
        }
    }

    func openSettingsWindow(pane: SettingsPane? = nil) {
        if let pane {
            selectedSettingsPane = pane
        }
        SettingsWindowController.show(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Duration Formatting

    static func formatDuration(seconds: Double) -> String {
        ConversationStatus.formatDuration(seconds: seconds)
    }
}

private struct RefreshSnapshot: Sendable {
    var tracked: [TrackedPerson]
    var excluded: [TrackedPerson]
    var suggestions: [SuggestedPerson]
    var latest: [String: LatestMessageInfo]
}

private enum RefreshOutcome: Sendable {
    case success(RefreshSnapshot)
    case failure(String)
}
