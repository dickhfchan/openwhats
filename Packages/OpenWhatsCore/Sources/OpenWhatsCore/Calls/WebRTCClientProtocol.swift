import Foundation

// MARK: - WebRTC abstraction layer
//
// This protocol decouples CallManager from the concrete WebRTC framework.
// The real implementation (WebRTCClient) uses import WebRTC and must be
// added via Xcode (stasel/WebRTC SPM package or Pods).
// For swift build / previews a stub is provided automatically.

public protocol WebRTCClientProtocol: AnyObject, Sendable {
    var delegate: (any WebRTCClientDelegate)? { get set }

    /// Create an SDP offer for an outgoing call.
    func createOffer(isVideo: Bool) async throws -> CallSignalData.SDPData

    /// Create an SDP answer for an incoming call.
    func createAnswer(offer: CallSignalData.SDPData) async throws -> CallSignalData.SDPData

    /// Apply the remote answer SDP.
    func setRemoteAnswer(_ answer: CallSignalData.SDPData) async throws

    /// Add a remote ICE candidate.
    func addICECandidate(_ candidate: CallSignalData.ICECandidateData) async throws

    /// Configure ICE servers (TURN/STUN).
    func configure(iceServers: [ICEServer])

    /// Mute or unmute local audio.
    func setAudioEnabled(_ enabled: Bool)

    /// Enable or disable local video track.
    func setVideoEnabled(_ enabled: Bool)

    /// Close the peer connection and release resources.
    func close()
}

public struct ICEServer: Sendable {
    public let urls: [String]
    public let username: String?
    public let credential: String?
    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls; self.username = username; self.credential = credential
    }
}

public protocol WebRTCClientDelegate: AnyObject, Sendable {
    func webRTCClient(_ client: any WebRTCClientProtocol, didGenerate candidate: CallSignalData.ICECandidateData)
    func webRTCClient(_ client: any WebRTCClientProtocol, didChangeConnectionState state: WebRTCConnectionState)
}

public enum WebRTCConnectionState: Equatable, Sendable {
    case new, checking, connected, disconnected, failed, closed
}

// MARK: - Stub (used when the real framework is not imported)

/// No-op implementation used in previews and swift build context.
public final class WebRTCClientStub: WebRTCClientProtocol, @unchecked Sendable {
    public weak var delegate: (any WebRTCClientDelegate)?
    public init() {}
    public func createOffer(isVideo: Bool) async throws -> CallSignalData.SDPData {
        CallSignalData.SDPData(sdp: "stub-sdp", type: "offer")
    }
    public func createAnswer(offer: CallSignalData.SDPData) async throws -> CallSignalData.SDPData {
        CallSignalData.SDPData(sdp: "stub-sdp", type: "answer")
    }
    public func setRemoteAnswer(_ answer: CallSignalData.SDPData) async throws {}
    public func addICECandidate(_ candidate: CallSignalData.ICECandidateData) async throws {}
    public func configure(iceServers: [ICEServer]) {}
    public func setAudioEnabled(_ enabled: Bool) {}
    public func setVideoEnabled(_ enabled: Bool) {}
    public func close() {}
}
