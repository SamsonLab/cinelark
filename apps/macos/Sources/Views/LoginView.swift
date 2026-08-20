import SwiftUI

struct LoginView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var totpCode = ""
    @State private var showTOTP = false
    @State private var isSigningIn = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.09, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text("CineLark")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(language.localized("login.tagline"))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField(language.localized("login.username"), text: $username)
                        .textContentType(.username)
                    SecureField(language.localized("login.password"), text: $password)
                        .textContentType(.password)

                    Toggle(language.localized("login.use_totp"), isOn: $showTOTP)
                        .toggleStyle(.switch)

                    if showTOTP {
                        TextField(language.localized("login.totp"), text: $totpCode)
                            .textContentType(.oneTimeCode)
                    }

                    if let error = model.errorMessage {
                        Text(language.userFacingError(error))
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        isSigningIn = true
                        Task {
                            await model.signIn(
                                username: username,
                                password: password,
                                totpCode: showTOTP ? totpCode : nil
                            )
                            isSigningIn = false
                        }
                    } label: {
                        HStack {
                            if isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(
                                language.localized(
                                    isSigningIn ? "login.signing_in" : "login.sign_in"
                                )
                            )
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        isSigningIn ||
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.isEmpty
                    )
                }
                .textFieldStyle(.roundedBorder)
                .padding(28)
                .frame(width: 420)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            }

            VStack {
                HStack {
                    Spacer()
                    LanguageMenu()
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
            }
            .padding(20)
        }
    }
}
