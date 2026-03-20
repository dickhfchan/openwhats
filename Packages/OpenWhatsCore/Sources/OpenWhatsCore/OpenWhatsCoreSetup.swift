import Foundation

// MARK: - App lifecycle hooks
//
// Call these from your app's @UIApplicationDelegateAdaptor / NSApplicationDelegate.
// All functions are @MainActor — call them inside `Task { @MainActor in ... }` from
// synchronous delegate methods.

/// Wire the in-memory MessageStore to the pipeline.
/// Call once, immediately after `didFinishLaunchingWithOptions` (before WebSocket connects).
@MainActor
public func setupMessagePipeline() {
    MessagePipeline.shared.messageStore = MessageStore.shared
}

/// Open the WebSocket relay. Call after authentication completes.
@MainActor
public func connectWebSocket() {
    WebSocketClient.shared.connect()
}

/// Close the WebSocket relay. Call on sign-out.
@MainActor
public func disconnectWebSocket() {
    WebSocketClient.shared.disconnect()
}

/// Kick off periodic SPK rotation and OTPK replenishment.
/// Call after authentication completes.
@MainActor
public func startKeyRotation() {
    KeyRotationManager.shared.startPeriodicRotation()
}

/// Full sign-out: clears credentials, disconnects WebSocket, posts `.signOut` notification.
@MainActor
public func performSignOut() {
    WebSocketClient.shared.disconnect()
    AccountManager.shared.jwtToken  = ""
    AccountManager.shared.userID    = ""
    AccountManager.shared.deviceID  = ""
    NotificationCenter.default.post(name: .signOut, object: nil)
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted by `performSignOut()`. RootView and macOS equivalent observe this to navigate to onboarding.
    public static let signOut = Notification.Name("OpenWhatsSignOut")
}
