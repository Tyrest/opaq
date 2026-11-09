import AppKit
import SwiftUI

struct AvatarView: View {
    let name: String
    let avatarData: Data?
    let cacheKey: String?
    let size: CGFloat

    init(name: String, avatarData: Data? = nil, cacheKey: String? = nil, size: CGFloat = 32) {
        self.name = name
        self.avatarData = avatarData
        self.cacheKey = cacheKey
        self.size = size
    }

    var body: some View {
        Group {
            if let nsImage = cachedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initialsForName(name))
                            // shortcut: diameter * 0.5 matches Contacts at the 28pt rows we draw; use its stepped sizes if avatars exceed 32pt
                            .font(.system(size: size * 0.5, weight: .regular))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var cachedImage: NSImage? {
        guard let data = avatarData, !data.isEmpty else { return nil }
        let key = (cacheKey ?? "\(data.count)") as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(data: data) else { return nil }
        Self.imageCache.setObject(image, forKey: key)
        return image
    }

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

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
}
