import SwiftUI

struct LoginView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var totpCode = ""
    @State private var showTOTP = false
    @State private var isSigningIn = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case password
        case totp
    }

    var body: some View {
        ZStack {
            CineLarkPageBackground()
            atmosphere

            VStack(spacing: 34) {
                identity
                credentialPanel
            }
            .padding(48)

            LanguageMenu()
                .buttonStyle(.glass)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)
        }
        .task {
            focusedField = .username
        }
        .onSubmit {
            if focusedField == .username {
                focusedField = .password
            } else if focusedField == .password, showTOTP {
                focusedField = .totp
            } else {
                signIn()
            }
        }
    }

    private var atmosphere: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.24))
                    .frame(width: proxy.size.width * 0.68)
                    .blur(radius: 120)
                    .offset(x: proxy.size.width * 0.30, y: -proxy.size.height * 0.28)
                Circle()
                    .fill(Color.cyan.opacity(0.10))
                    .frame(width: proxy.size.width * 0.46)
                    .blur(radius: 130)
                    .offset(x: -proxy.size.width * 0.38, y: proxy.size.height * 0.30)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var identity: some View {
        VStack(spacing: 12) {
            Image(systemName: "bird.fill")
                .font(.system(size: 52, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
            Text("CineLark")
                .font(.system(size: 44, weight: .bold))
            Text(language.localized("login.tagline"))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialPanel: some View {
        VStack(spacing: 16) {
            TextField(language.localized("login.username"), text: $username)
                .textContentType(.username)
                .focused($focusedField, equals: .username)
            SecureField(language.localized("login.password"), text: $password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)

            Toggle(language.localized("login.use_totp"), isOn: $showTOTP)
                .toggleStyle(.switch)

            if showTOTP {
                TextField(language.localized("login.totp"), text: $totpCode)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .totp)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = model.errorMessage {
                Text(language.userFacingError(error))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: signIn) {
                HStack {
                    if isSigningIn {
                        ProgressView().controlSize(.small)
                    }
                    Text(
                        language.localized(isSigningIn ? "login.signing_in" : "login.sign_in")
                    )
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(!canSignIn)
        }
        .textFieldStyle(.roundedBorder)
        .padding(30)
        .frame(width: 440)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .animation(CineLarkDesign.Motion.focus, value: showTOTP)
    }

    private func signIn() {
        guard !isSigningIn,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else { return }
        isSigningIn = true
        Task {
            await model.signIn(
                username: username,
                password: password,
                totpCode: showTOTP ? totpCode : nil
            )
            isSigningIn = false
        }
    }

    private var canSignIn: Bool {
        !isSigningIn &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty
    }
}
