import SwiftUI

/// The app never had its own login screen — it always relied on the WKWebView
/// showing admin.html's real login form once, then a since-removed CookieSync
/// helper copying that session cookie into NoktaAPI's URLSession on every
/// request. Now that every sidebar section is native (RootView's webPageId
/// is nil everywhere), that WKWebView is unreachable, so this is the only
/// way left to actually sign in.
///
/// Posting directly to /api/admin/login works without any WKWebView
/// involved: NoktaAPI's URLSession already uses `.shared` cookie storage and
/// accepts all cookies, so the Set-Cookie header from this POST lands there
/// directly and stays put — nothing re-syncs over it afterward.
@Observable
final class LoginViewModel {
    var username = ""
    var password = ""
    var remember = true
    var isLoading = false
    var errorMessage: String?

    func login() async -> Bool {
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
            if resp.ok == true { return true }
            errorMessage = "Usuario o contraseña incorrectos"
            return false
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
    let onSuccess: () -> Void

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
        if await vm.login() { onSuccess() }
    }
}
