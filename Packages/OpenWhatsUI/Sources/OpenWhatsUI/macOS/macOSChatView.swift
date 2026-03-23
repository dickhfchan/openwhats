#if os(macOS)
import SwiftUI
import OpenWhatsCore

/// Center column — active chat on macOS.
struct macOSChatView: View {

    let conversation: Conversation
    @Binding var showDetail: Bool

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isDropTargeted = false
    @State private var showKeyChangeBanner = false

    var body: some View {
        VStack(spacing: 0) {
            if showKeyChangeBanner {
                keyChangeBanner
            }
            messageList
                .background(Color(light: Color(hex: "#EAE4D9"), dark: Color(hex: "#0D1418")))
            Divider()
            macOSMessageInputBar(
                text: $inputText,
                onSend: sendText,
                onAttach: { /* Phase 5: open NSOpenPanel */ }
            )
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(conversation.peerDisplayName)
        .navigationSubtitle("last seen recently")
        .onAppear { messages = Message.previews(for: conversation.id) }
        .onReceive(NotificationCenter.default.publisher(for: .identityKeyChanged)) { note in
            if (note.object as? String) == conversation.peerUserID {
                showKeyChangeBanner = true
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDroppedFiles(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.owGreen, lineWidth: 3)
                    .background(Color.owGreen.opacity(0.05))
                    .padding(4)
            }
        }
    }

    // MARK: - Key change banner

    private var keyChangeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Security Code Changed")
                    .font(.subheadline).bold()
                Text("Verify this contact's identity in the info panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showKeyChangeBanner = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(messagesWithDateSeparators.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .message(let msg):
                            MessageBubble(message: msg, isLastInGroup: isLastInGroup(at: index))
                                .id(msg.id)
                                .contextMenu { messageContextMenu(for: msg) }
                        case .dateSeparator(let date):
                            macOSDateSeparator(date: date)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear { scrollToBottom(proxy: proxy, animated: false) }
            .onChange(of: messages.count) { scrollToBottom(proxy: proxy) }
        }
    }

    @ViewBuilder
    private func messageContextMenu(for message: Message) -> some View {
        if message.type == .text, let body = message.body {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(body, forType: .string)
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

    private func isLastInGroup(at index: Int) -> Bool {
        let items = messagesWithDateSeparators
        guard case .message(let current) = items[index] else { return true }
        // Check if next item is a different sender or a date separator
        if index + 1 < items.count {
            if case .message(let next) = items[index + 1] {
                return next.isMine != current.isMine
            }
        }
        return true
    }

    // MARK: - Actions

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
        // Phase 6: call MessagePipeline.shared.send(text:to:)
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        // Phase 5: for each url determine type + call MediaUploader
        _ = urls
    }
}

// MARK: - Date separator

private struct macOSDateSeparator: View {
    let date: Date

    var body: some View {
        Text(dateLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
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
#endif
