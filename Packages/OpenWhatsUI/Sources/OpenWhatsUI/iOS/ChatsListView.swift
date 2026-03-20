#if os(iOS)
import SwiftUI
import OpenWhatsCore

public struct ChatsListView: View {

    @State private var conversations: [Conversation] = Conversation.previews
    @State private var searchText = ""
    @State private var showNewChat = false

    public init() {}

    private var filtered: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.peerDisplayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { conversation in
                    NavigationLink(destination: ChatView(conversation: conversation)) {
                        ConversationRow(conversation: conversation)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .onDelete(perform: deleteConversations)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showNewChat) {
                ContactSearchView()
            }
            .refreshable {
                // Phase 5: pull-to-refresh fetches pending messages
            }
        }
    }

    private func deleteConversations(at offsets: IndexSet) {
        conversations.remove(atOffsets: offsets)
    }
}

#Preview {
    ChatsListView()
}
#endif
