import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let noktaBaseURL = "https://nokta-studio.onrender.com"

private let tipoLabels: [String: String] = [
    "boda": "Boda", "xvanios": "XV Años", "corporativo": "Corporativo",
    "deportivo": "Deportivo", "graduacion": "Graduación", "otro": "Evento",
]
private let galTabs = [("todos", "Todos"), ("activo", "Activos"), ("descargado", "Descargados"), ("expirado", "Expirados"), ("reactivado", "Reactivados")]

func copyToClipboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

@Observable
final class GaleriasViewModel {
    var clientes: [NoktaCliente] = []
    var filtro = "todos"
    var isLoading = true
    var reactivarCodigo: String?

    var galClientes: [NoktaCliente] { clientes.filter { $0.tipo != "contacto" } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let c: [NoktaCliente] = try? await NoktaAPI.get("/api/clientes") { clientes = c }
    }

    var activos: Int { galClientes.filter { $0.estado == "activo" }.count }
    var pendientes: Int { galClientes.filter { $0.estado == "activo" && ($0.descargas ?? []).isEmpty }.count }
    var reactivados: Int { galClientes.filter { !($0.reactivaciones ?? []).isEmpty }.count }

    var filtrados: [NoktaCliente] {
        switch filtro {
        case "activo": return galClientes.filter { $0.estado == "activo" }
        case "descargado": return galClientes.filter { $0.estado == "descargado" }
        case "expirado": return galClientes.filter { $0.estado == "expirado" }
        case "reactivado": return galClientes.filter { !($0.reactivaciones ?? []).isEmpty }
        default: return galClientes
        }
    }

    func diasRestantes(_ c: NoktaCliente) -> Int? {
        guard let expira = c.expira, let d = ISO8601DateFormatter().date(from: expira) ?? isoFractional.date(from: expira) else { return nil }
        return max(0, Int(ceil(d.timeIntervalSinceNow / 86400)))
    }
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    func reactivar(dias: Int) async {
        guard let codigo = reactivarCodigo else { return }
        struct Body: Encodable { let dias: Int }
        struct Resp: Decodable { let ok: Bool?; let expira: String? }
        let _: Resp? = try? await NoktaAPI.put("/api/clientes/\(codigo)/reactivar", body: Body(dias: dias))
        reactivarCodigo = nil
        await load()
    }

    func eliminar(_ codigo: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/clientes/\(codigo)")
        await load()
    }

    func crear(nombre: String, tipo: String, dias: Int, whatsapp: String) async -> String? {
        struct Body: Encodable { let nombre: String; let tipo: String; let dias: Int; let whatsapp: String }
        struct Resp: Decodable { let ok: Bool?; let cliente: NoktaCliente?; let link: String? }
        let resp: Resp? = try? await NoktaAPI.post("/api/clientes", body: Body(nombre: nombre, tipo: tipo, dias: dias, whatsapp: whatsapp))
        await load()
        return resp?.cliente?.codigo
    }
}

struct GaleriasView: View {
    @State private var vm = GaleriasViewModel()
    @State private var nuevoClienteShown = false
    @State private var eliminarConfirm: NoktaCliente?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Galerías").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                    Button("＋ Nuevo cliente") { nuevoClienteShown = true }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }

                HStack(spacing: 16) {
                    statCard("CLIENTES ACTIVOS", "\(vm.activos)", NoktaPalette.cream)
                    statCard("PENDIENTES DE DESCARGA", "\(vm.pendientes)", NoktaPalette.yellow)
                    statCard("REACTIVADOS", "\(vm.reactivados)", Color(hex: 0x6495ED))
                    statCard("TOTAL DEL AÑO", "\(vm.galClientes.count)", NoktaPalette.cream)
                }

                HStack(spacing: 8) {
                    ForEach(galTabs, id: \.0) { key, label in
                        Button(label) { vm.filtro = key }
                            .buttonStyle(.glass)
                            .tint(vm.filtro == key ? NoktaPalette.ember : nil)
                    }
                }

