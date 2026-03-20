#if os(iOS)
import SwiftUI
import OpenWhatsCore

/// Shown over the app when an incoming call arrives (in-app fallback,
/// CallKit handles the lock-screen presentation automatically).
public struct IncomingCallView: View {

    let signal: CallSignalMessage
    let peerDisplayName: String

    @ObservedObject private var callManager = CallManager.shared

    public init(signal: CallSignalMessage, peerDisplayName: String) {
        self.signal = signal
        self.peerDisplayName = peerDisplayName
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                AvatarView(url: nil, name: peerDisplayName, size: 88)

                VStack(spacing: 6) {
                    Text(peerDisplayName)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(signal.isVideo ? "Incoming Video Call" : "Incoming Call")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                HStack(spacing: 60) {
                    // Decline
                    Button {
                        callManager.declineCall()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.red)
                                .clipShape(Circle())
                            Text("Decline")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    // Accept
                    Button {
                        callManager.acceptCall()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: signal.isVideo ? "video.fill" : "phone.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.owGreen)
                                .clipShape(Circle())
                            Text("Accept")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }
}
#endif
