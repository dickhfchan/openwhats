import SwiftUI
import OpenWhatsCore

/// A single chat message bubble — sent (teal, right) or received (white/dark, left).
public struct MessageBubble: View {
    let message: Message

    public init(message: Message) {
        self.message = message
    }

    private var isMine: Bool { message.isMine }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: 60) }

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

            if !isMine { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Text bubble

    private var textBubble: some View {
        ZStack(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            Text((message.body ?? "") + messagePadding)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .foregroundStyle(isMine ? Color.primary : Color.primary)

            // Timestamp + ticks overlay at bottom-right
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
        .background(bubbleColor)
        .clipShape(BubbleShape(isMine: isMine))
        .overlay(BubbleShape(isMine: isMine).stroke(Color.clear, lineWidth: 0))
    }

    // Pad the text so the timestamp doesn't overlap
    private var messagePadding: String {
        let pad = isMine ? "        " : "     "
        return pad
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
            : Color(light: .white, dark: Color(hex: "#262D31"))
    }
}

// MARK: - Bubble tail shape

struct BubbleShape: Shape {
    let isMine: Bool
    let radius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tailSize: CGFloat = 8

        if isMine {
            // Rounded rect with flat bottom-right and small tail
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tailSize))
            // Tail pointing right
            path.addLine(to: CGPoint(x: rect.maxX + tailSize, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                        radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Rounded rect with flat bottom-left and small tail
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                        radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                        radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            // Tail pointing left
            path.addLine(to: CGPoint(x: rect.minX - tailSize, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - tailSize))
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
