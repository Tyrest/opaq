import Foundation
import Contacts
import AppKit

public final class ContactManager: @unchecked Sendable {
    public static let shared = ContactManager()

    private let store = CNContactStore()
    private let lock = NSLock()

    private var contactsCache: [ContactCard] = []
    private var idToCard: [String: ContactCard] = [:]
    private var exactPhoneToCard: [String: ContactCard] = [:]
    private var last10PhoneToCard: [String: ContactCard] = [:]
    private var emailToCard: [String: ContactCard] = [:]

    public init() {
        if checkAuthorizationStatus() {
            reloadContacts()
        }
    }

    // MARK: - Authorization

    public func checkAuthorizationStatus() -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized
    }

    public func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    @discardableResult
    public func requestAccessIfNeeded() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            return await requestAccess()
        } else if status == .authorized {
            reloadContacts()
            return true
        }
        return false
    }

    @discardableResult
    public func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            if granted {
                reloadContacts()
            }
            return granted
        } catch {
            return false
        }
    }

    public func requestOrOpenSettings() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            return await requestAccess()
        } else if status == .denied || status == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                await MainActor.run {
                    _ = NSWorkspace.shared.open(url)
                }
            }
            return false
        } else {
            reloadContacts()
            return true
        }
    }

    // MARK: - Normalization Helpers

    public static func isEmail(_ string: String) -> Bool {
        string.contains("@") && string.contains(".")
    }

    public static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Strips non-digit characters except leading '+'.
    /// Returns the exact normalized string and the last 10 digits (if applicable).
    public static func normalizePhone(_ phone: String) -> (exact: String, last10: String?) {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        var exact = ""
        var digitsOnly = ""

        let hasLeadingPlus = trimmed.hasPrefix("+")
        if hasLeadingPlus {
            exact.append("+")
        }

        for char in trimmed {
            if char.isNumber {
                exact.append(char)
                digitsOnly.append(char)
            }
        }

        let last10: String?
        if digitsOnly.count >= 10 {
            last10 = String(digitsOnly.suffix(10))
        } else {
            last10 = nil
        }

        return (exact: exact, last10: last10)
    }

    /// Normalizes a handle whether it is an email or phone number.
    public static func normalizeHandle(_ handle: String) -> String {
        if isEmail(handle) {
            return normalizeEmail(handle)
        } else {
            return normalizePhone(handle).exact
        }
    }

    // MARK: - Cache & Fetching

    public func reloadContacts() {
        guard checkAuthorizationStatus() else { return }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var cards: [ContactCard] = []

        var newIdMap: [String: ContactCard] = [:]
        var newExactPhoneMap: [String: ContactCard] = [:]
        var newLast10PhoneMap: [String: ContactCard] = [:]
        var newEmailMap: [String: ContactCard] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let givenName = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                let familyName = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)

                var fullName = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespacesAndNewlines)
                if fullName.isEmpty {
                    fullName = "Unnamed Contact"
                }

                let phoneStrings = contact.phoneNumbers.map { $0.value.stringValue }
                let emailStrings = contact.emailAddresses.map { $0.value as String }

                let card = ContactCard(
                    id: contact.identifier,
                    displayName: fullName,
                    phoneNumbers: phoneStrings,
                    emailAddresses: emailStrings,
                    avatarData: contact.thumbnailImageData
                )

                cards.append(card)
                newIdMap[card.id] = card

                for phone in phoneStrings {
                    let norm = Self.normalizePhone(phone)
                    if !norm.exact.isEmpty {
                        newExactPhoneMap[norm.exact] = card
                    }
                    if let last10 = norm.last10 {
                        newLast10PhoneMap[last10] = card
                    }
                }

                for email in emailStrings {
                    let norm = Self.normalizeEmail(email)
                    if !norm.isEmpty {
                        newEmailMap[norm] = card
                    }
                }
            }

            lock.lock()
            self.contactsCache = cards
            self.idToCard = newIdMap
            self.exactPhoneToCard = newExactPhoneMap
            self.last10PhoneToCard = newLast10PhoneMap
            self.emailToCard = newEmailMap
            lock.unlock()

        } catch {
            // Keep existing cache on failure
        }
    }

    // MARK: - Resolution & Lookup

    public func findContact(for handle: String) -> ContactCard? {
        lock.lock()
        defer { lock.unlock() }

        if Self.isEmail(handle) {
            let norm = Self.normalizeEmail(handle)
            return emailToCard[norm]
        } else {
            let norm = Self.normalizePhone(handle)
            if let card = exactPhoneToCard[norm.exact] {
                return card
            }
            if let last10 = norm.last10, let card = last10PhoneToCard[last10] {
                return card
            }
            return nil
        }
    }

    public func findContact(byId id: String) -> ContactCard? {
        lock.lock()
        defer { lock.unlock() }
        return idToCard[id]
    }

    /// A person is associated with a contact when their id is a `CNContact` identifier
    /// currently in the cache. Handles with no matching contact card use the normalized
    /// handle as their id and return false.
    public func isSavedContact(id: String) -> Bool {
        findContact(byId: id) != nil
    }

    /// Contacts-only tracking keeps saved contacts and skips raw phone numbers and emails.
    /// When the cache is still empty, previously stored contact ids are kept and handle-shaped
    /// ids are still skipped.
    public func shouldTrack(_ person: TrackedPerson, onlyTrackContacts: Bool) -> Bool {
        guard onlyTrackContacts else { return true }
        guard !person.id.isEmpty else { return false }
        if isSavedContact(id: person.id) { return true }

        lock.lock()
        let cacheLoaded = !contactsCache.isEmpty
        lock.unlock()

        if cacheLoaded { return false }
        return !Self.isHandleIdentifier(person.id)
    }

    /// True for phone numbers and emails. Contact identifiers are opaque strings, not handles.
    private static func isHandleIdentifier(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("@") { return true }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return false }
        return trimmed.allSatisfy { character in
            character.isNumber || character == "+" || character == "-" || character == "("
                || character == ")" || character == " " || character == "."
        }
    }

    public func fetchAvatarData(for contactId: String) -> Data? {
        if let card = findContact(byId: contactId) {
            return card.avatarData
        }
        return nil
    }

    public func searchContacts(query: String, limit: Int = 40) -> [ContactCard] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard limit > 0 else { return [] }

        let lowerQuery = trimmed.lowercased()
        let phoneNorm = Self.normalizePhone(trimmed)

        lock.lock()
        let all = contactsCache
        lock.unlock()

        var matches: [ContactCard] = []
        matches.reserveCapacity(min(limit, 40))

        for card in all {
            let nameMatches = card.displayName.lowercased().contains(lowerQuery)
            let emailMatches = card.emailAddresses.contains { $0.lowercased().contains(lowerQuery) }
            var phoneMatches = false
            if !nameMatches && !emailMatches {
                for phone in card.phoneNumbers {
                    let cardNorm = Self.normalizePhone(phone)
                    if cardNorm.exact.contains(phoneNorm.exact) {
                        phoneMatches = true
                        break
                    }
                    if let qLast10 = phoneNorm.last10, let cLast10 = cardNorm.last10, cLast10 == qLast10 {
                        phoneMatches = true
                        break
                    }
                }
            }
            if nameMatches || emailMatches || phoneMatches {
                matches.append(card)
                if matches.count >= limit {
                    break
                }
            }
        }

        return matches
    }

    // MARK: - TrackedPerson Factory

    public func makeTrackedPerson(from card: ContactCard, extraHandles: [String] = []) -> TrackedPerson {
        var handlesSet = Set<String>()
        for h in card.phoneNumbers { handlesSet.insert(h) }
        for h in card.emailAddresses { handlesSet.insert(h) }
        for h in extraHandles { handlesSet.insert(h) }

        return TrackedPerson(
            id: card.id,
            displayName: card.displayName,
            handles: Array(handlesSet),
            avatarData: card.avatarData
        )
    }

    public func makeTrackedPerson(manualHandle: String) -> TrackedPerson {
        let trimmed = manualHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let card = findContact(for: trimmed) {
            return makeTrackedPerson(from: card, extraHandles: [trimmed])
        }

        let norm = Self.normalizeHandle(trimmed)
        return TrackedPerson(
            id: norm,
            displayName: trimmed,
            handles: [trimmed],
            avatarData: nil
        )
    }
}
