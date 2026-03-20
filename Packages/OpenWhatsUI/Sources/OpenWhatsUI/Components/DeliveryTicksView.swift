import SwiftUI
import OpenWhatsCore

/// WhatsApp-style delivery tick icons.
/// - `.sending`  → clock icon
/// - `.sent`     → single gray check
/// - `.delivered`→ double gray checks
/// - `.read`     → double blue checks
/// - `.failed`   → red exclamation
public struct DeliveryTicksView: View {
    let status: MessageStatus

    public init(status: MessageStatus) {
        self.status = status
    }

    public var body: some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

        case .delivered:
            doubleCheck(color: .secondary)

        case .read:
            doubleCheck(color: Color(hex: "#4FC3F7"))

        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }

    private func doubleCheck(color: Color) -> some View {
        HStack(spacing: -4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
