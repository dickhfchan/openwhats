import SwiftUI

/// Circular avatar — shows remote image if available, falls back to initials.
public struct AvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    public init(url: URL?, name: String, size: CGFloat = 40) {
        self.url = url
        self.name = name
        self.size = size
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.avatarBackground(for: name))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

private extension Color {
    static func avatarBackground(for name: String) -> Color {
        let palette: [Color] = [
            Color(hue: 0.03, saturation: 0.7, brightness: 0.8),
            Color(hue: 0.10, saturation: 0.7, brightness: 0.8),
            Color(hue: 0.33, saturation: 0.5, brightness: 0.6),
            Color(hue: 0.55, saturation: 0.6, brightness: 0.7),
            Color(hue: 0.65, saturation: 0.6, brightness: 0.7),
            Color(hue: 0.75, saturation: 0.5, brightness: 0.6),
            Color(hue: 0.85, saturation: 0.6, brightness: 0.7),
        ]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }
}
