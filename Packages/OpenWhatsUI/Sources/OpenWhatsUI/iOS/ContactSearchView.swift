#if os(iOS)
import SwiftUI
import OpenWhatsCore

/// New chat screen — search by handle, tap to open or start conversation.
public struct ContactSearchView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var result: SearchResult = .idle
    @State private var navigateToChat: Conversation?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                switch result {
                case .idle:
                    ContentUnavailableView("Find People",
                        systemImage: "magnifyingglass",
                        description: Text("Search by @handle to start a conversation."))

                case .searching:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .found(let user):
                    List {
                        Button {
                            startConversation(with: user)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    url: user.avatarUrl.flatMap { URL(string: $0) },
                                    name: user.displayName
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("@\(user.handle)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)

                case .notFound:
                    ContentUnavailableView("No User Found",
                        systemImage: "person.slash",
                        description: Text("No one with the handle @\(searchText)"))

                case .error(let msg):
                    ContentUnavailableView("Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(msg))
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by @handle")
            .onChange(of: searchText) { _, newValue in
                searchHandle(newValue)
            }
            .navigationDestination(item: $navigateToChat) { conversation in
                ChatView(conversation: conversation)
            }
        }
    }

    // MARK: - Search

    private var searchTask: Task<Void, Never>?

    private mutating func searchHandle(_ handle: String) {
        searchTask?.cancel()
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")

        guard trimmed.count >= 3 else {
            result = .idle
            return
        }

        result = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500)) // debounce
            guard !Task.isCancelled else { return }
            do {
                let user = try await APIClient.shared.searchUser(handle: trimmed)
                await MainActor.run { result = .found(user) }
            } catch APIError.notFound {
                await MainActor.run { result = .notFound }
            } catch {
                await MainActor.run { result = .error(error.localizedDescription) }
            }
        }
    }

    private func startConversation(with user: UserResponse) {
        let conversation = Conversation(
            id: user.userId,
            peerUserID: user.userId,
            peerDisplayName: user.displayName,
            peerAvatarURL: user.avatarUrl,
            lastMessage: nil,
            unreadCount: 0,
            updatedAt: Date()
        )
        navigateToChat = conversation
    }

    // MARK: - State enum

    enum SearchResult {
        case idle
        case searching
        case found(UserResponse)
        case notFound
        case error(String)
    }
}

#Preview {
    ContactSearchView()
}
#endif
