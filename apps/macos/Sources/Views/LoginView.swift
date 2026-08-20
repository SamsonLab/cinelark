import SwiftUI

struct LoginView: View {
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
                    Text("Your library, ready for the big screen.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("UHDNow username", text: $username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    Toggle("Use a TOTP code", isOn: $showTOTP)
                        .toggleStyle(.switch)

                    if showTOTP {
                        TextField("6-digit code", text: $totpCode)
                            .textContentType(.oneTimeCode)
                    }

                    if let error = model.errorMessage {
                        Text(error)
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
                            Text(isSigningIn ? "Signing In…" : "Sign In")
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
        }
    }
}
