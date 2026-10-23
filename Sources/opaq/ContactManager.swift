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

    public func fetchAvatarData(for contactId: String) -> Data? {
        if let card = findContact(byId: contactId) {
            return card.avatarData
        }
        return nil
    }

    public func searchContacts(query: String) -> [ContactCard] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lock.lock()
            let all = contactsCache
            lock.unlock()
            return Array(all.prefix(50))
        }

        let lowerQuery = trimmed.lowercased()
        let phoneNorm = Self.normalizePhone(trimmed)

        lock.lock()
        let all = contactsCache
        lock.unlock()

        return all.filter { card in
            if card.displayName.lowercased().contains(lowerQuery) {
                return true
            }
            for email in card.emailAddresses {
                if email.lowercased().contains(lowerQuery) {
                    return true
                }
            }
            for phone in card.phoneNumbers {
                let cardNorm = Self.normalizePhone(phone)
                if cardNorm.exact.contains(phoneNorm.exact) {
                    return true
                }
                if let qLast10 = phoneNorm.last10, let cLast10 = cardNorm.last10, cLast10 == qLast10 {
                    return true
                }
            }
            return false
        }
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
