import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class DatabaseService: @unchecked Sendable {
    public static let shared = DatabaseService()

    public static var defaultDbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path
    }

    public static var defaultWalPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db-wal")
            .path
    }

    private let dbPath: String

    public init(dbPath: String = DatabaseService.defaultDbPath) {
        self.dbPath = dbPath
    }

    // MARK: - Permission Verification

    public func checkFullDiskAccess() -> Bool {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db = db else {
            if let db = db { sqlite3_close(db) }
            return false
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT 1 FROM message LIMIT 1;"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let stepResult = sqlite3_step(stmt)
        return stepResult == SQLITE_ROW || stepResult == SQLITE_DONE
    }

    // MARK: - Safe Database Helper

    private func openDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &db, flags, nil)
        guard rc == SQLITE_OK, let validDb = db else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        return validDb
    }

    // MARK: - Query A: Chat Discovery & Suggestions

    public func fetchAllChatPeople(
        contactManager: ContactManager = .shared
    ) -> [DiscoveredPersonRecord] {
        guard let db = openDatabase() else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT 
            h.id AS handle_identifier,
            COUNT(m.ROWID) AS total_messages,
            SUM(
                1.0 / (1.0 + ((strftime('%s', 'now') - (m.date / 1000000000 + 978307200)) / 86400.0) * 0.1)
            ) AS recency_weighted_score
        FROM message m
        JOIN handle h ON m.handle_id = h.ROWID
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE c.style = 45 
        GROUP BY h.id
        ORDER BY recency_weighted_score DESC
        LIMIT 500;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        struct RawChatPartner {
            let handle: String
            let totalMessages: Int
            let score: Double
        }

        var rawList: [RawChatPartner] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let handle = String(cString: cStr)
            let total = Int(sqlite3_column_int(stmt, 1))
            let score = sqlite3_column_double(stmt, 2)
            rawList.append(RawChatPartner(handle: handle, totalMessages: total, score: score))
        }

        // Group discovered handles by CNContact.identifier or individual normalized handle
        var grouped: [String: (person: TrackedPerson, total: Int, score: Double)] = [:]

        for raw in rawList {
            let rawNorm = ContactManager.normalizeHandle(raw.handle)

            if let card = contactManager.findContact(for: raw.handle) {
                if var existing = grouped[card.id] {
                    var handles = Set(existing.person.handles)
                    handles.insert(raw.handle)
                    for h in card.allHandles { handles.insert(h) }
                    existing.person.handles = Array(handles)
                    existing.total += raw.totalMessages
                    existing.score += raw.score
                    grouped[card.id] = existing
                } else {
                    var handles = Set(card.allHandles)
                    handles.insert(raw.handle)
                    let person = TrackedPerson(
                        id: card.id,
                        displayName: card.displayName,
                        handles: Array(handles),
                        avatarData: card.avatarData
                    )
                    grouped[card.id] = (person: person, total: raw.totalMessages, score: raw.score)
                }
            } else {
                // No contact card found; group by normalized handle
                let key = rawNorm
                if var existing = grouped[key] {
                    var handles = Set(existing.person.handles)
                    handles.insert(raw.handle)
                    existing.person.handles = Array(handles)
                    existing.total += raw.totalMessages
                    existing.score += raw.score
                    grouped[key] = existing
                } else {
                    let person = TrackedPerson(
                        id: key,
                        displayName: raw.handle,
                        handles: [raw.handle],
                        avatarData: nil
                    )
                    grouped[key] = (person: person, total: raw.totalMessages, score: raw.score)
                }
            }
        }

        return grouped.values
            .map { DiscoveredPersonRecord(person: $0.person, totalMessages: $0.total, recencyWeightedScore: $0.score) }
            .sorted { $0.recencyWeightedScore > $1.recencyWeightedScore }
    }

    public func fetchTimeDecayedSuggestions(
        trackedPeople: [TrackedPerson],
        contactManager: ContactManager = .shared
    ) -> [SuggestedPerson] {
        let allDiscovered = fetchAllChatPeople(contactManager: contactManager)

        // Build set of currently tracked IDs and handles
        var trackedIds = Set<String>()
        var trackedHandles = Set<String>()
        for person in trackedPeople {
            trackedIds.insert(person.id)
            for h in person.handles {
                trackedHandles.insert(h)
                let norm = ContactManager.normalizeHandle(h)
                trackedHandles.insert(norm)
                let phoneNorm = ContactManager.normalizePhone(h)
                if !phoneNorm.exact.isEmpty { trackedHandles.insert(phoneNorm.exact) }
                if let last10 = phoneNorm.last10 { trackedHandles.insert(last10) }
            }
        }

        return allDiscovered.compactMap { record in
            if trackedIds.contains(record.person.id) { return nil }
            for h in record.person.handles {
                let norm = ContactManager.normalizeHandle(h)
                let phoneNorm = ContactManager.normalizePhone(h)
                if trackedHandles.contains(h) || trackedHandles.contains(norm) {
                    return nil
                }
                if let last10 = phoneNorm.last10, trackedHandles.contains(last10) {
                    return nil
                }
            }
            return SuggestedPerson(
                person: record.person,
                totalMessages: record.totalMessages,
                recencyWeightedScore: record.recencyWeightedScore
            )
        }
    }

    // MARK: - Query B: Unreplied Status Across Tracked People

    public func fetchLatestMessages(for people: [TrackedPerson]) -> [String: LatestMessageInfo] {
        guard !people.isEmpty else { return [:] }
        guard let db = openDatabase() else { return [:] }
        defer { sqlite3_close(db) }

        var results: [String: LatestMessageInfo] = [:]
        for person in people {
            if let latest = fetchLatestMessageInternal(db: db, for: person) {
                results[person.id] = latest
            }
        }
        return results
    }

    public func fetchLatestMessage(for person: TrackedPerson) -> LatestMessageInfo? {
        guard let db = openDatabase() else { return nil }
        defer { sqlite3_close(db) }
        return fetchLatestMessageInternal(db: db, for: person)
    }

    private func fetchLatestMessageInternal(db: OpaquePointer, for person: TrackedPerson) -> LatestMessageInfo? {
        // Expand handles to match various chat_identifier formats in chat.db
        var candidateHandles = Set<String>()
        for h in person.handles {
            let trimmed = h.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            candidateHandles.insert(trimmed)

            if ContactManager.isEmail(trimmed) {
                candidateHandles.insert(ContactManager.normalizeEmail(trimmed))
            } else {
                let phoneNorm = ContactManager.normalizePhone(trimmed)
                if !phoneNorm.exact.isEmpty {
                    candidateHandles.insert(phoneNorm.exact)
                    if phoneNorm.exact.hasPrefix("+") {
                        candidateHandles.insert(String(phoneNorm.exact.dropFirst()))
                    } else {
                        candidateHandles.insert("+" + phoneNorm.exact)
                    }
                }
                if let last10 = phoneNorm.last10 {
                    candidateHandles.insert(last10)
                    candidateHandles.insert("+1" + last10)
                    candidateHandles.insert("1" + last10)
                }
            }
        }

        let handlesArray = Array(candidateHandles)
        guard !handlesArray.isEmpty else { return nil }

        let placeholders = handlesArray.map { _ in "?" }.joined(separator: ", ")

        let sql = """
        SELECT 
            c.chat_identifier,
            m.ROWID AS message_id,
            m.is_from_me,
            m.date AS raw_apple_date,
            (m.date / 1000000000 + 978307200) AS unix_timestamp
        FROM chat c
        JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
        JOIN message m ON cmj.message_id = m.ROWID
        WHERE c.style = 45
          AND c.chat_identifier IN (\(placeholders))
          AND m.item_type = 0
          AND m.associated_message_type NOT BETWEEN 3000 AND 3005
          AND NOT (m.is_from_me = 0 AND m.associated_message_type BETWEEN 2000 AND 2005)
        ORDER BY m.date DESC
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        for (index, handle) in handlesArray.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), handle, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let chatIdentifier = String(cString: sqlite3_column_text(stmt, 0))
            let messageId = sqlite3_column_int64(stmt, 1)
            let isFromMe = sqlite3_column_int(stmt, 2) != 0
            let rawAppleDate = sqlite3_column_int64(stmt, 3)
            let unixTimestamp = sqlite3_column_double(stmt, 4)

            return LatestMessageInfo(
                chatIdentifier: chatIdentifier,
                messageId: messageId,
                isFromMe: isFromMe,
                rawAppleDate: rawAppleDate,
                unixTimestamp: unixTimestamp
            )
        }

        return nil
    }
}
