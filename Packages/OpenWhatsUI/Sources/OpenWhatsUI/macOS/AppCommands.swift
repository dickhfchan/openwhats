#if os(macOS)
import SwiftUI
import OpenWhatsCore

/// Menu bar commands + keyboard shortcuts for the macOS app.
public struct AppCommands: Commands {

    public init() {}

    public var body: some Commands {
        // MARK: File menu additions
        CommandGroup(after: .newItem) {
            Button("New Chat") {
                NotificationCenter.default.post(name: .newChatRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        // MARK: Navigate menu
        CommandMenu("Navigate") {
            Button("Next Conversation") {
                NotificationCenter.default.post(name: .navigateConversation, object: true)
            }
            .keyboardShortcut(KeyEquivalent.downArrow, modifiers: .command)

            Button("Previous Conversation") {
                NotificationCenter.default.post(name: .navigateConversation, object: false)
            }
            .keyboardShortcut(KeyEquivalent.upArrow, modifiers: .command)
        }
    }
}

extension Notification.Name {
    /// Object is `Bool` — true = forward, false = backward.
    static let navigateConversation = Notification.Name("openwhats.navigateConversation")
}
#endif
