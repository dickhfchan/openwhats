import SwiftUI
import OpenWhatsCore
import OpenWhatsUI

@main
struct OpenWhatsApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var isAuthenticated = !AccountManager.shared.jwtToken.isEmpty

    var body: some View {
        Group {
            if isAuthenticated {
                AppTabView()
            } else {
                OnboardingView(onComplete: {
                    isAuthenticated = true
                    Task { @MainActor in connectWebSocket(); startKeyRotation() }
                })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .signOut)) { _ in
            isAuthenticated = false
        }
    }
}
