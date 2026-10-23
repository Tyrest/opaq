import XCTest

@testable import opaq

final class ConversationStatusTests: XCTestCase {
    func testFormatDuration() {
        XCTAssertEqual(ConversationStatus.formatDuration(seconds: 30), "now")
        XCTAssertEqual(ConversationStatus.formatDuration(seconds: 90), "1m")
        XCTAssertEqual(ConversationStatus.formatDuration(seconds: 3600), "1h")
        XCTAssertEqual(ConversationStatus.formatDuration(seconds: 3660), "1h 1m")
        XCTAssertEqual(ConversationStatus.formatDuration(seconds: 86400), "1d")
        XCTAssertEqual(ConversationStatus.formatDuration(seconds: 90000), "1d 1h")
    }

    func testUnrepliedFilteringGraceSortAndHandle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline: Int64 = 200

        let fromMe = person(id: "from-me", handle: "from-me@example.com")
        let dismissedEqual = person(id: "dismissed-equal", handle: "dismissed-equal@example.com")
        let dismissedOlder = person(id: "dismissed-older", handle: "dismissed-older@example.com")
        let baselineEqual = person(id: "baseline-equal", handle: "baseline-equal@example.com")
        let baselineOlder = person(id: "baseline-older", handle: "baseline-older@example.com")
        let recent = person(id: "recent", handle: "recent@example.com")
        let waiting = person(id: "waiting", handle: "waiting@example.com")

        let messages: [String: LatestMessageInfo] = [
            fromMe.id: message(
                chat: "+15550000001",
                fromMe: true,
                raw: 5_000,
                unix: now.timeIntervalSince1970 - 50_000
            ),
            dismissedEqual.id: message(
                chat: "+15550000002",
                fromMe: false,
                raw: 400,
                unix: now.timeIntervalSince1970 - 40_000
            ),
            dismissedOlder.id: message(
                chat: "+15550000003",
                fromMe: false,
                raw: 300,
                unix: now.timeIntervalSince1970 - 30_000
            ),
            baselineEqual.id: message(
                chat: "+15550000004",
                fromMe: false,
                raw: baseline,
                unix: now.timeIntervalSince1970 - 20_000
            ),
            baselineOlder.id: message(
                chat: "+15550000005",
                fromMe: false,
                raw: baseline - 1,
                unix: now.timeIntervalSince1970 - 15_000
            ),
            recent.id: message(
                chat: "+15550000006",
                fromMe: false,
                raw: 1_000,
                unix: now.timeIntervalSince1970 - 3_600
            ),
            waiting.id: message(
                chat: "+15550000007",
                fromMe: false,
                raw: 900,
                unix: now.timeIntervalSince1970 - 10_800
            ),
        ]

        let results = ConversationStatus.unreplied(
            people: [
                recent, fromMe, dismissedEqual, waiting, dismissedOlder, baselineEqual,
                baselineOlder,
            ],
            latestMessages: messages,
            dismissedTimestamps: [
                dismissedEqual.id: 400,
                dismissedOlder.id: 500,
            ],
            trackingBaselineRawAppleDate: baseline,
            now: now,
            gracePeriodHours: 2
        )

        XCTAssertEqual(results.map(\.person.id), ["waiting", "recent"])
        XCTAssertFalse(results[0].isInGracePeriod)
        XCTAssertTrue(results[1].isInGracePeriod)
        XCTAssertLessThan(
            results[0].latestMessage.unixTimestamp,
            results[1].latestMessage.unixTimestamp
        )
        XCTAssertEqual(results[0].primaryHandle, results[0].latestMessage.chatIdentifier)
        XCTAssertEqual(results[1].primaryHandle, results[1].latestMessage.chatIdentifier)
        XCTAssertNotEqual(results[0].primaryHandle, waiting.primaryHandle)
    }

    func testUrgencyThresholds() {
        XCTAssertEqual(unreplied(waitHours: 23).urgency, .normal)
        XCTAssertEqual(unreplied(waitHours: 25).urgency, .warning)
        XCTAssertEqual(unreplied(waitHours: 73).urgency, .critical)
    }

    private func person(id: String, handle: String) -> TrackedPerson {
        TrackedPerson(id: id, displayName: id, handles: [handle])
    }

    private func message(chat: String, fromMe: Bool, raw: Int64, unix: Double) -> LatestMessageInfo {
        LatestMessageInfo(
            chatIdentifier: chat,
            messageId: raw,
            isFromMe: fromMe,
            rawAppleDate: raw,
            unixTimestamp: unix
        )
    }

    private func unreplied(waitHours: Double) -> UnrepliedPerson {
        let tracked = person(id: "pat", handle: "pat@example.com")
        let latest = message(chat: "+15551230000", fromMe: false, raw: 1, unix: 0)
        return UnrepliedPerson(
            person: tracked,
            latestMessage: latest,
            waitTimeSeconds: waitHours * 3600,
            formattedDuration: "x",
            isInGracePeriod: false,
            primaryHandle: latest.chatIdentifier
        )
    }

    func testTrackedPersonPersistenceOmitsAvatar() throws {
        let person = TrackedPerson(
            id: "contact-1",
            displayName: "Ada",
            handles: ["+15551234567"],
            avatarData: Data([1, 2, 3])
        )
        let data = try JSONEncoder().encode(person)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("avatar"))

        let decoded = try JSONDecoder().decode(TrackedPerson.self, from: data)
        XCTAssertNil(decoded.avatarData)
        XCTAssertEqual(decoded.handles, ["+15551234567"])

        let legacy = Data(
            #"{"id":"contact-1","displayName":"Ada","handles":["+15551234567"],"avatarData":"AQID"}"#
                .utf8
        )
        let decodedLegacy = try JSONDecoder().decode(TrackedPerson.self, from: legacy)
        XCTAssertEqual(decodedLegacy.displayName, "Ada")
        XCTAssertNil(decodedLegacy.avatarData)
    }
}
