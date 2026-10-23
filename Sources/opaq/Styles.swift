import SwiftUI

// MARK: - Settings Pane

public enum SettingsPane: Int, Hashable, CaseIterable {
    case people
    case quietHours
    case general
}

// MARK: - Ghost Icon Button Style

public struct GhostIconButtonStyle: ButtonStyle {
    public var size: CGFloat
    public var cornerRadius: CGFloat

    public init(size: CGFloat = 22, cornerRadius: CGFloat = 6) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        GhostIconButtonBody(configuration: configuration, size: size, cornerRadius: cornerRadius)
    }

    private struct GhostIconButtonBody: View {
        let configuration: Configuration
        let size: CGFloat
        let cornerRadius: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(backgroundColor)
                )
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }

        private var backgroundColor: Color {
            if configuration.isPressed {
                return Color.primary.opacity(0.12)
            }
            return isHovered ? Color.primary.opacity(0.07) : Color.clear
        }
    }
}

// MARK: - Contact Identity

public struct ContactIdentityRow: View {
    public let name: String
    public let detail: String
    public let avatarData: Data?
    public var size: CGFloat
    public var isMuted: Bool

    public init(
        name: String,
        detail: String,
        avatarData: Data? = nil,
        size: CGFloat = 28,
        isMuted: Bool = false
    ) {
        self.name = name
        self.detail = detail
        self.avatarData = avatarData
        self.size = size
        self.isMuted = isMuted
    }

    public var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: name, avatarData: avatarData, size: size)
                .opacity(isMuted ? 0.7 : 1.0)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(isMuted ? .secondary : .primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
