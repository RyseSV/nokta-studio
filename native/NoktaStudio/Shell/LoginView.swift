import SwiftUI

/// The app never had its own login screen — it always relied on the WKWebView
/// showing admin.html's real login form once, then CookieSync copying that
/// session cookie into NoktaAPI's URLSession. Now that every sidebar section
/// is native (RootView's webPageId is nil everywhere), that WKWebView is
/// unreachable, so this is the only way left to actually sign in.
///
/// Posting directly to /api/admin/login works without any WKWebView
/// involved: NoktaAPI's URLSession already uses `.shared` cookie storage and
/// accepts all cookies, so the Set-Cookie header from this POST lands in the
/// exact same place CookieSync used to copy into.
@Observable
final class LoginViewModel {
    var username = ""
    var password = ""
    var remember = true
    var useTouchID = true
    var isLoading = false
    var errorMessage: String?

    func login(saveForBiometrics: Bool) async -> Bool {
        errorMessage = nil
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !password.isEmpty else {
            errorMessage = "Escribe tu usuario y contraseña"
            return false
        }
        isLoading = true
        defer { isLoading = false }
        struct Body: Encodable { let username: String; let password: String; let remember: Bool }
        struct Resp: Decodable { let ok: Bool? }
        do {
            let resp: Resp = try await NoktaAPI.post("/api/admin/login", body: Body(username: user, password: password, remember: remember))
            guard resp.ok == true else {
                errorMessage = "Usuario o contraseña incorrectos"
                KeychainCredentialStore.delete() // stale saved credential would just fail silently later
                return false
            }
            if saveForBiometrics {
                KeychainCredentialStore.save(username: user, password: password)
            } else {
                KeychainCredentialStore.delete()
            }
            return true
        } catch NoktaAPIError.http(_, let msg) {
            errorMessage = msg == "—" ? "Usuario o contraseña incorrectos" : msg
            return false
        } catch {
            errorMessage = "No se pudo conectar. Revisa tu internet."
            return false
        }
    }
}

struct LoginView: View {
    @State private var vm = LoginViewModel()
    @State private var hasSavedCredential = KeychainCredentialStore.hasStoredCredential
    @State private var isAuthenticatingBiometrics = false
    let onSuccess: () -> Void

    private var biometricLabel: String {
        #if os(iOS)
        "Entrar con Face ID / Touch ID"
        #else
        "Entrar con Touch ID"
        #endif
    }

    var body: some View {
        ZStack {
            NoktaPalette.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("nokta").foregroundStyle(NoktaPalette.cream)
                        Text(".").foregroundStyle(NoktaPalette.ember)
                    }.font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Panel administrativo").font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                }

                VStack(spacing: 12) {
                    if hasSavedCredential && BiometricAuth.isAvailable {
                        Button {
                            Task { await loginWithBiometrics() }
                        } label: {
                            Label(isAuthenticatingBiometrics ? "Verificando…" : biometricLabel, systemImage: "touchid")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                        .disabled(isAuthenticatingBiometrics)

                        HStack {
                            Rectangle().fill(NoktaPalette.border).frame(height: 1)
                            Text("o con tu contraseña").font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                            Rectangle().fill(NoktaPalette.border).frame(height: 1)
                        }
                    }

                    TextField("Usuario", text: $vm.username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Contraseña", text: $vm.password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await submit() } }

                    Toggle("Recordar sesión en este dispositivo", isOn: $vm.remember)
                        .font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)
                        .toggleStyle(.switch)

                    if BiometricAuth.isAvailable {
                        Toggle(biometricLabel + " la próxima vez", isOn: $vm.useTouchID)
                            .font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)
                            .toggleStyle(.switch)
                    }

                    if let err = vm.errorMessage {
                        Text(err).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                    }

                    Button(vm.isLoading ? "Ingresando…" : "Ingresar") { Task { await submit() } }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                        .frame(maxWidth: .infinity)
                        .disabled(vm.isLoading)
                }
                .frame(maxWidth: 320)
            }
            .padding(32)
        }
    }

    private func submit() async {
        if await vm.login(saveForBiometrics: vm.useTouchID && BiometricAuth.isAvailable) { onSuccess() }
    }

    /// The Keychain item's own access-control check does the actual
    /// biometric/passcode prompt (kSecUseOperationPrompt) — this just reads
    /// the result and replays the same login the user already did once.
    private func loginWithBiometrics() async {
        isAuthenticatingBiometrics = true
        defer { isAuthenticatingBiometrics = false }
        guard let cred = KeychainCredentialStore.load(reason: "Inicia sesión en Nokta Studio") else {
            hasSavedCredential = KeychainCredentialStore.hasStoredCredential
            return
        }
        vm.username = cred.username
        vm.password = cred.password
        if await vm.login(saveForBiometrics: true) { onSuccess() }
    }
}
