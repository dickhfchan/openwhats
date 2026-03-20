import UIKit
import UserNotifications
import OpenWhatsCore

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in }
        application.registerForRemoteNotifications()

        // Wire core services on MainActor
        Task { @MainActor in
            setupMessagePipeline()
            if !AccountManager.shared.jwtToken.isEmpty {
                connectWebSocket()
                startKeyRotation()
            }
        }

        return true
    }

    // MARK: - APNs token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        // Re-register device with updated APNs token (server upserts by device type)
        Task {
            guard !AccountManager.shared.jwtToken.isEmpty else { return }
            _ = try? await APIClient.shared.registerDevice(type: "phone", apnsToken: token)
        }
    }

    // MARK: - App lifecycle

    func applicationDidBecomeActive(_ application: UIApplication) {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        Task { @MainActor in
            // Reconnect if disconnected while in background
            if !AccountManager.shared.jwtToken.isEmpty {
                connectWebSocket()
            }
        }
    }
}
