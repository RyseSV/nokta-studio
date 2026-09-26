import SwiftUI

private let eventoTipos = ["Fotografía de evento", "Video de evento", "Redes sociales", "Edición de video", "Paquete completo"]
private let diaNombres = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]

enum CalTipo { case evento, cobrado, porCobrar, retrasado
    var color: Color {
        switch self {
        case .evento: NoktaTheme.marca
        case .cobrado: NoktaTheme.exito
        case .porCobrar: NoktaTheme.aviso
        case .retrasado: NoktaTheme.error
        }
    }
    var nombre: String {
        switch self {
        case .evento: "Evento"
        case .cobrado: "Cobrado"
        case .porCobrar: "Por cobrar"
        case .retrasado: "Retrasado"
        }
    }
}

struct CalItem: Identifiable {
    let id: String
    let label: String
    let tipo: CalTipo
    var monto: Double? = nil
    let action: () -> Void
}

/// A timed event placed on the week grid (hours as decimals, e.g. 16.5).
struct CalBloque: Identifiable {
    let id: String
    let titulo: String
    let horario: String
    let inicio: Double
    let fin: Double
    let tipo: CalTipo
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
    var estados: [NoktaClienteEstado] = []
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
        async let es: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        let (e, t, r) = await (ev, tr, es)
        eventos = e ?? []
        trabajos = t ?? []
        estados = r ?? []
    }

    /// Sunday (start of day) of the week shown in the hours grid.
    var inicioSemana: Date = CalendarioViewModel.domingo(de: Date())

    static func domingo(de fecha: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        let dia = cal.startOfDay(for: fecha)
        let wd = cal.component(.weekday, from: dia) - 1
        return cal.date(byAdding: .day, value: -wd, to: dia) ?? dia
    }

    var diasSemana: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: inicioSemana) }
    }

    var tituloSemana: String {
        let d = diasSemana
        guard let a = d.first, let b = d.last else { return "" }
        let c = Calendar.current
        let (da, ma) = (c.component(.day, from: a), c.component(.month, from: a) - 1)
        let (db, mb) = (c.component(.day, from: b), c.component(.month, from: b) - 1)
        return ma == mb
            ? "Semana del \(da) al \(db) de \(FechaUtil.mesesCompletos[mb].lowercased())"
            : "Semana del \(da) de \(FechaUtil.mesesCompletos[ma].lowercased()) al \(db) de \(FechaUtil.mesesCompletos[mb].lowercased())"
    }

    /// Keeps the mini month in step with the week being shown.
    private func sincronizarMes() {
        let medio = Calendar.current.date(byAdding: .day, value: 3, to: inicioSemana) ?? inicioSemana
        month = Calendar.current.component(.month, from: medio) - 1
        year = Calendar.current.component(.year, from: medio)
    }

    func moverSemana(_ n: Int) {
        inicioSemana = Calendar.current.date(byAdding: .day, value: 7 * n, to: inicioSemana) ?? inicioSemana
        sincronizarMes()
    }

    func elegirDia(_ dateStr: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateStr) else { return }
        inicioSemana = Self.domingo(de: d)
    }

    func irAHoy() {
        month = Calendar.current.component(.month, from: Date()) - 1
        year = Calendar.current.component(.year, from: Date())
        inicioSemana = Self.domingo(de: Date())
    }

    /// "16:00", "4:30 pm", "9" → decimal hours; nil when unreadable.
    static func hora(_ texto: String?) -> Double? {
        guard let t = texto?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        let pm = t.contains("pm") || t.contains("p.m"), am = t.contains("am") || t.contains("a.m")
        let nums = t.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        guard var h = nums.first, h < 24 else { return nil }
        let m = nums.count > 1 ? nums[1] : 0
        if pm && h < 12 { h += 12 }
        if am && h == 12 { h = 0 }
        return h + min(m, 59) / 60
    }

    func bloques(for dateStr: String) -> [CalBloque] {
        eventos.filter { $0.fecha == dateStr }.compactMap { ev in
            guard let ini = Self.hora(ev.horaInicio) else { return nil }
            let fin = max(ini + 0.5, Self.hora(ev.horaFin) ?? ini + 1)
            let horario = (ev.horaInicio ?? "") + (ev.horaFin.map { $0.isEmpty ? "" : " – \($0)" } ?? "")
            return CalBloque(id: ev.id, titulo: ev.titulo ?? ev.tipo ?? "Evento", horario: horario, inicio: ini, fin: fin, tipo: .evento) { [weak self] in
                self?.eventoMostrado = ev
            }
        }
    }

    /// Everything without a usable time: quincena charges and untimed events.
    func todoElDia(for dateStr: String) -> [CalItem] {
        let conHora = Set(bloques(for: dateStr).map(\.id))
        return items(for: dateStr).filter { !conHora.contains($0.id) }
    }

    var resumenMes: (eventos: Int, cobrado: Double, porCobrar: Double, retrasados: Int) {
        let todos = days.compactMap { $0 }.flatMap { items(for: $0.dateStr) }
        return (
            todos.filter { $0.tipo == .evento }.count,
            todos.filter { $0.tipo == .cobrado }.reduce(0) { $0 + ($1.monto ?? 0) },
            todos.filter { $0.tipo == .porCobrar || $0.tipo == .retrasado }.reduce(0) { $0 + ($1.monto ?? 0) },
            todos.filter { $0.tipo == .retrasado }.count
        )
    }

    /// What's coming in the displayed month (from today on when it's the
    /// current month), in date order — for the "Próximos" panel.
    var proximos: [(fecha: String, item: CalItem)] {
        let hoy = isoDay(Date())
        return days.compactMap { $0 }
            .filter { $0.dateStr >= hoy }
            .flatMap { d in items(for: d.dateStr).map { (d.dateStr, $0) } }
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

    func isoDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func items(for dateStr: String) -> [CalItem] {
        var items: [CalItem] = eventos.filter { $0.fecha == dateStr }.map { ev in
            CalItem(id: ev.id, label: ev.titulo ?? ev.tipo ?? "Evento", tipo: .evento, monto: ev.monto) { [weak self] in
                self?.eventoMostrado = ev
            }
        }
        // Same relationship rule as IngresosCalculator: a paused/cancelled client
        // has nothing left to collect — only already-paid history stays.
        func activo(_ t: NoktaTrabajo) -> Bool {
            (estados.first { $0.nombre == t.cliente }?.estado ?? t.estadoContrato ?? "activo").lowercased() == "activo"
        }
        for t in trabajos where t.grupoResuelto == "B" {
            for q in t.quincenas ?? [] where q.estado != "oculta" && (q.estado == "pagado" || activo(t)) {
                var qDate = ""
                if q.estado == "pagado", let fp = q.fechaPago, !fp.isEmpty {
                    qDate = String(fp.prefix(10))
                } else if q.estado != "pagado" {
                    qDate = "\(q.periodo)-\(q.q == 1 ? "01" : "15")"
                }
                guard qDate == dateStr else { continue }
                let tipo: CalTipo = q.estado == "pagado" ? .cobrado : q.estado == "retrasado" ? .retrasado : .porCobrar
                items.append(CalItem(id: "\(t.id)-\(q.periodo)-\(q.q)", label: "\(t.cliente) · Q\(q.q)", tipo: tipo, monto: q.monto ?? (t.pagoMensual ?? 0) / 2) { [weak self] in
                    self?.trabajoIdMostrado = t.id
                })
            }
        }
        // Class sessions ("Clases" etc.): each one on its own date.
        for t in trabajos {
            for ses in t.sesiones ?? [] where ses.fecha == dateStr && ses.estado != "oculta" && ses.estado != "cancelado" {
                let pagada = ses.estado == "pagado"
                guard pagada || activo(t) else { continue }
                items.append(CalItem(id: "\(t.id)-ses-\(ses.id)", label: "\(t.cliente) · Clase", tipo: pagada ? .cobrado : .porCobrar, monto: ses.monto) { [weak self] in
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
    @State private var aparecio = false
    /// +1 moving forward a week, -1 backward — drives the slide direction.
    @State private var direccion: CGFloat = 1
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif

    private let altoHora: CGFloat = 40
    private let anchoHoras: CGFloat = 52

    /// Timed events of the week being shown.
    private var bloquesSemana: [CalBloque] { vm.diasSemana.flatMap { vm.bloques(for: vm.isoDay($0)) } }

    /// Visible hours: 9 am–7 pm (10 rows), stretched only when an event
    /// falls outside that window.
    private var rangoHoras: (inicio: Int, fin: Int) {
        var ini = 9.0, fin = 19.0
        for b in bloquesSemana { ini = min(ini, b.inicio.rounded(.down)); fin = max(fin, b.fin.rounded(.up)) }
        return (max(0, Int(ini)), min(24, Int(fin)))
    }
    private var horaInicio: Int { rangoHoras.inicio }
    private var horaFin: Int { rangoHoras.fin }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NoktaEncabezado(titulo: "Calendario", subtitulo: vm.tituloSemana) {
                    navegacion
                    Button { agregarEventoShown = true } label: {
                        Label("Evento", systemImage: "plus").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(NoktaBotonPrimario())
                }
                .noktaEntrada(aparecio, 0)

                if compacto {
                    miniMes.noktaEntrada(aparecio, 1)
                    agendaCompacta.noktaEntrada(aparecio, 2)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            miniMes
                            resumen
                        }
                        .frame(width: 250)
                        .noktaEntrada(aparecio, 1)
                        semana.noktaEntrada(aparecio, 2)
                    }
                }
            }
            .padding(.horizontal, compacto ? 16 : 44)
            .padding(.vertical, compacto ? 16 : 36)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .task {
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            await vm.load()
        }
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

    // MARK: - Navigation

    private var navegacion: some View {
        HStack(spacing: 2) {
            Button { direccion = -1; withAnimation(.snappy(duration: 0.4)) { vm.moverSemana(-1) } } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .help("Semana anterior")
            Button {
                direccion = vm.inicioSemana < CalendarioViewModel.domingo(de: Date()) ? 1 : -1
                withAnimation(.snappy(duration: 0.4)) { vm.irAHoy() }
            } label: {
                Text("Hoy").font(NoktaFont.poppins(12, .medium)).padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
            }
            Button { direccion = 1; withAnimation(.snappy(duration: 0.4)) { vm.moverSemana(1) } } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .help("Semana siguiente")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(NoktaTheme.texto)
        .padding(3)
        .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
    }

    // MARK: - Mini month

    private var miniMes: some View {
        let semana = Set(vm.diasSemana.map { vm.isoDay($0) })
        let columnas = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(vm.titulo).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
                Spacer()
                Button { withAnimation(.snappy) { vm.prev() } } label: { Image(systemName: "chevron.left") }
                Button { withAnimation(.snappy) { vm.next() } } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NoktaTheme.textoSuave)
            LazyVGrid(columns: columnas, spacing: 2) {
                ForEach(Array(diaNombres.enumerated()), id: \.offset) { _, d in
                    Text(String(d.prefix(1))).font(NoktaFont.poppins(9, .medium)).foregroundStyle(NoktaTheme.textoTenue)
                        .frame(height: 20)
                }
                ForEach(Array(vm.days.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        let tipos = vm.items(for: cell.dateStr).map(\.tipo)
                        let enSemana = semana.contains(cell.dateStr)
                        Button {
                            let hacia: CGFloat = cell.dateStr < vm.isoDay(vm.inicioSemana) ? -1 : 1
                            direccion = hacia
                            withAnimation(.snappy(duration: 0.4)) { vm.elegirDia(cell.dateStr) }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(cell.day)")
                                    .font(NoktaFont.poppins(11, cell.isToday ? .medium : .regular))
                                    .foregroundStyle(cell.isToday ? Color.white : (enSemana ? NoktaTheme.texto : NoktaTheme.textoSuave))
                                    .frame(width: 24, height: 24)
                                    .background(cell.isToday ? NoktaTheme.marca : .clear, in: Circle())
                                Circle().fill(tipos.first?.color ?? .clear).frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(enSemana ? NoktaTheme.superficie2 : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
        .noktaCard(padding: 16)
    }

    private var resumen: some View {
        let r = vm.resumenMes
        return VStack(alignment: .leading, spacing: 12) {
            Text("En \(FechaUtil.mesesCompletos[vm.month].lowercased())")
                .font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
            fila("Eventos", valor: "\(r.eventos)", color: NoktaTheme.marca)
            fila("Cobrado", valor: NoktaFormato.dinero(r.cobrado), color: NoktaTheme.exito)
            fila("Por cobrar", valor: NoktaFormato.dinero(r.porCobrar), color: NoktaTheme.aviso)
            if r.retrasados > 0 {
                fila("Retrasados", valor: "\(r.retrasados)", color: NoktaTheme.error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard(padding: 16)
        .animation(.snappy, value: vm.month)
    }

    private func fila(_ texto: String, valor: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(texto).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            Spacer()
            Text(valor).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Week grid

    private var semana: some View {
        let dias = vm.diasSemana
        let hoy = vm.isoDay(Date())
        let clave = vm.isoDay(vm.inicioSemana)
        return VStack(spacing: 0) {
            // Day headers
            HStack(spacing: 0) {
                Color.clear.frame(width: anchoHoras, height: 1)
                ForEach(dias, id: \.self) { d in
                    let iso = vm.isoDay(d), esHoy = iso == hoy
                    VStack(spacing: 2) {
                        Text(diaNombres[Calendar.current.component(.weekday, from: d) - 1].uppercased())
                            .font(NoktaFont.poppins(10, .medium)).tracking(1.2)
                            .foregroundStyle(esHoy ? NoktaTheme.marca : NoktaTheme.textoTenue)
                        Text("\(Calendar.current.component(.day, from: d))")
                            .font(NoktaFont.poppins(22, .light)).tracking(-0.6)
                            .foregroundStyle(esHoy ? NoktaTheme.marca : NoktaTheme.texto)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }

            // All-day row
            HStack(alignment: .top, spacing: 0) {
                Text("TODO EL\nDÍA").font(NoktaFont.poppins(8, .medium)).tracking(1).multilineTextAlignment(.trailing)
                    .foregroundStyle(NoktaTheme.textoTenue)
                    .frame(width: anchoHoras - 8, alignment: .trailing).padding(.trailing, 8).padding(.top, 8)
                ForEach(dias, id: \.self) { d in
                    let lista = vm.todoElDia(for: vm.isoDay(d))
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(lista.prefix(3)) { item in chip(item) }
                        if lista.count > 3 {
                            Text("+\(lista.count - 3) más").font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoSuave).padding(.leading, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                    .padding(4)
                    .overlay(alignment: .leading) { Rectangle().fill(NoktaTheme.borde).frame(width: 1) }
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }

            // Hours
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(horaInicio..<horaFin, id: \.self) { h in
                        Text(etiquetaHora(h)).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                            .frame(width: anchoHoras - 8, height: altoHora, alignment: .trailing)
                            .padding(.trailing, 8)
                            .overlay(alignment: .top) { Rectangle().fill(NoktaTheme.borde.opacity(0.7)).frame(height: 1) }
                    }
                }
                ForEach(dias, id: \.self) { d in
                    columnaDia(vm.isoDay(d), esHoy: vm.isoDay(d) == hoy)
                }
            }
            .id(clave)
            .transition(.asymmetric(
                insertion: .offset(x: 50 * direccion).combined(with: .opacity),
                removal: .offset(x: -50 * direccion).combined(with: .opacity)
            ))
        }
        // Size to content — otherwise the card stretched to the left column's
        // height and the day headers floated in empty space.
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .noktaCard(padding: 0)
    }

    private func etiquetaHora(_ h: Int) -> String {
        h == 12 ? "12 pm" : h < 12 ? "\(h) am" : "\(h - 12) pm"
    }

    private func columnaDia(_ dateStr: String, esHoy: Bool) -> some View {
        let bloques = conCarriles(vm.bloques(for: dateStr))
        let alto = altoHora * CGFloat(horaFin - horaInicio)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Hour lines
                VStack(spacing: 0) {
                    ForEach(horaInicio..<horaFin, id: \.self) { _ in
                        Rectangle().fill(NoktaTheme.borde.opacity(0.7)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                }
                ForEach(Array(bloques.enumerated()), id: \.element.bloque.id) { i, b in
                    let ancho = (geo.size.width - 6) / CGFloat(b.carriles)
                    BloqueEvento(bloque: b.bloque, orden: i)
                        .frame(width: ancho - 3, height: max(24, CGFloat(b.bloque.fin - b.bloque.inicio) * altoHora - 3))
                        .offset(x: 3 + ancho * CGFloat(b.carril), y: CGFloat(b.bloque.inicio - Double(horaInicio)) * altoHora + 1)
                }
                if esHoy { lineaAhora }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .background(esHoy ? NoktaTheme.marca.opacity(0.02) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(NoktaTheme.borde).frame(width: 1) }
    }

    /// Overlapping events sit side by side instead of on top of each other.
    private func conCarriles(_ lista: [CalBloque]) -> [(bloque: CalBloque, carril: Int, carriles: Int)] {
        let orden = lista.sorted { $0.inicio < $1.inicio }
        var finPorCarril: [Double] = []
        var asignados: [(CalBloque, Int)] = []
        for b in orden {
            if let libre = finPorCarril.firstIndex(where: { $0 <= b.inicio }) {
                finPorCarril[libre] = b.fin; asignados.append((b, libre))
            } else {
                finPorCarril.append(b.fin); asignados.append((b, finPorCarril.count - 1))
            }
        }
        let total = max(1, finPorCarril.count)
        return asignados.map { ($0.0, $0.1, total) }
    }

    private var lineaAhora: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let c = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
            let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            if h >= Double(horaInicio) && h <= Double(horaFin) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(NoktaTheme.marca).frame(height: 2)
                        .shadow(color: NoktaTheme.marca.opacity(0.8), radius: 4)
                    Circle().fill(NoktaTheme.marca).frame(width: 9, height: 9).offset(x: -4)
                }
                .offset(y: CGFloat(h - Double(horaInicio)) * altoHora - 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func chip(_ item: CalItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 5) {
                Circle().fill(item.tipo.color).frame(width: 5, height: 5)
                Text(item.label).font(NoktaFont.poppins(10)).lineLimit(1).foregroundStyle(NoktaTheme.texto)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.tipo.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.label + (item.monto.map { " · " + NoktaFormato.dinero($0) } ?? ""))
    }

    // MARK: - iPhone: agenda of the week

    private var agendaCompacta: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(vm.diasSemana, id: \.self) { d in
                let iso = vm.isoDay(d), esHoy = iso == vm.isoDay(Date())
                let horarios = vm.bloques(for: iso).sorted { $0.inicio < $1.inicio }
                let resto = vm.todoElDia(for: iso)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text(diaNombres[Calendar.current.component(.weekday, from: d) - 1].uppercased())
                            .font(NoktaFont.poppins(9, .medium)).tracking(1)
                        Text("\(Calendar.current.component(.day, from: d))").font(NoktaFont.poppins(20, .light))
                    }
                    .foregroundStyle(esHoy ? NoktaTheme.marca : NoktaTheme.texto)
                    .frame(width: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        if horarios.isEmpty && resto.isEmpty {
                            Text("Libre").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue).padding(.top, 8)
                        }
                        ForEach(horarios) { b in
                            Button(action: b.action) {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2).fill(b.tipo.color).frame(width: 3)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(b.titulo).font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                                        Text(b.horario).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoSuave)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(b.tipo.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(resto) { chip($0) }
                    }
                }
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
            }
        }
        .noktaCard(padding: 16)
    }
}

/// One timed event on the grid: grows in from its top edge, lifts on hover.
private struct BloqueEvento: View {
    let bloque: CalBloque
    let orden: Int
    @State private var visible = false
    @State private var encima = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = bloque.tipo.color
        let forma = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: bloque.action) {
            HStack(spacing: 0) {
                Rectangle().fill(c).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bloque.titulo).font(NoktaFont.poppins(11, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(2)
                    Text(bloque.horario).font(NoktaFont.poppins(9)).foregroundStyle(NoktaTheme.textoSuave).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(c.opacity(encima ? 0.26 : 0.17), in: forma)
            .clipShape(forma)
            .overlay(forma.strokeBorder(c.opacity(encima ? 0.8 : 0.25), lineWidth: 1))
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .scaleEffect(x: 1, y: visible ? 1 : 0.2, anchor: .top)
        .opacity(visible ? 1 : 0)
        .scaleEffect(encima ? 1.03 : 1)
        .shadow(color: .black.opacity(encima ? 0.3 : 0), radius: 10, y: 5)
        .zIndex(encima ? 1 : 0)
        .onHover { h in withAnimation(.spring(duration: 0.25)) { encima = h } }
        .help(bloque.titulo + " · " + bloque.horario)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.15).delay(0.15 + Double(orden) * 0.09)) { visible = true }
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
            HStack(spacing: 10) {
                Image(systemName: "calendar").font(.system(size: 15, weight: .light)).foregroundStyle(NoktaTheme.marca)
                    .frame(width: 36, height: 36).background(NoktaTheme.marcaSuave, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(evento.titulo ?? "Evento").font(NoktaFont.poppins(18, .light)).tracking(-0.4).foregroundStyle(NoktaTheme.texto)
            }
            field("TIPO", evento.tipo ?? "—")
            field("FECHA", FechaUtil.fechaCorta(evento.fecha))
            field("HORARIO", (evento.horaInicio ?? "—") + (evento.horaFin.map { " → \($0)" } ?? ""))
            field("LUGAR", evento.lugar ?? "—")
            field("MONTO", NoktaFormato.dinero(evento.monto ?? 0))
            field("ANTICIPO", NoktaFormato.dinero(evento.anticipo ?? 0))
            HStack {
                Button("Cerrar") { dismiss() }.buttonStyle(NoktaBotonSecundario())
                Spacer()
                Button(role: .destructive) { eliminarConfirm = true } label: {
                    Label("Eliminar", systemImage: "trash").foregroundStyle(NoktaTheme.error)
                }
                .buttonStyle(NoktaBotonSecundario())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 380)
        .background(NoktaTheme.superficie)
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
            Text(label).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
            Text(value).font(NoktaFont.poppins(14)).foregroundStyle(NoktaTheme.texto)
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
            Text("Agregar evento").font(NoktaFont.poppins(22, .light)).tracking(-0.6).foregroundStyle(NoktaTheme.texto)
            Text("Aparecerá en el calendario del día elegido.").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave).padding(.top, -8)

            field("Cliente") { TextField("Nombre del cliente", text: $cliente).textFieldStyle(.plain) }
            VStack(alignment: .leading, spacing: 6) {
                Text("TIPO DE SERVICIO").font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
                Picker("", selection: $tipo) {
                    ForEach(eventoTipos, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }
            DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
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
                Label(errorMessage, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }

            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario())
                Spacer()
                Button("Guardar evento") { Task { await guardar() } }
                    .buttonStyle(NoktaBotonPrimario())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 400)
        .background(NoktaTheme.superficie)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
            content()
                .font(NoktaFont.poppins(13))
                .padding(.horizontal, 12).frame(height: 38)
                .foregroundStyle(NoktaTheme.texto)
                .background(NoktaTheme.superficie2.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
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
