import SwiftUI

private let alertIcons: [String: String] = [
    "descarga": "📥", "link_venciendo": "⏰", "pago_pendiente": "💰",
    "evento_proximo": "📅", "quincena_vencida": "🔔",
]
private let alertLabels: [String: String] = [
    "descarga": "Descarga de galería", "link_venciendo": "Link próximo a vencer",
    "pago_pendiente": "Pago pendiente", "evento_proximo": "Evento próximo",
    "quincena_vencida": "Quincena sin pagar",
]

@MainActor
@Observable
final class AlertasViewModel {
    var alertas: [NoktaAlerta] = []
    var isLoading = true
    var isMutating = false
    var errorMessage: String?
    var trabajoIdMostrado: String?
    /// Fired after every load/mutation so the caller can mirror the unread
    /// count elsewhere (e.g. RootView's sidebar badge).
    var onUnreadChange: (Int) -> Void = { _ in }

    private func notifyUnreadChange() {
        onUnreadChange(alertas.filter { !$0.leida }.count)
    }

    func load() async {
        guard !isMutating else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched: [NoktaAlerta] = try await NoktaAPI.get("/api/alertas")
            // Keep read records on the server so automatic alerts stay deduplicated.
            alertas = fetched.filter { !$0.leida }
            notifyUnreadChange()
        } catch {
            errorMessage = "No se pudieron cargar las alertas: \(error.localizedDescription)"
        }
    }

    func marcarLeida(_ id: String) async {
        await marcarLeidas(path: "/api/alertas/\(id)/leer", id: id)
    }

    func marcarTodasLeidas() async {
        await marcarLeidas(path: "/api/alertas/leer", id: nil)
    }

    private func marcarLeidas(path: String, id: String?) async {
        guard !isLoading, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            let _: OKResponse = try await NoktaAPI.put(path, body: [String: String]())
            if let id {
                alertas.removeAll { $0.id == id }
            } else {
                alertas.removeAll()
            }
            notifyUnreadChange()
        } catch {
            errorMessage = "No se pudieron marcar las alertas como leídas: \(error.localizedDescription)"
        }
    }

}

struct AlertasView: View {
    @State private var vm = AlertasViewModel()
    /// Lets RootView's sidebar badge update the instant an alert is read
    /// here, instead of waiting for its own 30s poll.
    var onUnreadChange: (Int) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Alertas").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                    Button("✓ Marcar todas leídas") { Task { await vm.marcarTodasLeidas() } }
                        .buttonStyle(.glass)
                        .disabled(vm.isLoading || vm.isMutating || vm.alertas.isEmpty)
                }

                if let errorMessage = vm.errorMessage {
                    Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                }

                if vm.alertas.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "No hay alertas")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    ForEach(vm.alertas, id: \.id) { a in
                        alertRow(a)
                    }
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task {
            vm.onUnreadChange = onUnreadChange
            await vm.load()
        }
        .refreshable { await vm.load() }
        .sheet(item: Binding(get: {
            vm.trabajoIdMostrado.map { TrabajoSheetContext(id: $0) }
        }, set: { if $0 == nil { vm.trabajoIdMostrado = nil } })) { ctx in
            NavigationStack {
                TrabajoDetailView(trabajoId: ctx.id, onBack: { vm.trabajoIdMostrado = nil })
            }
            .frame(minWidth: 980, minHeight: 560)
        }
    }

    private func alertRow(_ a: NoktaAlerta) -> some View {
        let d = a.datos
        let desc: String = {
            switch a.tipo {
            case "descarga":
                return "\(d.nombre ?? "") descargó su galería (\((d.tipo ?? "") == "todo" ? "todo" : "favoritas")) — \(FechaUtil.fechaCorta(d.fecha))"
            case "link_venciendo":
                let dias = d.diasRestantes ?? 0
                return "\(d.nombre ?? "") (\(d.codigo ?? "")) — \(dias) día\(dias != 1 ? "s" : "") restante\(dias != 1 ? "s" : "")"
            case "pago_pendiente":
                return "\(d.cliente ?? "") — \(d.servicio ?? "") — Saldo: $\(String(format: "%.2f", d.saldo ?? 0))"
            case "evento_proximo":
                return "\(d.cliente ?? "") — \(d.tipo ?? "") — \(FechaUtil.fechaCorta(d.fecha)) \(d.hora ?? "")"
            case "quincena_vencida":
                return d.mensaje ?? ""
            default:
                return ""
            }
        }()

        return HStack(alignment: .top, spacing: 14) {
            Text(alertIcons[a.tipo] ?? "🔔").font(.system(size: 20))
            VStack(alignment: .leading, spacing: 3) {
                Text(alertLabels[a.tipo] ?? a.tipo).font(.system(size: 13, weight: .medium)).foregroundStyle(NoktaPalette.cream)
                Text(desc).font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)
                HStack(spacing: 12) {
                    Text(FechaUtil.fechaHoraCorta(a.fecha)).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                    if a.tipo == "pago_pendiente" || a.tipo == "quincena_vencida", let id = d.id {
                        Button(a.tipo == "pago_pendiente" ? "Ver trabajo" : "Ver quincenas") { vm.trabajoIdMostrado = id }
                            .buttonStyle(.glass)
                    }
                    if !a.leida {
                        Button("Marcar leída") { Task { await vm.marcarLeida(a.id) } }
                            .buttonStyle(.glass)
                            .disabled(vm.isLoading || vm.isMutating)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(a.leida ? NoktaPalette.border : NoktaPalette.ember).frame(width: 3)
        }
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }
}

private struct TrabajoSheetContext: Identifiable { let id: String }

private extension FechaUtil {
    static func fechaHoraCorta(_ iso: String) -> String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = withFractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return iso }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        f.locale = Locale(identifier: "es_MX")
        return f.string(from: d)
    }
}
