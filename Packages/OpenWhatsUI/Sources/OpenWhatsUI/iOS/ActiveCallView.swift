#if os(iOS)
import SwiftUI
import OpenWhatsCore

/// Full-screen active call UI (shown when a call is connected).
public struct ActiveCallView: View {

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
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Avatar / Video placeholder
                if isVideo {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text("Video — coming in Phase 7b")
                                .foregroundStyle(.secondary)
                        )
                        .padding(.horizontal, 24)
                        .frame(height: 300)
                } else {
                    AvatarView(url: nil, name: peerDisplayName, size: 100)
                }

                Spacer().frame(height: 24)

                Text(peerDisplayName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(callDuration)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)

                Spacer()

                // Controls
                HStack(spacing: 40) {
                    CallControlButton(
                        systemName: callManager.isAudioMuted ? "mic.slash.fill" : "mic.fill",
                        label: callManager.isAudioMuted ? "Unmute" : "Mute",
                        tint: callManager.isAudioMuted ? .red : .white.opacity(0.3)
                    ) {
                        callManager.toggleMute()
                    }

                    // End call
                    Button {
                        callManager.endCall()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color.red)
                            .clipShape(Circle())
                    }

                    if isVideo {
                        CallControlButton(
                            systemName: callManager.isVideoEnabled ? "video.fill" : "video.slash.fill",
                            label: "Camera",
                            tint: .white.opacity(0.3)
                        ) {
                            callManager.toggleVideo()
                        }
                    } else {
                        CallControlButton(
                            systemName: "speaker.wave.2.fill",
                            label: "Speaker",
                            tint: .white.opacity(0.3)
                        ) {
                            // Phase 7b: toggle speaker
                        }
                    }
                }
                .padding(.bottom, 48)
            }
        }
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

private struct CallControlButton: View {
    let systemName: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(tint)
                    .clipShape(Circle())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

#Preview {
    ActiveCallView(peerDisplayName: "Alice Johnson", isVideo: false)
}
#endif
