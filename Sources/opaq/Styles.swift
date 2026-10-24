import SwiftUI

// MARK: - Settings Pane

enum SettingsPane: Int, Hashable, CaseIterable {
    case people
    case quietHours
    case general

    var title: String {
        switch self {
        case .people: return "People"
        case .quietHours: return "Quiet Hours"
        case .general: return "General"
        }
    }

    var systemImage: String {
        switch self {
        case .people: return "person.2"
        case .quietHours: return "moon"
        case .general: return "gearshape"
        }
    }
}

// MARK: - Contact Identity

struct ContactIdentityRow: View {
    let name: String
    let detail: String
    let avatarData: Data?
    var cacheKey: String?
    var size: CGFloat
    var isMuted: Bool

    init(
        name: String,
        detail: String,
        avatarData: Data? = nil,
        cacheKey: String? = nil,
        size: CGFloat = 28,
        isMuted: Bool = false
    ) {
        self.name = name
        self.detail = detail
        self.avatarData = avatarData
        self.cacheKey = cacheKey
        self.size = size
        self.isMuted = isMuted
    }

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: name, avatarData: avatarData, cacheKey: cacheKey, size: size)
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
