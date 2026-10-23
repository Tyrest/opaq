import SwiftUI

struct PersonRowView: View {
    let item: UnrepliedPerson
    let isMuted: Bool
    let onReply: () -> Void
    let onDismiss: () -> Void

    init(
        item: UnrepliedPerson,
        isMuted: Bool = false,
        onReply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.isMuted = isMuted
        self.onReply = onReply
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onReply) {
                ContactIdentityRow(
                    name: item.person.displayName,
                    detail: item.primaryHandle,
                    avatarData: item.person.avatarData,
                    cacheKey: item.person.id,
                    size: 28,
                    isMuted: isMuted
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.person.displayName), waiting \(item.formattedDuration)")
            .accessibilityHint("Opens this conversation in Messages")

            Text(item.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(durationColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(durationColor.opacity(0.16), in: Capsule())
                .accessibilityLabel("Waiting \(item.formattedDuration)")

            Button(action: onDismiss) {
                Image(systemName: "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Conversation ended naturally (don't count as ghosting)")
            .accessibilityLabel("Mark conversation as ended")
        }
        .contextMenu {
            Button("Reply in Messages", action: onReply)
            Button("Conversation Ended", action: onDismiss)
        }
    }

    private var durationColor: Color {
        if isMuted { return .secondary }
        switch item.urgency {
        case .normal: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
