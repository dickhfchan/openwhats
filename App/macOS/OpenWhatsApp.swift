#if os(macOS)
import SwiftUI
import OpenWhatsCore
import OpenWhatsUI

@main
struct OpenWhatsApp: App {

    @NSApplicationDelegateAdaptor(macOSAppDelegate.self) var appDelegate
    @State private var isAuthenticated = !AccountManager.shared.jwtToken.isEmpty

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    AppSplitView()
                } else {
                    macOSOnboarding {
                        isAuthenticated = true
                        Task { @MainActor in connectWebSocket(); startKeyRotation() }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .signOut)) { _ in
                isAuthenticated = false
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 680)
        .commands { AppCommands() }

        Settings {
            MacSettingsView()
        }
    }
}
#endif
