#if os(macOS)
import AppKit
import OpenWhatsCore

final class macOSAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupMessagePipeline()
            if !AccountManager.shared.jwtToken.isEmpty {
                connectWebSocket()
                startKeyRotation()
            }
        }
        NSApplication.shared.dockTile.badgeLabel = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // stay running in the dock like a real chat app
    }
}
#endif