                if vm.filtrados.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "Sin clientes en esta categoría")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center).padding(40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        ForEach(vm.filtrados, id: \.codigo) { c in galCard(c) }
                    }
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $nuevoClienteShown) {
            NuevoClienteSheet { nombre, tipo, dias, whatsapp in
                await vm.crear(nombre: nombre, tipo: tipo, dias: dias, whatsapp: whatsapp)
            }
        }
        .sheet(item: Binding(get: {
            vm.reactivarCodigo.map { ReactivarSheetId(codigo: $0) }
        }, set: { if $0 == nil { vm.reactivarCodigo = nil } })) { ctx in
            ReactivarSheet { dias in await vm.reactivar(dias: dias) }
        }
        .alert("¿Eliminar cliente?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let c = eliminarConfirm { Task { await vm.eliminar(c.codigo) } }
            }
        } message: {
            Text("El código dejará de funcionar.")
        }
    }

    private func statCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func galCard(_ c: NoktaCliente) -> some View {
        let dias = vm.diasRestantes(c)
        let reacs = c.reactivaciones ?? []
        let link = "\(noktaBaseURL)/galeria?codigo=\(c.codigo)"
        let estadoColor: Color = c.estado == "activo" ? NoktaPalette.green : c.estado == "descargado" ? Color(hex: 0x6495ED) : NoktaPalette.red
        let estadoLabel = c.estado == "activo" ? "Activo" : c.estado == "descargado" ? "Descargado" : "Expirado"

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(c.nombre).font(.system(size: 15, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
                if !reacs.isEmpty {
                    Text("↺ \(reacs.count)x").font(.system(size: 10)).foregroundStyle(Color(hex: 0x6495ED))
                }
                Spacer()
                Text(estadoLabel).font(NoktaFont.pill).foregroundStyle(estadoColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(estadoColor.opacity(0.15), in: Capsule())
            }

            linkRow(link) { copyToClipboard(link) }
            linkRow("🔑 " + c.codigo) { copyToClipboard(c.codigo) }

            VStack(alignment: .leading, spacing: 4) {
                Text("📂 \(tipoLabels[c.tipo ?? ""] ?? c.tipo ?? "—")").font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                Text("👁 \((c.visitas ?? []).count) visitas").font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                if let dias {
                    Text("⏱ \(dias) días restantes").font(.system(size: 11)).foregroundStyle(dias <= 3 ? NoktaPalette.yellow : NoktaPalette.muted)
                } else {
                    Text("∞ Sin límite").font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                }
                if let last = (c.descargas ?? []).last {
                    Text("✅ Descargado \(FechaUtil.fechaCorta(String(last.fecha.prefix(10))))").font(.system(size: 11)).foregroundStyle(NoktaPalette.green)
                } else {
                    Text("⏳ Sin descargar").font(.system(size: 11)).foregroundStyle(NoktaPalette.yellow)
                }
            }

            HStack(spacing: 8) {
                if let url = URL(string: link) {
                    Link("👁 Ver galería", destination: url).buttonStyle(.glass)
                }
                Button("🔄 Reactivar") { vm.reactivarCodigo = c.codigo }.buttonStyle(.glass)
                if let wa = c.whatsapp, !wa.isEmpty, let url = waURL(c, wa: wa) {
                    Link("💬 WA", destination: url).buttonStyle(.glass)
                }
                Button("Eliminar", role: .destructive) { eliminarConfirm = c }
                    .buttonStyle(.glass)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func waURL(_ c: NoktaCliente, wa: String) -> URL? {
        let dias = vm.diasRestantes(c)
        let link = "\(noktaBaseURL)/galeria?codigo=\(c.codigo)"
        let limite = dias != nil ? "El acceso estará disponible por \(dias!) días." : "El acceso no tiene límite de tiempo."
        let msg = "Hola \(c.nombre), tus fotos de \(tipoLabels[c.tipo ?? ""] ?? c.tipo ?? "") ya están listas 📸\nPodés verlas y descargarlas en este link:\n\(link)\n\nTu código de acceso es: \(c.codigo)\n\(limite)"
        var comps = URLComponents(string: "https://wa.me/\(wa)")
        comps?.queryItems = [URLQueryItem(name: "text", value: msg)]
        return comps?.url
    }

    private func linkRow(_ text: String, onCopy: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("📋") { onCopy() }.buttonStyle(.glass)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(NoktaPalette.bg, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ReactivarSheetId: Identifiable { let codigo: String; var id: String { codigo } }

private struct ReactivarSheet: View {
    let onConfirm: (Int) async -> Void
    @State private var dias = 30
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reactivar acceso").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
            Picker("Días adicionales", selection: $dias) {
                Text("7 días").tag(7); Text("15 días").tag(15); Text("30 días").tag(30); Text("60 días").tag(60)
            }.pickerStyle(.menu)
            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Reactivar") { Task { await onConfirm(dias); dismiss() } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

private struct NuevoClienteSheet: View {
    let onCreate: (String, String, Int, String) async -> String?
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var tipo = "boda"
    @State private var dias = 30
    @State private var whatsapp = ""
    @State private var errorMessage: String?
    @State private var resultCodigo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nuevo cliente — Galería privada").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)

            if let resultCodigo {
                Text("✓ Cliente creado. Código: \(resultCodigo)").font(.system(size: 13)).foregroundStyle(NoktaPalette.green)
                HStack {
                    Spacer()
                    Button("Cerrar") { dismiss() }.buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }
            } else {
                field("Nombre del cliente") { TextField("Nombre completo", text: $nombre).textFieldStyle(.plain) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("TIPO DE EVENTO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                    Picker("", selection: $tipo) {
                        ForEach(Array(tipoLabels.keys.sorted()), id: \.self) { k in Text(tipoLabels[k] ?? k).tag(k) }
                    }.labelsHidden().pickerStyle(.menu)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("DÍAS DE ACCESO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                    Picker("", selection: $dias) {
                        Text("15 días").tag(15); Text("30 días").tag(30); Text("60 días").tag(60); Text("Sin límite").tag(0)
                    }.labelsHidden().pickerStyle(.menu)
                }
                field("WhatsApp del cliente (con código de país)") { TextField("50370000000", text: $whatsapp).textFieldStyle(.plain) }

                if let errorMessage {
                    Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                }
                HStack {
                    Button("Cancelar") { dismiss() }.buttonStyle(.glass)
                    Spacer()
                    Button("Crear cliente") { Task { await crear() } }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            content()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(NoktaPalette.cream)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        }
    }

    private func crear() async {
        errorMessage = nil
        guard !nombre.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el nombre del cliente"; return }
        resultCodigo = await onCreate(nombre, tipo, dias, whatsapp)
        if resultCodigo == nil { errorMessage = "No se pudo crear el cliente" }
    }
}
