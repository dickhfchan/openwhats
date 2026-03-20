import Foundation

// MARK: - CallManager

/// Central coordinator for all WebRTC call lifecycle:
/// - Fetches TURN credentials and configures ICE servers
/// - Drives the WebRTC peer connection (via WebRTCClientProtocol)
/// - Relays signaling messages over WebSocket (via WebSocketClient)
/// - Publishes `callState` for the UI layer to observe
@MainActor
public final class CallManager: ObservableObject {

    public static let shared = CallManager()

    // MARK: Public state

    @Published public private(set) var callState: CallState = .idle
    @Published public private(set) var isAudioMuted = false
    @Published public private(set) var isVideoEnabled = false
    @Published public private(set) var isSpeakerOn = false

    // MARK: Private

    private var peerConnection: (any WebRTCClientProtocol)?
    private var activeTURN: TURNCredentials?

    /// Injected factory — swap in a real WebRTCClient in App/iOS and App/macOS.
    public var peerConnectionFactory: () -> any WebRTCClientProtocol = { WebRTCClientStub() }

    private init() {
        // Listen for call signals from WebSocket
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCallSignalNotification(_:)),
            name: .callSignalReceived,
            object: nil
        )
    }

    // MARK: - Outgoing call

    public func startCall(to peerUserID: String, peerDisplayName: String, isVideo: Bool) {
        guard case .idle = callState else { return }

        let callID = UUID().uuidString
        callState = .outgoingRinging(callID: callID, peerUserID: peerUserID,
                                      peerDisplayName: peerDisplayName, isVideo: isVideo)

        Task {
            do {
                let turn = try await APIClient.shared.getTURNCredentials()
                activeTURN = turn
                let pc = peerConnectionFactory()
                peerConnection = pc
                pc.delegate = self
                pc.configure(iceServers: iceServers(from: turn))
                pc.setVideoEnabled(isVideo)

                let offer = try await pc.createOffer(isVideo: isVideo)
                await sendSignal(callID: callID, to: peerUserID, type: .offer,
                                 data: .sdp(offer), isVideo: isVideo)
            } catch {
                callState = .ended(callID: callID, reason: .failed)
            }
        }
    }

    // MARK: - Incoming call handling

    public func receiveIncomingCall(signal: CallSignalMessage) {
        guard case .idle = callState else {
            // Send busy signal back
            Task {
                await sendSignal(callID: signal.callID, to: signal.fromUserID,
                                 toDeviceID: signal.fromDeviceID, type: .busy, data: nil, isVideo: signal.isVideo)
            }
            return
        }
        callState = .incomingRinging(callID: signal.callID,
                                      peerUserID: signal.fromUserID,
                                      peerDisplayName: signal.fromUserID, // resolved by UI
                                      isVideo: signal.isVideo)
        NotificationCenter.default.post(name: .incomingCallReceived, object: signal)
    }

    public func acceptCall() {
        guard case .incomingRinging(let callID, let peerUserID, _, let isVideo) = callState else { return }
        callState = .connecting(callID: callID)

        Task {
            do {
                let turn = try await APIClient.shared.getTURNCredentials()
                activeTURN = turn
                let pc = peerConnectionFactory()
                peerConnection = pc
                pc.delegate = self
                pc.configure(iceServers: iceServers(from: turn))
                pc.setVideoEnabled(isVideo)
                // Answer is created once the offer's SDP is applied via receiveOffer
            } catch {
                callState = .ended(callID: callID, reason: .failed)
            }
            await sendSignal(callID: callID, to: peerUserID, type: .ringing, data: nil, isVideo: isVideo)
        }
    }

    public func declineCall() {
        guard case .incomingRinging(let callID, let peerUserID, _, let isVideo) = callState else { return }
        Task { await sendSignal(callID: callID, to: peerUserID, type: .hangup, data: nil, isVideo: isVideo) }
        callState = .ended(callID: callID, reason: .declined)
    }

    public func endCall() {
        let callID = currentCallID
        let peerUserID = peerUserIDForCurrentCall()
        guard let callID, !peerUserID.isEmpty else { return }
        Task { await sendSignal(callID: callID, to: peerUserID, type: .hangup, data: nil, isVideo: false) }
        peerConnection?.close()
        peerConnection = nil
        callState = .ended(callID: callID, reason: .localHangup)
    }

    // MARK: - Call controls

    public func toggleMute() {
        isAudioMuted.toggle()
        peerConnection?.setAudioEnabled(!isAudioMuted)
    }

    public func toggleVideo() {
        isVideoEnabled.toggle()
        peerConnection?.setVideoEnabled(isVideoEnabled)
    }

    // MARK: - Signal handling

    @objc private func handleCallSignalNotification(_ note: Notification) {
        guard let signal = note.object as? CallSignalMessage else { return }
        Task { await handleSignal(signal) }
    }

    private func handleSignal(_ signal: CallSignalMessage) async {
        switch signal.signalType {
        case .offer:
            receiveIncomingCall(signal: signal)

        case .answer:
            guard let sdp = signal.sdpData, let pc = peerConnection else { return }
            do {
                try await pc.setRemoteAnswer(sdp)
                if case .outgoingRinging(let callID, _, _, _) = callState {
                    callState = .active(callID: callID, startedAt: Date())
                }
            } catch {}

        case .iceCandidate:
            guard let iceData = signal.iceCandidateData, let pc = peerConnection else { return }
            try? await pc.addICECandidate(iceData)

        case .ringing:
            break  // UI already shows outgoing ringing state

        case .hangup, .busy:
            peerConnection?.close()
            peerConnection = nil
            let reason: EndReason = signal.signalType == .busy ? .busy : .remoteHangup
            if case .outgoingRinging(let callID, _, _, _) = callState {
                callState = .ended(callID: callID, reason: reason)
            } else if case .active(let callID, _) = callState {
                callState = .ended(callID: callID, reason: reason)
            } else if case .connecting(let callID) = callState {
                callState = .ended(callID: callID, reason: reason)
            }
        }
    }

    // MARK: - Helpers

    private func iceServers(from turn: TURNCredentials) -> [ICEServer] {
        [ICEServer(urls: turn.uris, username: turn.username, credential: turn.password)]
    }

    private func sendSignal(callID: String, to peerUserID: String,
                             toDeviceID: String? = nil,
                             type: CallSignalType, data: CallSignalData?,
                             isVideo: Bool) async {
        let account = AccountManager.shared
        let msg = CallSignalMessage(
            callID: callID,
            fromUserID: account.userID,
            fromDeviceID: account.deviceID,
            toUserID: peerUserID,
            toDeviceID: toDeviceID,
            signalType: type,
            signalData: data,
            isVideo: isVideo
        )
        WebSocketClient.shared.sendCallSignal(msg)
    }

    private func peerUserIDForCurrentCall() -> String {
        switch callState {
        case .outgoingRinging(_, let id, _, _): return id
        case .incomingRinging(_, let id, _, _): return id
        default: return ""
        }
    }
}

