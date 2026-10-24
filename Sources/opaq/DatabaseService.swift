import Foundation
import SQLite3

struct DatabaseFailure: Error, Equatable {
    var message: String
}

final class DatabaseService: Sendable {
    static let shared = DatabaseService()

    static var defaultDbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path
    }

    static var defaultWalPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db-wal")
            .path
    }

    private let dbPath: String

    init(dbPath: String = DatabaseService.defaultDbPath) {
        self.dbPath = dbPath
    }

    // MARK: - Permission Verification

    func checkFullDiskAccess() -> Bool {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &opened, flags, nil)
        guard rc == SQLITE_OK, let db = opened else {
            if let opened {
                let message = String(cString: sqlite3_errmsg(opened))
                Log.database.debug("full disk access check failed: \(message, privacy: .public)")
                sqlite3_close(opened)
            } else {
                Log.database.debug("full disk access check failed: unable to open database")
            }
            return false
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT 1 FROM message LIMIT 1;"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            Log.database.debug("full disk access check failed: \(message, privacy: .public)")
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let stepResult = sqlite3_step(stmt)
        if stepResult == SQLITE_ROW || stepResult == SQLITE_DONE {
            return true
        }
        let message = String(cString: sqlite3_errmsg(db))
        Log.database.debug("full disk access check failed: \(message, privacy: .public)")
        return false
    }

    // MARK: - Safe Database Helper

    private func openDatabase() throws -> OpaquePointer {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &opened, flags, nil)
        guard rc == SQLITE_OK, let db = opened else {
            let failure = makeFailure(db: opened, context: "open")
            if let opened {
                sqlite3_close(opened)
            }
            throw failure
        }
        return db
    }

    private func prepare(_ db: OpaquePointer, sql: String, context: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw makeFailure(db: db, context: context)
        }
        return stmt
    }

    private func makeFailure(db: OpaquePointer?, context: String) -> DatabaseFailure {
        let message: String
        if let db {
            message = String(cString: sqlite3_errmsg(db))
        } else {
            message = "unknown sqlite error"
        }
        Log.database.error("\(context, privacy: .public): \(message, privacy: .public)")
        return DatabaseFailure(message: message)
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    /// Phones, then emails, then previously seen handles, then this chat.db handle.
    private static func mergedHandles(existing: [String], card: ContactCard?, rawHandle: String) -> [String] {
        var handles: [String] = []
        func appendUnique(_ handle: String) {
            if !handles.contains(handle) {
                handles.append(handle)
            }
        }
        if let card {
            for phone in card.phoneNumbers {
                appendUnique(phone)
            }
            for email in card.emailAddresses {
                appendUnique(email)
            }
        }
        for handle in existing {
            appendUnique(handle)
        }
        appendUnique(rawHandle)
        return handles
    }

    // MARK: - Query A: Chat Discovery & Suggestions

    func fetchAllChatPeople(contactManager: ContactManager = .shared) throws -> [SuggestedPerson] {
        let db = try openDatabase()
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

        let stmt = try prepare(db, sql: sql, context: "prepare chat people")
        defer { sqlite3_finalize(stmt) }

        struct RawChatPartner {
            let handle: String
            let totalMessages: Int
            let score: Double
        }

        var rawList: [RawChatPartner] = []
        while true {
            let stepRC = sqlite3_step(stmt)
            if stepRC == SQLITE_DONE { break }
            guard stepRC == SQLITE_ROW else {
                throw makeFailure(db: db, context: "step chat people")
            }
            let handle = Self.columnText(stmt, 0)
            if handle.isEmpty { continue }
            let total = Int(sqlite3_column_int(stmt, 1))
            let score = sqlite3_column_double(stmt, 2)
            rawList.append(RawChatPartner(handle: handle, totalMessages: total, score: score))
        }

        struct GroupedChat {
            var person: TrackedPerson
            var total: Int
            var score: Double
        }

        var grouped: [String: GroupedChat] = [:]

        for raw in rawList {
            let card = contactManager.findContact(for: raw.handle)
            let key = card?.id ?? ContactManager.normalizeHandle(raw.handle)
            let existing = grouped[key]
            let handles = Self.mergedHandles(
                existing: existing?.person.handles ?? [],
                card: card,
                rawHandle: raw.handle
            )
            let displayName = existing?.person.displayName ?? card?.displayName ?? raw.handle
            let person = TrackedPerson(
                id: key,
                displayName: displayName,
                handles: handles,
                avatarData: card?.avatarData
            )
            if var existing {
                existing.person = person
                existing.total += raw.totalMessages
                existing.score += raw.score
                grouped[key] = existing
            } else {
                grouped[key] = GroupedChat(person: person, total: raw.totalMessages, score: raw.score)
            }
        }

        return grouped.values
            .map { SuggestedPerson(person: $0.person, totalMessages: $0.total, recencyWeightedScore: $0.score) }
            .sorted { $0.recencyWeightedScore > $1.recencyWeightedScore }
    }

    func fetchTimeDecayedSuggestions(
        trackedPeople: [TrackedPerson],
        contactManager: ContactManager = .shared
    ) throws -> [SuggestedPerson] {
        let allDiscovered = try fetchAllChatPeople(contactManager: contactManager)

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
            return record
        }
    }

    // MARK: - Query B: Unreplied Status Across Tracked People

    func fetchLatestMessagesByChatIdentifier() throws -> [String: LatestMessageInfo] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            WITH ranked AS (
              SELECT
                c.chat_identifier AS chat_identifier,
                m.ROWID AS message_id,
                m.is_from_me AS is_from_me,
                m.date AS raw_apple_date,
                (m.date / 1000000000 + 978307200) AS unix_timestamp,
                ROW_NUMBER() OVER (PARTITION BY c.ROWID ORDER BY m.date DESC) AS rn
              FROM chat c
              JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
              JOIN message m ON cmj.message_id = m.ROWID
              WHERE c.style = 45
                AND m.item_type = 0
                AND m.associated_message_type NOT BETWEEN 3000 AND 3005
                AND NOT (m.is_from_me = 0 AND m.associated_message_type BETWEEN 2000 AND 2005)
            )
            SELECT chat_identifier, message_id, is_from_me, raw_apple_date, unix_timestamp
            FROM ranked
            WHERE rn = 1;
            """

        let stmt = try prepare(db, sql: sql, context: "prepare latest messages")
        defer { sqlite3_finalize(stmt) }

        var results: [String: LatestMessageInfo] = [:]
        while true {
            let stepRC = sqlite3_step(stmt)
            if stepRC == SQLITE_DONE { break }
            guard stepRC == SQLITE_ROW else {
                throw makeFailure(db: db, context: "step latest messages")
            }

            let info = LatestMessageInfo(
                chatIdentifier: Self.columnText(stmt, 0),
                messageId: sqlite3_column_int64(stmt, 1),
                isFromMe: sqlite3_column_int(stmt, 2) != 0,
                rawAppleDate: sqlite3_column_int64(stmt, 3),
                unixTimestamp: sqlite3_column_double(stmt, 4)
            )
            if let existing = results[info.chatIdentifier], existing.rawAppleDate >= info.rawAppleDate {
                continue
            }
            results[info.chatIdentifier] = info
        }
        return results
    }

    func fetchLatestMessages(for people: [TrackedPerson]) throws -> [String: LatestMessageInfo] {
        guard !people.isEmpty else { return [:] }
        let byChat = try fetchLatestMessagesByChatIdentifier()

        var results: [String: LatestMessageInfo] = [:]
        for person in people {
            var best: LatestMessageInfo?
            for handle in candidateHandles(for: person) {
                guard let info = byChat[handle] else { continue }
                if let current = best, current.rawAppleDate >= info.rawAppleDate {
                    continue
                }
                best = info
            }
            if let best {
                results[person.id] = best
            }
        }
        return results
    }

    /// Exact handle, email folding, and phone variants (exact, +/- prefix, last 10, +1 / 1).
    private func candidateHandles(for person: TrackedPerson) -> Set<String> {
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
        return candidateHandles
    }
}
