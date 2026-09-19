import SwiftUI

private let eventoTipos = ["Fotografía de evento", "Video de evento", "Redes sociales", "Edición de video", "Paquete completo"]
private let diaNombres = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]

struct CalItem: Identifiable {
    let id: String
    let label: String
    let background: Color
    let foreground: Color
    let action: () -> Void
}

struct CalDay {
    let day: Int
    let dateStr: String
    let isToday: Bool
}

@Observable
final class CalendarioViewModel {
    var eventos: [NoktaEvento] = []
    var trabajos: [NoktaTrabajo] = []
    var month: Int
    var year: Int
    var eventoMostrado: NoktaEvento?
    var trabajoIdMostrado: String?

    init() {
        let now = Calendar.current
        month = now.component(.month, from: Date()) - 1
        year = now.component(.year, from: Date())
    }

    func load() async {
        async let ev: [NoktaEvento]? = try? NoktaAPI.get("/api/eventos")
        async let tr: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        let (e, t) = await (ev, tr)
        eventos = e ?? []
        trabajos = t ?? []
    }

    func prev() { month -= 1; if month < 0 { month = 11; year -= 1 } }
    func next() { month += 1; if month > 11 { month = 0; year += 1 } }

    var titulo: String { "\(FechaUtil.mesesCompletos[month]) \(String(year))" }

    var days: [CalDay?] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month + 1, day: 1)) else { return [] }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) - 1 // 0 = Sunday
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let today = Date()
        let todayStr = isoDay(today)

        var result: [CalDay?] = Array(repeating: nil, count: firstWeekday)
        for d in 1...daysInMonth {
            let dateStr = String(format: "%04d-%02d-%02d", year, month + 1, d)
            result.append(CalDay(day: d, dateStr: dateStr, isToday: dateStr == todayStr))
        }
        return result
    }

    private func isoDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func items(for dateStr: String) -> [CalItem] {
        var items: [CalItem] = eventos.filter { $0.fecha == dateStr }.map { ev in
            CalItem(id: ev.id, label: ev.titulo ?? ev.tipo ?? "Evento", background: NoktaPalette.ember.opacity(0.25), foreground: NoktaPalette.cream) { [weak self] in
                self?.eventoMostrado = ev
            }
        }
        for t in trabajos where t.grupoResuelto == "B" {
            for q in t.quincenas ?? [] {
                var qDate = ""
                if q.estado == "pagado", let fp = q.fechaPago, !fp.isEmpty {
                    qDate = String(fp.prefix(10))
                } else if q.estado != "pagado" {
                    qDate = "\(q.periodo)-\(q.q == 1 ? "01" : "15")"
                }
                guard qDate == dateStr else { continue }
                let color: Color = q.estado == "pagado" ? NoktaPalette.green : q.estado == "retrasado" ? NoktaPalette.overdue : NoktaPalette.yellow
                let label = q.estado == "pagado" ? "✓ \(t.cliente) Q\(q.q)" : "$ \(t.cliente) Q\(q.q)"
                items.append(CalItem(id: "\(t.id)-\(q.periodo)-\(q.q)", label: label, background: color, foreground: .black) { [weak self] in
                    self?.trabajoIdMostrado = t.id
                })
            }
        }
        return items
    }
}

struct CalendarioView: View {
    @State private var vm = CalendarioViewModel()
    @State private var agregarEventoShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Calendario").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                    Button("＋ Agregar evento") { agregarEventoShown = true }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }

