#if os(iOS)
import SwiftUI
import OpenWhatsCore

public struct ChatView: View {

    let conversation: Conversation

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var inputFocused: Bool
    @State private var showKeyChangeBanner = false

    public init(conversation: Conversation) {
        self.conversation = conversation
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showKeyChangeBanner {
                keyChangeBanner
            }
            messageList
            Divider()
            MessageInputBar(
                text: $inputText,
                onSend: sendText,
                onAttach: { /* Phase 5: show photo/camera picker */ },
                onVoice: { /* Phase 5: start voice recording */ }
            )
            .background(.bar)
        }
        .navigationTitle(conversation.peerDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AvatarView(
                    url: conversation.peerAvatarURL.flatMap { URL(string: $0) },
                    name: conversation.peerDisplayName,
                    size: 32
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: ConversationInfoView(conversation: conversation)) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .onAppear { loadMessages() }
        .onReceive(NotificationCenter.default.publisher(for: .identityKeyChanged)) { note in
            if (note.object as? String) == conversation.peerUserID {
                showKeyChangeBanner = true
            }
        }
    }

    // MARK: - Key change banner

    private var keyChangeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Security Code Changed")
                    .font(.subheadline).bold()
                Text("Verify this contact's identity in Contact Info.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showKeyChangeBanner = false } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messagesWithDateSeparators, id: \.id) { item in
                        switch item {
                        case .message(let msg):
                            MessageBubble(message: msg)
                                .id(msg.id)
                                .contextMenu { messagContextMenu(for: msg) }

                        case .dateSeparator(let date):
                            DateSeparator(date: date)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func messagContextMenu(for message: Message) -> some View {
        if message.type == .text, let body = message.body {
            Button {
                UIPasteboard.general.string = body
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        Button(role: .destructive) {
            messages.removeAll { $0.id == message.id }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = messages.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Date separators

    private enum ListItem: Identifiable {
        case message(Message)
        case dateSeparator(Date)

        var id: String {
            switch self {
            case .message(let m): return m.id
            case .dateSeparator(let d): return "sep-\(d.timeIntervalSince1970)"
            }
        }
    }

    private var messagesWithDateSeparators: [ListItem] {
        var result: [ListItem] = []
        var lastDate: Date?
        for msg in messages {
            let day = Calendar.current.startOfDay(for: msg.timestamp)
            if lastDate.map({ !Calendar.current.isDate($0, inSameDayAs: day) }) ?? true {
                result.append(.dateSeparator(day))
                lastDate = day
            }
            result.append(.message(msg))
        }
        return result
    }

    // MARK: - Actions

    private func loadMessages() {
        messages = Message.previews(for: conversation.id)
    }

    private func sendText() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newMsg = Message(
            id: UUID().uuidString,
            conversationID: conversation.id,
            senderID: "me",
            senderDeviceID: "mydev",
            type: .text,
            body: inputText,
            localPath: nil,
            timestamp: Date(),
            status: .sending
        )
        messages.append(newMsg)
        inputText = ""
        inputFocused = false

        // Phase 5: call MessagePipeline.shared.send(text:to:)
    }
}

// MARK: - Date separator view

private struct DateSeparator: View {
    let date: Date

    var body: some View {
        Text(dateLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .padding(.vertical, 8)
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: Conversation.previews[0])
    }
}
#endif