// MARK: - WebRTCClientDelegate

extension CallManager: WebRTCClientDelegate {
    nonisolated public func webRTCClient(_ client: any WebRTCClientProtocol,
                                         didGenerate candidate: CallSignalData.ICECandidateData) {
        Task { @MainActor in
            let callID = self.currentCallID ?? ""
            let peerUserID = self.peerUserIDForCurrentCall()
            await self.sendSignal(callID: callID, to: peerUserID, type: .iceCandidate,
                                  data: .iceCandidate(candidate), isVideo: false)
        }
    }

    nonisolated public func webRTCClient(_ client: any WebRTCClientProtocol,
                                         didChangeConnectionState state: WebRTCConnectionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if case .connecting(let callID) = self.callState {
                    self.callState = .active(callID: callID, startedAt: Date())
                }
            case .failed, .closed:
                if let callID = self.currentCallID {
                    self.peerConnection?.close()
                    self.peerConnection = nil
                    self.callState = .ended(callID: callID, reason: .failed)
                }
            default: break
            }
        }
    }

    private var currentCallID: String? {
        switch callState {
        case .outgoingRinging(let id, _, _, _): return id
        case .incomingRinging(let id, _, _, _): return id
        case .connecting(let id): return id
        case .active(let id, _): return id
        case .ended(let id, _): return id
        case .idle: return nil
        }
    }
}

// MARK: - CallSignalMessage helpers

private extension CallSignalMessage {
    var sdpData: CallSignalData.SDPData? {
        guard case .sdp(let v) = signalData else { return nil }
        return v
    }
    var iceCandidateData: CallSignalData.ICECandidateData? {
        guard case .iceCandidate(let v) = signalData else { return nil }
        return v
    }
}

// MARK: - Notification names

public extension Notification.Name {
    static let callSignalReceived  = Notification.Name("openwhats.callSignalReceived")
    static let incomingCallReceived = Notification.Name("openwhats.incomingCallReceived")
}
