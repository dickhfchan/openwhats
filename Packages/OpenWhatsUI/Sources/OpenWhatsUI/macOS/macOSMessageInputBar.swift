#if os(macOS)
import SwiftUI

/// Compose bar for macOS — TextEditor with ⌘↩ to send, attachment button.
struct macOSMessageInputBar: View {

    @Binding var text: String
    var onSend: () -> Void
    var onAttach: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Attachment
            Button(action: onAttach) {
                Image(systemName: "paperclip")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 9)
            .help("Attach File")

            // Text area
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Message")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .frame(minHeight: 36, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .onKeyPress(.return, phases: .down) { event in
                        // ⌘↩ sends; plain ↩ inserts newline
                        if event.modifiers.contains(.command) {
                            onSend()
                            return .handled
                        }
                        return .ignored
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )

            // Send
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Color.secondary.opacity(0.4)
                                     : Color.owGreen)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.bottom, 5)
            .help("Send (⌘↩)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { isFocused = true }
    }
}
#endif
