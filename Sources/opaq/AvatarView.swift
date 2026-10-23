import SwiftUI
import AppKit

public struct AvatarView: View {
    public let name: String
    public let avatarData: Data?
    public let size: CGFloat

    public init(name: String, avatarData: Data? = nil, size: CGFloat = 32) {
        self.name = name
        self.avatarData = avatarData
        self.size = size
    }

    public var body: some View {
        Group {
            if let data = avatarData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(gradientForName(name))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initialsForName(name))
                            .font(.system(size: max(9, size * 0.38), weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func initialsForName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        if trimmed.hasPrefix("+") || trimmed.first?.isNumber == true {
            return "#"
        }

        let parts = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        } else if let first = parts.first, !first.isEmpty {
            return String(first.prefix(1)).uppercased()
        }
        return "?"
    }

    private func gradientForName(_ name: String) -> LinearGradient {
        var hash: Int = 0
        for u in name.unicodeScalars {
            hash = (hash &<< 5) &- hash &+ Int(u.value)
        }

        let palettes: [[Color]] = [
            [Color(red: 0.40, green: 0.45, blue: 0.95), Color(red: 0.58, green: 0.40, blue: 0.96)],
            [Color(red: 0.20, green: 0.60, blue: 0.92), Color(red: 0.35, green: 0.44, blue: 0.92)],
            [Color(red: 0.88, green: 0.36, blue: 0.56), Color(red: 0.65, green: 0.30, blue: 0.88)],
            [Color(red: 0.15, green: 0.68, blue: 0.60), Color(red: 0.14, green: 0.55, blue: 0.75)],
            [Color(red: 0.92, green: 0.50, blue: 0.28), Color(red: 0.88, green: 0.30, blue: 0.42)],
            [Color(red: 0.50, green: 0.40, blue: 0.92), Color(red: 0.80, green: 0.35, blue: 0.70)],
            [Color(red: 0.30, green: 0.72, blue: 0.65), Color(red: 0.20, green: 0.52, blue: 0.85)],
        ]

        let pair = palettes[abs(hash) % palettes.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
