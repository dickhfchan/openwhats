#if os(macOS)
import SwiftUI
import OpenWhatsCore

/// Left column of the macOS split view — conversation list.
struct SidebarView: View {

    let conversations: [Conversation]
    @Binding var selection: Conversation?

    var body: some View {
        List(conversations, selection: $selection) { conversation in
            ConversationRow(conversation: conversation, compact: true)
                .tag(conversation)
                .contextMenu {
                    Button(role: .destructive) {
                        if selection?.id == conversation.id { selection = nil }
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                    }

                    Button {
                        // Phase 8: archive
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }

                    Divider()

                    Button {
                        // Phase 7: mute
                    } label: {
                        Label("Mute Notifications", systemImage: "bell.slash")
                    }
                }
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenWhats")
    }
}
#endif
