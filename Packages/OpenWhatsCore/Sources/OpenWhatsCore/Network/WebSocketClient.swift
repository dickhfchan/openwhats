import Foundation

// MARK: - WebSocket message types

enum WSMessageType: String {
    case envelope        = "ENVELOPE"
    case deliveryReceipt = "DELIVERY_RECEIPT"
    case readReceipt     = "READ_RECEIPT"
    case callSignal      = "CALL_SIGNAL"
    case ping            = "PING"
    case pong            = "PONG"
    case ack             = "ACK"
    case connected       = "CONNECTED"
}

// MARK: - WebSocketClient

/// Maintains a persistent, authenticated WebSocket connection to the relay server.
/// Reconnects automatically with exponential backoff on disconnect.
@MainActor
final class WebSocketClient: NSObject {

    static let shared = WebSocketClient()

    // Callbacks — set before calling connect()
    var onEnvelope: ((IncomingEnvelope) -> Void)?
    var onDeliveryReceipt: ((String) -> Void)?   // envelopeID
    var onReadReceipt: ((String) -> Void)?        // envelopeID
    var onConnected: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var backoffSeconds: Double = 1
    private let maxBackoff: Double = 60
    private var isIntentionallyClosed = false
    private var serverURL: URL

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    override private init() {
        #if DEBUG
        serverURL = URL(string: "ws://localhost:8083/ws")!
        #else
        serverURL = URL(string: "wss://api.openwhats.app/ws")!
        #endif
        super.init()
        session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
    }

    func setServerURL(_ url: URL) { serverURL = url }

    // MARK: - Connection lifecycle

    func connect() {
        isIntentionallyClosed = false
        openConnection()
    }

    func disconnect() {
        isIntentionallyClosed = true
        pingTask?.cancel()
        reconnectTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func openConnection() {
        guard !isIntentionallyClosed else { return }
        let account = AccountManager.shared
        guard !account.jwtToken.isEmpty, !account.deviceID.isEmpty else { return }

        var request = URLRequest(url: serverURL)
        request.setValue("Bearer \(account.jwtToken)", forHTTPHeaderField: "Authorization")
        request.setValue(account.deviceID, forHTTPHeaderField: "X-Device-ID")

        task = session.webSocketTask(with: request)
        task?.resume()
        receive()
        schedulePing()
    }

    // MARK: - Receive loop

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receive()  // continue listening
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = json["type"] as? String,
              let type = WSMessageType(rawValue: typeStr) else { return }

        switch type {
        case .connected:
            backoffSeconds = 1
            onConnected?()

        case .envelope:
            if let envData = try? JSONSerialization.data(withJSONObject: json["data"] ?? [:]),
               let env = try? decoder.decode(IncomingEnvelope.self, from: envData) {
                onEnvelope?(env)
                sendAck(envelopeIDs: [env.id])
            }

        case .deliveryReceipt:
            if let d = json["data"] as? [String: Any],
               let eid = d["envelope_id"] as? String {
                onDeliveryReceipt?(eid)
            }

        case .readReceipt:
            if let d = json["data"] as? [String: Any],
               let eid = d["envelope_id"] as? String {
                onReadReceipt?(eid)
            }

        case .callSignal:
            if let sigData = try? JSONSerialization.data(withJSONObject: json["data"] ?? [:]),
               let signal = try? decoder.decode(CallSignalMessage.self, from: sigData) {
                NotificationCenter.default.post(name: .callSignalReceived, object: signal)
            }

        case .pong:
            break  // heartbeat acknowledged

        default:
            break
        }
    }

    // MARK: - Send helpers

    func sendDeliveryReceipt(envelopeID: String, senderUserID: String, senderDeviceID: String) {
        let payload: [String: Any] = [
            "envelope_id": envelopeID,
            "sender_user_id": senderUserID,
            "sender_device_id": senderDeviceID,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        sendFrame(type: .deliveryReceipt, data: payload)
    }

    func sendReadReceipt(envelopeID: String, senderUserID: String, senderDeviceID: String) {
        let payload: [String: Any] = [
            "envelope_id": envelopeID,
            "sender_user_id": senderUserID,
            "sender_device_id": senderDeviceID,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        sendFrame(type: .readReceipt, data: payload)
    }

    func sendCallSignal(_ signal: CallSignalMessage) {
        guard let data = try? JSONEncoder().encode(signal),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        sendFrame(type: .callSignal, data: dict)
    }

    private func sendAck(envelopeIDs: [String]) {
        sendFrame(type: .ack, data: ["envelope_ids": envelopeIDs])
    }

    private func sendFrame(type: WSMessageType, data: [String: Any]) {
        var frame: [String: Any] = ["type": type.rawValue]
        frame["data"] = data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: frame),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        task?.send(.string(jsonStr)) { _ in }
    }

    // MARK: - Ping / reconnect

    private func schedulePing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.sendFrame(type: .ping, data: [:])
            }
        }
    }

    private func scheduleReconnect() {
        guard !isIntentionallyClosed else { return }
        task = nil
        reconnectTask?.cancel()
        let delay = backoffSeconds
        backoffSeconds = min(backoffSeconds * 2, maxBackoff)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.openConnection()
        }
    }
}
