#if os(iOS)
import Foundation
import CallKit
import AVFoundation
import OpenWhatsCore

/// Bridges `CallManager` and CallKit so the system shows native call UI.
@MainActor
public final class CallKitProvider: NSObject, CXProviderDelegate {

    public static let shared = CallKitProvider()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var activeUUID: UUID?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.iconTemplateImageData = nil
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)

        // Listen for CallManager state changes
        Task { @MainActor in
            for await _ in NotificationCenter.default.notifications(named: .incomingCallReceived) {
                // Handled via reportIncomingCall
            }
        }
    }

    // MARK: - Outgoing call

    public func reportOutgoingCall(callID: String, peerDisplayName: String, isVideo: Bool) {
        let uuid = UUID()
        activeUUID = uuid
        let handle = CXHandle(type: .generic, value: peerDisplayName)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = isVideo
        let transaction = CXTransaction(action: startAction)
        callController.request(transaction) { _ in }
    }

    // MARK: - Incoming call

    public func reportIncomingCall(signal: CallSignalMessage, displayName: String) {
        let uuid = UUID()
        activeUUID = uuid
        let handle = CXHandle(type: .generic, value: displayName)
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.hasVideo = signal.isVideo
        update.localizedCallerName = displayName
        provider.reportNewIncomingCall(with: uuid, update: update) { _ in }
    }

    // MARK: - End call

    public func reportCallEnded() {
        guard let uuid = activeUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        activeUUID = nil
    }

    // MARK: - CXProviderDelegate

    nonisolated public func providerDidReset(_ provider: CXProvider) {}

    nonisolated public func provider(_ provider: CXProvider,
                                     perform action: CXAnswerCallAction) {
        Task { @MainActor in CallManager.shared.acceptCall() }
        action.fulfill()
        configureAudio()
    }

    nonisolated public func provider(_ provider: CXProvider,
                                     perform action: CXEndCallAction) {
        Task { @MainActor in CallManager.shared.endCall() }
        action.fulfill()
    }

    nonisolated public func provider(_ provider: CXProvider,
                                     perform action: CXSetMutedCallAction) {
        Task { @MainActor in CallManager.shared.toggleMute() }
        action.fulfill()
    }

    nonisolated public func provider(_ provider: CXProvider,
                                     didActivate audioSession: AVAudioSession) {
        // WebRTC audio session is activated here
    }

    nonisolated public func provider(_ provider: CXProvider,
                                     didDeactivate audioSession: AVAudioSession) {}

    // MARK: - Audio session

    private func configureAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        try? session.setActive(true)
    }
}
#endif
