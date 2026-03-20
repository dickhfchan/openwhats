#if os(iOS)
import SwiftUI

/// The pinned input bar at the bottom of the chat view.
/// - When text is empty: shows mic button (hold to record)
/// - When text is non-empty: shows send button
public struct MessageInputBar: View {

    @Binding var text: String
    let onSend: () -> Void
    let onAttach: () -> Void
    let onVoice: () -> Void

    @FocusState private var focused: Bool
    @State private var isRecording = false

    public init(
        text: Binding<String>,
        onSend: @escaping () -> Void,
        onAttach: @escaping () -> Void,
        onVoice: @escaping () -> Void
    ) {
        self._text = text
        self.onSend = onSend
        self.onAttach = onAttach
        self.onVoice = onVoice
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Attachment button
            Button(action: onAttach) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.owGreen)
            }

            // Multi-line text field
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Message")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .frame(minHeight: 36, maxHeight: 120)
                    .padding(.horizontal, 4)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Send or Mic button
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Voice record button — long press
                Button(action: {}) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.owGreen)
                        .clipShape(Circle())
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onChanged { _ in isRecording = true }
                        .onEnded { _ in
                            isRecording = false
                            onVoice()
                        }
                )
            } else {
                Button(action: {
                    onSend()
                    focused = false
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.owGreen)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.25), value: text.isEmpty)
    }
}

#Preview {
    VStack {
        Spacer()
        MessageInputBar(text: .constant(""), onSend: {}, onAttach: {}, onVoice: {})
        MessageInputBar(text: .constant("Hello world"), onSend: {}, onAttach: {}, onVoice: {})
    }
    .background(Color(.systemBackground))
}
#endif
