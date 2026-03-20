#if os(iOS)
import SwiftUI
import OpenWhatsCore

/// Contact/Conversation info — avatar, name, security code, mute, delete.
public struct ConversationInfoView: View {

    let conversation: Conversation

    @State private var isMuted = false
    @State private var showSecurityCode = false
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    public init(conversation: Conversation) {
        self.conversation = conversation
    }

    public var body: some View {
        List {
            // Header — avatar + name
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        AvatarView(
                            url: conversation.peerAvatarURL.flatMap { URL(string: $0) },
                            name: conversation.peerDisplayName,
                            size: 80
                        )
                        Text(conversation.peerDisplayName)
                            .font(.title2.weight(.semibold))
                        Text("@\(conversation.peerUserID)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 16)
            }

            // Quick actions
            Section {
                HStack(spacing: 20) {
                    Spacer()
                    ActionButton(icon: "phone.fill", label: "Voice") { /* Phase 7 */ }
                    ActionButton(icon: "video.fill", label: "Video") { /* Phase 7 */ }
                    ActionButton(icon: "bell.slash.fill", label: isMuted ? "Unmute" : "Mute") {
                        isMuted.toggle()
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Security
            Section("Encryption") {
                Button {
                    showSecurityCode = true
                } label: {
                    Label("Security Code", systemImage: "lock.shield.fill")
                        .foregroundStyle(.primary)
                }
            }

            // Media — placeholder
            Section("Media, Links and Docs") {
                Label("0 Items", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(.secondary)
            }

            // Danger zone
            Section {
                Toggle(isOn: $isMuted) {
                    Label("Mute Notifications", systemImage: "bell.slash")
                }

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Conversation", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Contact Info")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSecurityCode) {
            SecurityCodeView(
                peerName: conversation.peerDisplayName,
                peerUserID: conversation.peerUserID
            )
        }
        .alert("Delete Conversation?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all messages with \(conversation.peerDisplayName). This action cannot be undone.")
        }
    }
}

// MARK: - Quick action button

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 50, height: 50)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Security code screen

struct SecurityCodeView: View {
    let peerName: String
    let peerUserID: String
    @Environment(\.dismiss) private var dismiss

    // Placeholder — real safety numbers from SafetyNumbers.compute() in Phase 9
    var safetyNumber: String {
        "12345 67890 12345\n67890 12345 67890\n12345 67890 12345\n67890 12345 67890"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "qrcode")
                    .font(.system(size: 120))
                    .foregroundStyle(Color.primary)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text("Security Code with \(peerName)")
                        .font(.headline)
                    Text(safetyNumber)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text("Verify this code with \(peerName) to confirm your messages are end-to-end encrypted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Security Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ConversationInfoView(conversation: Conversation.previews[0])
    }
}
#endif
