#if os(iOS)
import SwiftUI
import AuthenticationServices
import OpenWhatsCore

/// Full onboarding flow: Sign in with Apple → handle picker → display name + avatar.
public struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var step: Step = .signIn
    @State private var handle = ""
    @State private var displayName = ""
    @State private var handleAvailable: Bool? = nil
    @State private var isCheckingHandle = false
    @State private var errorMessage: String?

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            switch step {
            case .signIn:    signInView
            case .profile:   profileView
            }
        }
    }

    // MARK: - Sign In step

    private var signInView: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.owGreen)

                Text("OpenWhats")
                    .font(.system(size: 34, weight: .bold))

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
            .frame(height: 50)
            .padding(.horizontal, 40)

            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Text("By signing in you agree to our Privacy Policy.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .navigationTitle("")
        .navigationBarHidden(true)
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

                    let deviceResp = try await APIClient.shared.registerDevice(type: "phone", apnsToken: nil)
                    AccountManager.shared.deviceID = deviceResp.deviceId

                    if resp.isComplete {
                        await MainActor.run { onComplete() }
                    } else {
                        // New user — needs to set handle
                        await MainActor.run { step = .profile }
                    }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile setup step

    private var profileView: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AvatarView(url: nil, name: displayName.isEmpty ? "?" : displayName, size: 72)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Choose a handle") {
                HStack {
                    Text("@")
                        .foregroundStyle(.secondary)
                    TextField("yourhandle", text: $handle)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: handle) { _, new in checkHandle(new) }
                    Spacer()
                    if isCheckingHandle {
                        ProgressView().scaleEffect(0.8)
                    } else if let available = handleAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(available ? Color.owGreen : .red)
                    }
                }
            } footer: {
                Text("3–20 characters. Letters, numbers, underscores only.")
            }

            Section("Your name") {
                TextField("Display name", text: $displayName)
            }

            Section {
                Button("Continue") { saveProfile() }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(canContinue ? Color.owGreen : .secondary)
                    .disabled(!canContinue)
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Set Up Profile")
        .navigationBarBackButtonHidden()
    }

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        handleAvailable == true
    }

    private var handleCheckTask: Task<Void, Never>?

    private mutating func checkHandle(_ handle: String) {
        handleCheckTask?.cancel()
        handleAvailable = nil
        guard handle.count >= 3 else { return }

        isCheckingHandle = true
        handleCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                let resp = try await APIClient.shared.checkHandle(handle)
                await MainActor.run {
                    handleAvailable = resp.available
                    isCheckingHandle = false
                }
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
    OnboardingView(onComplete: {})
}
#endif
