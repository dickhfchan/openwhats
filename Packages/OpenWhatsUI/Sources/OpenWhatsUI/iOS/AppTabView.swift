#if os(iOS)
import SwiftUI
import OpenWhatsCore

/// Root tab bar for the iOS app — Calls | Chats | Settings.
public struct AppTabView: View {

    @State private var selectedTab: Tab = .chats

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            CallsPlaceholderView()
                .tabItem {
                    Label("Calls", systemImage: "phone.fill")
                }
                .tag(Tab.calls)

            ChatsListView()
                .tabItem {
                    Label("Chats", systemImage: "message.fill")
                }
                .tag(Tab.chats)
                .badge(0)   // unread count injected from ConversationStore

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(Color.owGreen)
    }

    enum Tab { case calls, chats, settings }
}

private struct CallsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No Calls Yet",
                systemImage: "phone.fill",
                description: Text("Calls will appear here."))
            .navigationTitle("Calls")
        }
    }
}
#endif
