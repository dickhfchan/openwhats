import SwiftUI
import OpenWhatsCore

/// A single chat message bubble — sent (teal, right) or received (white/dark, left).
public struct MessageBubble: View {
    let message: Message
    /// Whether this is the last message in a consecutive run from the same sender.
    /// When false, the bubble tail is hidden and corner radius is uniform.
    var isLastInGroup: Bool

    public init(message: Message, isLastInGroup: Bool = true) {
        self.message = message
        self.isLastInGroup = isLastInGroup
    }

    private var isMine: Bool { message.isMine }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Avatar placeholder for received messages
            if !isMine {
                if isLastInGroup {
                    AvatarView(url: nil, name: "?", size: 28)
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }

            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 0) {
                switch message.type {
                case .text:
                    textBubble
                case .image:
                    imageBubble
                case .voice:
                    voiceBubble
                default:
                    textBubble
                }
            }

            if !isMine { Spacer(minLength: 40) }

            // Balance spacing for sent messages (no avatar)
            if isMine { Color.clear.frame(width: 28, height: 28) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isLastInGroup ? 2 : 1)
    }

    // MARK: - Text bubble

    private var textBubble: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 1) {
            Text(message.body ?? "")
                .font(.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 1)

            HStack(spacing: 3) {
                Text(message.timestamp.shortTimeString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if isMine {
                    DeliveryTicksView(status: message.status)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(bubbleColor)
        .clipShape(BubbleShape(isMine: isMine, showTail: isLastInGroup))
    }

    // MARK: - Image bubble

    private var imageBubble: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 220, height: 165)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                )
            timestampRow
        }
        .padding(6)
        .background(bubbleColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Voice bubble

    private var voiceBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 16))
                .foregroundStyle(isMine ? Color.primary : Color.accentColor)

            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 2, height: CGFloat.random(in: 4...16))
                }
            }
            .frame(height: 20)

            Text("0:00")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            timestampRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(bubbleColor)
        .clipShape(BubbleShape(isMine: isMine))
    }

    // MARK: - Helpers

    private var timestampRow: some View {
        HStack(spacing: 3) {
            Text(message.timestamp.shortTimeString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if isMine {
                DeliveryTicksView(status: message.status)
            }
        }
    }

    private var bubbleColor: Color {
        isMine
            ? Color(light: Color(hex: "#DCF8C6"), dark: Color(hex: "#005C4B"))
            : Color(light: Color(hex: "#F0F0F0"), dark: Color(hex: "#262D31"))
    }
}

// MARK: - Bubble tail shape

struct BubbleShape: Shape {
    let isMine: Bool
    var showTail: Bool = true
    let radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        // When no tail, just use uniform rounded rect
        guard showTail else {
            return Path(roundedRect: rect, cornerRadius: radius)
        }

        var path = Path()
        // Bottom corner radius is smaller when showing tail (flatter bottom edge)
        let br: CGFloat = 4

        if isMine {
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                        radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                        radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                        radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + br, y: rect.maxY - br),
                        radius: br, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Color light/dark helper

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColorOrNSColor: {
            #if os(iOS)
            return UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) }
            #else
            return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) }
            #endif
        }())
    }

    #if os(iOS)
    init(uiColorOrNSColor color: UIColor) { self.init(color) }
    #else
    init(uiColorOrNSColor color: NSColor) { self.init(color) }
    #endif
}

// MARK: - Date helpers

extension Date {
    var shortTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f.string(from: self)
    }
}
