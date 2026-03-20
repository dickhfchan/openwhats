#if os(macOS)
import SwiftUI
import OpenWhatsCore

/// Detail column — contact info for the selected conversation.
struct macOSContactInfoPanel: View {

    let conversation: Conversation

    @State private var showSecurityCode = false
    @State private var isMuted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    AvatarView(
                        url: conversation.peerAvatarURL.flatMap { URL(string: $0) },
                        name: conversation.peerDisplayName,
                        size: 72
                    )
                    Text(conversation.peerDisplayName)
                        .font(.title3.bold())
                    Text("@\(conversation.peerUserID)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)

                Divider()

                // Quick actions
                HStack(spacing: 32) {
                    IconAction(systemName: "phone.fill", label: "Voice") {
                        // Phase 7
                    }
                    IconAction(systemName: "video.fill", label: "Video") {
                        // Phase 7
                    }
                    IconAction(systemName: isMuted ? "bell.slash.fill" : "bell.fill",
                               label: isMuted ? "Unmute" : "Mute") {
                        isMuted.toggle()
                    }
                }
                .padding(.vertical, 20)

                Divider()

                // Security
                Button {
                    showSecurityCode = true
                } label: {
                    HStack {
                        Label("Encryption", systemImage: "lock.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Divider()

                // Destructive
                Button(role: .destructive) {
                    // Phase 8: delete conversation
                } label: {
                    HStack {
                        Label("Delete Chat", systemImage: "trash")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .sheet(isPresented: $showSecurityCode) {
            macOSSecurityCodeView(conversation: conversation)
        }
    }
}

private struct IconAction: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct macOSSecurityCodeView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Security Code")
                .font(.headline)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 160, height: 160)
                .overlay(
                    Image(systemName: "qrcode")
                        .font(.system(size: 80))
                        .foregroundStyle(.secondary)
                )

            Text("60 83 19 42 77 25 31 64\n09 88 52 16 40 73 57 29\n11 36 90 44 68 03 85 12")
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.center)

            Text("If the codes above match your contact's device, your conversation is end-to-end encrypted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 360)
    }
}
#endif
