#if os(macOS)
import SwiftUI
import OpenWhatsCore

// MARK: - macOS call overlay

/// Floating panel shown during a call on macOS.
/// Appears as a small HUD in the top-right corner of the screen.
public struct MacCallView: View {

    let peerDisplayName: String
    let isVideo: Bool

    @ObservedObject private var callManager = CallManager.shared
    @State private var callDuration = ""
    @State private var timer: Timer?

    public init(peerDisplayName: String, isVideo: Bool) {
        self.peerDisplayName = peerDisplayName
        self.isVideo = isVideo
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                AvatarView(url: nil, name: peerDisplayName, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peerDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(callDuration.isEmpty ? "Connecting…" : callDuration)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }

            HStack(spacing: 12) {
                MacCallButton(
                    systemName: callManager.isAudioMuted ? "mic.slash.fill" : "mic.fill",
                    tint: callManager.isAudioMuted ? .red : .white.opacity(0.3)
                ) { callManager.toggleMute() }
                .help(callManager.isAudioMuted ? "Unmute" : "Mute")

                if isVideo {
                    MacCallButton(
                        systemName: callManager.isVideoEnabled ? "video.fill" : "video.slash.fill",
                        tint: .white.opacity(0.3)
                    ) { callManager.toggleVideo() }
                    .help("Toggle Camera")
                }

                Spacer()

                Button {
                    callManager.endCall()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("End Call")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.82))
        )
        .frame(width: 260)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if case .active(_, let startedAt) = callManager.callState {
                let elapsed = Int(Date().timeIntervalSince(startedAt))
                let m = elapsed / 60; let s = elapsed % 60
                callDuration = String(format: "%02d:%02d", m, s)
            }
        }
    }
}

private struct MacCallButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Incoming call banner for macOS

public struct MacIncomingCallBanner: View {

    let signal: CallSignalMessage
    let peerDisplayName: String

    @ObservedObject private var callManager = CallManager.shared

    public init(signal: CallSignalMessage, peerDisplayName: String) {
        self.signal = signal
        self.peerDisplayName = peerDisplayName
    }

    public var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: nil, name: peerDisplayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(peerDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(signal.isVideo ? "Incoming Video Call" : "Incoming Call")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button {
                callManager.declineCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Decline")

            Button {
                callManager.acceptCall()
            } label: {
                Image(systemName: signal.isVideo ? "video.fill" : "phone.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.owGreen)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Accept")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.82))
        )
        .frame(width: 320)
    }
}

#Preview {
    MacCallView(peerDisplayName: "Alice Johnson", isVideo: false)
        .padding()
}
#endif