                HStack {
                    Button { vm.prev() } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass)
                    Text(vm.titulo).font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
                        .frame(minWidth: 180).multilineTextAlignment(.center)
                    Button { vm.next() } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                calendarGrid
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $agregarEventoShown) {
            AgregarEventoSheet { await vm.load() }
        }
        .sheet(item: $vm.eventoMostrado) { ev in
            EventoDetailSheet(evento: ev) { await vm.load() }
        }
        .sheet(item: Binding(get: {
            vm.trabajoIdMostrado.map { TrabajoSheetId(id: $0) }
        }, set: { if $0 == nil { vm.trabajoIdMostrado = nil } })) { ctx in
            NavigationStack {
                TrabajoDetailView(trabajoId: ctx.id, onBack: { vm.trabajoIdMostrado = nil })
            }
            .frame(minWidth: 980, minHeight: 560)
        }
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(diaNombres, id: \.self) { d in
                Text(d).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
            }
            ForEach(Array(vm.days.enumerated()), id: \.offset) { _, cell in
                if let cell {
                    dayCell(cell)
                } else {
                    RoundedRectangle(cornerRadius: NoktaRadius.button).fill(NoktaPalette.card.opacity(0.3))
                        .frame(minHeight: 90)
                }
            }
        }
    }

    private func dayCell(_ cell: CalDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(cell.day)").font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)
            ForEach(vm.items(for: cell.dateStr)) { item in
                Button(action: item.action) {
                    Text(item.label)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.background, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(item.foreground)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(NoktaPalette.card, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        .overlay {
            if cell.isToday {
                RoundedRectangle(cornerRadius: NoktaRadius.button).stroke(NoktaPalette.ember, lineWidth: 1)
            }
        }
    }
}

private struct TrabajoSheetId: Identifiable { let id: String }

private struct EventoDetailSheet: View {
    let evento: NoktaEvento
    let onChange: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var eliminarConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(evento.titulo ?? "Evento").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
            field("TIPO", evento.tipo ?? "—")
            field("FECHA", FechaUtil.fechaCorta(evento.fecha))
            field("HORARIO", (evento.horaInicio ?? "—") + (evento.horaFin.map { " → \($0)" } ?? ""))
            field("LUGAR", evento.lugar ?? "—")
            field("MONTO", "$" + String(format: "%.2f", evento.monto ?? 0))
            field("ANTICIPO", "$" + String(format: "%.2f", evento.anticipo ?? 0))
            HStack {
                Spacer()
                Button(role: .destructive) { eliminarConfirm = true } label: {
                    Text("🗑 Eliminar")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(24)
        .frame(width: 360)
        .alert("¿Eliminar este evento?", isPresented: $eliminarConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                Task {
                    struct Resp: Decodable { let ok: Bool? }
                    let _: Resp? = try? await NoktaAPI.delete("/api/eventos/\(evento.id)")
                    await onChange()
                    dismiss()
                }
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text(value).font(.system(size: 14)).foregroundStyle(NoktaPalette.cream)
        }
    }
}

private struct AgregarEventoSheet: View {
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cliente = ""
    @State private var tipo = eventoTipos[0]
    @State private var fecha = Date()
    @State private var horaInicio = ""
    @State private var horaFin = ""
    @State private var lugar = ""
    @State private var monto = ""
    @State private var anticipo = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agregar evento al calendario").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)

            field("Cliente") { TextField("Nombre del cliente", text: $cliente).textFieldStyle(.plain) }
            VStack(alignment: .leading, spacing: 6) {
                Text("TIPO DE SERVICIO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                Picker("", selection: $tipo) {
                    ForEach(eventoTipos, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }
            DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
            HStack {
                field("Hora inicio") { TextField("HH:MM", text: $horaInicio).textFieldStyle(.plain) }
                field("Hora fin") { TextField("HH:MM", text: $horaFin).textFieldStyle(.plain) }
            }
            field("Lugar") { TextField("Lugar", text: $lugar).textFieldStyle(.plain) }
            HStack {
                field("Monto ($)") { TextField("0.00", text: $monto).textFieldStyle(.plain) }
                field("Anticipo ($)") { TextField("0.00", text: $anticipo).textFieldStyle(.plain) }
            }

            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Guardar") { Task { await guardar() } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            content()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(NoktaPalette.cream)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guardar() async {
        errorMessage = nil
        guard !cliente.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el nombre del cliente"; return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var fields: [String: AnyEncodableValue] = [
            "titulo": .string("\(cliente) — \(tipo)"),
            "tipo": .string(tipo),
            "fecha": .string(f.string(from: fecha)),
            "horaInicio": .string(horaInicio),
            "horaFin": .string(horaFin),
            "lugar": .string(lugar),
        ]
        if let m = Double(monto) { fields["monto"] = .double(m) }
        if let a = Double(anticipo) { fields["anticipo"] = .double(a) }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.post("/api/eventos", body: AnyEncodableDict(fields))
        await onSaved()
        dismiss()
    }
}
