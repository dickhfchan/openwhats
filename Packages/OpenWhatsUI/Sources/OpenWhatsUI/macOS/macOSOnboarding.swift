#if os(macOS)
import SwiftUI
import AuthenticationServices
import OpenWhatsCore

/// Onboarding flow for macOS: Sign in with Apple → profile setup.
public struct macOSOnboarding: View {

    let onComplete: () -> Void

    @State private var step: Step = .signIn
    @State private var handle = ""
    @State private var displayName = ""
    @State private var handleAvailable: Bool? = nil
    @State private var isCheckingHandle = false
    @State private var errorMessage: String?
    @State private var handleCheckTask: Task<Void, Never>?

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        switch step {
        case .signIn: signInView
        case .profile: profileView
        }
    }

    // MARK: - Sign in

    private var signInView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.owGreen)

                Text("OpenWhats")
                    .font(.system(size: 28, weight: .bold))

                Text("Simple. Secure. Private.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 240, height: 44)

            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text("By signing in you agree to our Privacy Policy.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(width: 480, height: 400)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Sign in failed — try again."
                return
            }
            Task {
                do {
                    let resp = try await APIClient.shared.appleAuth(identityToken: token)
                    AccountManager.shared.jwtToken = resp.token
                    AccountManager.shared.userID = resp.userId

                    let deviceResp = try await APIClient.shared.registerDevice(type: "desktop", apnsToken: nil)
                    AccountManager.shared.deviceID = deviceResp.deviceId

                    await MainActor.run {
                        if resp.isComplete { onComplete() } else { step = .profile }
                    }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile setup

    private var profileView: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AvatarView(url: nil, name: displayName.isEmpty ? "?" : displayName, size: 64)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Choose a handle") {
                HStack {
                    Text("@").foregroundStyle(.secondary)
                    TextField("yourhandle", text: $handle)
                        .onChange(of: handle) { _, new in startHandleCheck(new) }
                    Spacer()
                    if isCheckingHandle {
                        ProgressView().scaleEffect(0.7)
                    } else if let available = handleAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(available ? Color.owGreen : .red)
                    }
                }
            }

            Section("Your name") {
                TextField("Display name", text: $displayName)
            }

            Section {
                Button("Continue") { saveProfile() }
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .navigationTitle("Set Up Profile")
    }

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && handleAvailable == true
    }

    private func startHandleCheck(_ value: String) {
        handleCheckTask?.cancel()
        handleAvailable = nil
        guard value.count >= 3 else { return }
        isCheckingHandle = true
        handleCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                let resp = try await APIClient.shared.checkHandle(value)
                await MainActor.run { handleAvailable = resp.available; isCheckingHandle = false }
            } catch {
                await MainActor.run { isCheckingHandle = false }
            }
        }
    }

    private func saveProfile() {
        Task {
            do {
                _ = try await APIClient.shared.register(handle: handle, displayName: displayName)
                await MainActor.run { onComplete() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    enum Step { case signIn, profile }
}

#Preview {
    macOSOnboarding(onComplete: {})
}
#endif
