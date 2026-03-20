#if os(macOS)
import SwiftUI
import OpenWhatsCore

/// Root window for macOS — three-column NavigationSplitView.
/// Sidebar: conversation list
/// Content: active chat
/// Detail: contact info panel (collapsible)
public struct AppSplitView: View {

    @State private var selectedConversation: Conversation?
    @State private var showDetail = false
    @State private var conversations: [Conversation] = Conversation.previews
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // MARK: Sidebar
            SidebarView(
                conversations: filteredConversations,
                selection: $selectedConversation
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 340)
        } content: {
            // MARK: Content — active chat
            if let conversation = selectedConversation {
                macOSChatView(
                    conversation: conversation,
                    showDetail: $showDetail
                )
            } else {
                ContentUnavailableView(
                    "No Chat Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Choose a conversation from the sidebar.")
                )
            }
        } detail: {
            // MARK: Detail panel — contact info
            if showDetail, let conversation = selectedConversation {
                macOSContactInfoPanel(conversation: conversation)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
            }
        }
        .navigationTitle("")
        .toolbar { toolbarContent }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
        .frame(minWidth: 900, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .navigateConversation)) { note in
            guard let forward = note.object as? Bool else { return }
            navigate(forward: forward)
        }
    }

    private func navigate(forward: Bool) {
        let list = filteredConversations
        guard !list.isEmpty else { return }
        if let current = selectedConversation, let idx = list.firstIndex(where: { $0.id == current.id }) {
            let next = forward ? min(idx + 1, list.count - 1) : max(idx - 1, 0)
            selectedConversation = list[next]
        } else {
            selectedConversation = forward ? list.first : list.last
        }
    }

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.peerDisplayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                NSApp.keyWindow?.firstResponder?.tryToPerform(
                    #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if selectedConversation != nil {
                Button {
                    showDetail.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Info Panel (⌘W)")

                Divider()

                Button { /* Phase 7 */ } label: {
                    Image(systemName: "phone.fill")
                }
                .help("Voice Call")

                Button { /* Phase 7 */ } label: {
                    Image(systemName: "video.fill")
                }
                .help("Video Call")
            }

            Button {
                // ⌘N opens new chat sheet
                NotificationCenter.default.post(name: .newChatRequested, object: nil)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New Chat (⌘N)")
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let newChatRequested = Notification.Name("openwhats.newChatRequested")
}
#endif
