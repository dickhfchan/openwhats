import Foundation

// MARK: - Call signal types

public enum CallSignalType: String, Codable {
    case offer          // Caller → callee: SDP offer
    case answer         // Callee → caller: SDP answer
    case iceCandidate   = "ice_candidate"
    case hangup
    case ringing        // Callee → caller: phone is ringing
    case busy           // Callee → caller: already in a call
}

public struct CallSignalMessage: Codable, Sendable {
    public let callID: String
    public let fromUserID: String
    public let fromDeviceID: String
    public let toUserID: String
    public let toDeviceID: String?
    public let signalType: CallSignalType
    public let signalData: CallSignalData?
    public let isVideo: Bool

    public enum CodingKeys: String, CodingKey {
        case callID         = "call_id"
        case fromUserID     = "from_user_id"
        case fromDeviceID   = "from_device_id"
        case toUserID       = "to_user_id"
        case toDeviceID     = "to_device_id"
        case signalType     = "signal_type"
        case signalData     = "signal_data"
        case isVideo        = "is_video"
    }

    public init(callID: String, fromUserID: String, fromDeviceID: String,
                toUserID: String, toDeviceID: String?,
                signalType: CallSignalType, signalData: CallSignalData?,
                isVideo: Bool) {
        self.callID = callID
        self.fromUserID = fromUserID
        self.fromDeviceID = fromDeviceID
        self.toUserID = toUserID
        self.toDeviceID = toDeviceID
        self.signalType = signalType
        self.signalData = signalData
        self.isVideo = isVideo
    }
}

// MARK: - Signal payloads

public enum CallSignalData: Codable, Sendable {
    case sdp(SDPData)
    case iceCandidate(ICECandidateData)

    public struct SDPData: Codable, Sendable {
        public let sdp: String
        public let type: String    // "offer" or "answer"
        public init(sdp: String, type: String) { self.sdp = sdp; self.type = type }
    }

    public struct ICECandidateData: Codable, Sendable {
        public let candidate: String
        public let sdpMid: String?
        public let sdpMLineIndex: Int32?
        public init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32?) {
            self.candidate = candidate; self.sdpMid = sdpMid; self.sdpMLineIndex = sdpMLineIndex
        }
    }

    enum CodingKeys: String, CodingKey { case sdp, iceCandidate = "ice_candidate" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(SDPData.self, forKey: .sdp) { self = .sdp(v); return }
        if let v = try? c.decode(ICECandidateData.self, forKey: .iceCandidate) { self = .iceCandidate(v); return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown signal data"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sdp(let v):           try c.encode(v, forKey: .sdp)
        case .iceCandidate(let v):  try c.encode(v, forKey: .iceCandidate)
        }
    }
}

// MARK: - TURN Credentials

public struct TURNCredentials: Codable, Sendable {
    public let username: String
    public let password: String
    public let ttl: Int
    public let uris: [String]
}

// MARK: - Call session state

public enum CallState: Equatable, Sendable {
    case idle
    case outgoingRinging(callID: String, peerUserID: String, peerDisplayName: String, isVideo: Bool)
    case incomingRinging(callID: String, peerUserID: String, peerDisplayName: String, isVideo: Bool)
    case connecting(callID: String)
    case active(callID: String, startedAt: Date)
    case ended(callID: String, reason: EndReason)
}

public enum EndReason: String, Equatable, Sendable {
    case localHangup, remoteHangup, busy, failed, declined, timeout
}
