import Foundation

enum ConversationStatus {
    static func formatDuration(seconds: Double) -> String {
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

    static func unreplied(
        people: [TrackedPerson],
        latestMessages: [String: LatestMessageInfo],
        dismissedTimestamps: [String: Int64],
        trackingBaselineRawAppleDate: Int64,
        now: Date,
        gracePeriodHours: Double
    ) -> [UnrepliedPerson] {
        let nowUnix = now.timeIntervalSince1970
        let gracePeriodSeconds = gracePeriodHours * 3600.0

        var unrepliedList: [UnrepliedPerson] = []

        for person in people {
            guard let latest = latestMessages[person.id] else {
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
            let formatted = formatDuration(seconds: waitTime)
            let inGrace = waitTime < gracePeriodSeconds
            let chatIdentifier = latest.chatIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let primaryHandle = chatIdentifier.isEmpty ? person.primaryHandle : chatIdentifier

            let unreplied = UnrepliedPerson(
                person: person,
                latestMessage: latest,
                waitTimeSeconds: waitTime,
                formattedDuration: formatted,
                isInGracePeriod: inGrace,
                primaryHandle: primaryHandle
            )
            unrepliedList.append(unreplied)
        }

        // Sort ascending by unix_timestamp (longest waiting / oldest message is #1 at top)
        unrepliedList.sort { $0.latestMessage.unixTimestamp < $1.latestMessage.unixTimestamp }
        return unrepliedList
    }
}
