import Foundation

/// A cotización/recibo, as created by the Assistant — enough fields to
/// render the same PDF layout the web's `buildDocHTML()` produces.
struct DocumentoParaPDF {
    var numero: String
    var tipo: String   // cotizacion | recibo
    var clienteNombre: String
    var empresa: String?
    var telefono: String?
    var email: String?
    var fechaEmision: String
    var servicios: [(descripcion: String, monto: Double)]
    var notas: String?

    var total: Double { servicios.reduce(0) { $0 + $1.monto } }
    var fileName: String { "\(numero)_\(clienteNombre)" }
}

/// Fields for the client services contract — see `PDFTemplates.contrato()`.
/// Mirrors admin.html's `contratoHTML()` field-for-field so a contract
/// generated from either platform reads identically.
struct ContratoParaPDF: Encodable {
    var trabajoId: String?
    var ciudad: String
    var fechaContrato: String
    var clienteNombre: String
    var clienteDui: String
    var clienteTelefono: String
    var clienteEmail: String
    var clienteDireccion: String
    var servicioTipo: String
    var servicioFecha: String
    var servicioLugar: String
    var entregables: String
    var anticipoMonto: Double
    var anticipoFecha: String
    var saldoMonto: Double
    var saldoFecha: String
    var plazoDias: String
    var mora: Double = 10

    var fileName: String { "Contrato_\(clienteNombre)" }
}

/// Shared by TrabajoDetailView (generate from a trabajo already open) and
/// ContratosView (generate from the "+ Nuevo contrato" trabajo picker) so
/// the render+save-to-history step isn't duplicated between the two.
enum ContratoGenerator {
    static func generar(_ datos: ContratoParaPDF) async throws -> URL {
        let html = PDFTemplates.contrato(datos)
        let url = try await PDFRenderer().renderToPDF(html: html, suggestedName: datos.fileName)
        // Best-effort: the PDF above is already generated and returned either
        // way — a failed save here shouldn't block or alarm about the PDF the
        // caller already has in hand, just leave it out of the history list.
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.post("/api/contratos", body: datos)
        return url
    }
}

/// Rebuilds the exact HTML/CSS `buildDocHTML()` in admin.html uses (same
/// colors, layout, typography) so a PDF generated from the Assistant looks
/// identical to one downloaded from the Documentos page — rendered via
/// WKWebView instead of html2pdf.js, since there's no browser here.
enum PDFTemplates {
    /// The real brush-lockup logo (`img/logo/nokta_lockup_color_transparent.png`,
    /// bundled at Resources/Images), inlined as base64 so it renders even
    /// though `PDFRenderer` loads the HTML with no base URL to resolve a
    /// relative image path against. Falls back to a plain text wordmark if
    /// the resource is ever missing from the bundle, rather than a broken
    /// image icon.
    private static let logoDataURI: String? = {
        guard let url = Bundle.main.url(forResource: "nokta_lockup_color_transparent", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }()

    private static func logoTag(height: Int) -> String {
        guard let logoDataURI else { return logoFallback }
        return "<img src=\"\(logoDataURI)\" alt=\"Nokta Studio\" style=\"height:\(height)px;width:auto;display:block\">"
    }

    private static let logoFallback = """
    <div style="font-size:20px;font-weight:700;color:#1C1C1A">nokta<span style="color:#B85228">.</span></div>
    <div style="font-size:9px;letter-spacing:3px;color:#888;margin-top:2px">NOKTA STUDIO</div>
    """

    // MARK: - Estilo "tarjeta cálida" (2026-09): fondo crema, documento como
    // tarjeta blanca con franja naranja, datos en bloques y total grande.
    // Mismo diseño que los PDFs del panel web.

    /// Poppins incrustada (el proceso de WebKit no ve las fuentes registradas
    /// por la app), para que el PDF se vea igual en cualquier equipo.
    private static let fuentesCSS: String = {
        let pesos: [(String, Int)] = [("Poppins-Light", 300), ("Poppins-Regular", 400), ("Poppins-Medium", 500), ("Poppins-SemiBold", 600)]
        return pesos.compactMap { nombre, peso in
            guard let url = Bundle.main.url(forResource: nombre, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return "@font-face{font-family:'Poppins';font-weight:\(peso);src:url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype')}"
        }.joined()
    }()

    static let calidaCSS = """
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{background:#F3EEE6;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    body{font-family:'Poppins',-apple-system,'Helvetica Neue',sans-serif;color:#1C1C1A;padding:48px}
    .card{background:#fff;border-radius:22px;padding:44px 44px 40px 54px;position:relative;overflow:hidden;box-shadow:0 14px 40px -18px rgba(60,40,20,.28)}
    .card::before{content:"";position:absolute;left:0;top:0;bottom:0;width:9px;background:linear-gradient(#D0673A,#B85228)}
    .top{display:flex;justify-content:space-between;align-items:center;gap:16px}
    .chip{font-size:10px;font-weight:600;letter-spacing:.14em;padding:6px 14px;border-radius:99px;background:#F3EEE6;color:#B85228;white-space:nowrap}
    .chip.ok{background:#E4F2EA;color:#2E8B5A}
    h1{margin:40px 0 0;font-size:40px;font-weight:300;letter-spacing:-.04em;line-height:1.05}
    .num{font-size:12px;color:#999;margin-top:8px}
    .blocks{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:32px}
    .blk{background:#FAF7F2;border-radius:14px;padding:16px 18px}
    .blk small{display:block;font-size:9px;letter-spacing:.2em;color:#B85228;font-weight:600;margin-bottom:6px;text-transform:uppercase}
    .blk b{font-size:13.5px;font-weight:500}
    .blk span{display:block;font-size:11.5px;color:#888;margin-top:3px}
    table.lista{width:100%;border-collapse:collapse;margin-top:26px}
    table.lista th{font-size:9px;letter-spacing:.2em;color:#B85228;font-weight:600;text-transform:uppercase;text-align:left;padding:0 0 8px}
    table.lista th:last-child{text-align:right}
    table.lista td{font-size:13px;padding:12px 0;border-bottom:1px dashed #E6DFD4}
    table.lista td:first-child{color:#666}
    table.lista td:last-child{text-align:right;font-weight:500;color:#1C1C1A}
    .total{margin-top:22px;display:flex;justify-content:space-between;align-items:baseline}
    .total span{font-size:13px;color:#888}
    .total b{font-size:46px;font-weight:300;letter-spacing:-.05em}
    .total b i{font-style:normal;color:#B85228}
    .nota{margin-top:26px;padding:14px 16px;background:#FAF7F2;border-radius:12px;font-size:11.5px;color:#555;line-height:1.6;white-space:pre-wrap}
    .nota strong{display:block;font-size:9px;letter-spacing:.2em;color:#B85228;text-transform:uppercase;margin-bottom:4px}
    .gracias{margin-top:28px;font-size:12.5px;color:#666}
    .puntos{position:absolute;right:-14px;bottom:-14px;width:150px;height:150px;background-image:radial-gradient(#B85228 18%,transparent 20%);background-size:16px 16px;opacity:.12;border-radius:50%}
    .pie{text-align:center;font-size:10px;color:#a89f92;margin-top:18px}
    """

    /// "$1,250.50" con el punto decimal en naranja.
    private static func totalGrande(_ v: Double) -> String {
        let n = NumberFormatter(); n.locale = Locale(identifier: "en_US"); n.numberStyle = .decimal
        n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        let txt = n.string(from: NSNumber(value: v)) ?? fmt(v)
        let partes = txt.split(separator: ".", maxSplits: 1)
        return "$\(partes.first ?? "0")<i>.</i>\(partes.count > 1 ? partes[1] : "00")"
    }

    private static func bloque(_ titulo: String, _ principal: String, _ secundario: String? = nil) -> String {
        "<div class=\"blk\"><small>\(esc(titulo))</small><b>\(esc(principal.isEmpty ? "—" : principal))</b>\(secundario.flatMap { $0.isEmpty ? nil : "<span>\(esc($0))</span>" } ?? "")</div>"
    }

    /// Página completa: fondo crema + tarjeta. `extraCSS` para documentos largos.
    static func calida(titulo: String, chip: String, chipOK: Bool = false, encabezado: String, numero: String,
                       contenido: String, extraCSS: String = "", pie: String = "Nokta Studio · contacto@noktastudio.com") -> String {
        """
        <!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>\(esc(titulo))</title>
        <style>\(fuentesCSS)\(calidaCSS)\(extraCSS)</style></head><body>
        <div class="card">
          <div class="top">\(logoTag(height: 44))<span class="chip\(chipOK ? " ok" : "")">\(esc(chip))</span></div>
          <h1>\(esc(encabezado))</h1><div class="num">\(esc(numero))</div>
          \(contenido)
          <i class="puntos"></i>
        </div>
        <div class="pie">\(esc(pie))</div>
        </body></html>
        """
    }

    /// Fecha ISO ("2026-09-12" o instante) → "sábado 12 de septiembre de 2026".
    private static func fechaLegible(_ iso: String?, conDia: Bool = true) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.count == 10
            ? day.date(from: iso)
            : (fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? day.date(from: String(iso.prefix(10))))
        guard let date else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = conDia ? "EEEE d 'de' MMMM 'de' yyyy" : "d 'de' MMMM 'de' yyyy"
        return f.string(from: date)
    }

    /// Cotización o recibo creado en Documentos o por el Asistente.
    static func documento(_ d: DocumentoParaPDF) -> String {
        let esCot = d.tipo == "cotizacion"
        let filas = d.servicios.map { s in
            "<tr><td>\(esc(s.descripcion.isEmpty ? "—" : s.descripcion))</td><td>$\(fmt(s.monto))</td></tr>"
        }.joined()
        let contacto = [d.empresa, d.email, d.telefono].compactMap { $0 }.filter { !$0.isEmpty }
        let contenido = """
        <div class="blocks">
          \(bloque(esCot ? "Para" : "Cliente", d.clienteNombre, contacto.first))
          \(bloque("Detalles", "Emitido \(d.fechaEmision)", contacto.dropFirst().joined(separator: " · ").isEmpty ? "\(d.servicios.count) concepto\(d.servicios.count == 1 ? "" : "s")" : contacto.dropFirst().joined(separator: " · ")))
        </div>
        <table class="lista"><tr><th>Concepto</th><th>Monto</th></tr>\(filas)</table>
        <div class="total"><span>Total</span><b>\(totalGrande(d.total))</b></div>
        \((d.notas?.isEmpty == false) ? "<div class=\"nota\"><strong>Notas y condiciones</strong>\(esc(d.notas!))</div>" : "")
        <div class="gracias">\(esCot ? "Gracias por considerar a Nokta. Quedamos atentos. ✦" : "Gracias por confiar en Nokta. ✦")</div>
        """
        return calida(titulo: "\(esCot ? "Cotización" : "Recibo") \(d.numero)", chip: esCot ? "COTIZACIÓN" : "PAGADO", chipOK: !esCot,
                      encabezado: esCot ? "Propuesta" : "Recibo de pago", numero: "\(d.numero) · \(d.fechaEmision)", contenido: contenido)
    }

    /// Recibo de una quincena pagada (mensuales).
    static func facturaQuincena(cliente: String, empresa: String?, servicio: String, periodo: String, q: Int, monto: Double, fechaPago: String?) -> String {
        let parts = periodo.split(separator: "-")
        let anio = String(parts.first ?? "")
        let mes = String(parts.count > 1 ? parts[1] : "01")
        let mesNombre = FechaUtil.mesesCompletos[max(0, min(11, (Int(mes) ?? 1) - 1))]
        let calendario = Calendar(identifier: .gregorian)
        let inicioMes = calendario.date(from: DateComponents(year: Int(anio) ?? 2000, month: Int(mes) ?? 1, day: 1))
        let ultimoDia = inicioMes.flatMap { calendario.range(of: .day, in: .month, for: $0)?.count } ?? 30
        let rango = q == 1 ? "del 1 al 15" : "del 16 al \(ultimoDia)"
        let pago = fechaLegible(fechaPago, conDia: false) ?? "—"
        let contenido = """
        <div class="blocks">
          \(bloque("Cliente", cliente, [empresa ?? "", servicio].filter { !$0.isEmpty }.joined(separator: " · ")))
          \(bloque("Periodo", "\(mesNombre) \(anio)", "\(rango) · quincena \(q) de 2"))
        </div>
        <table class="lista"><tr><td>Fecha de pago</td><td>\(esc(pago))</td></tr><tr><td>Servicio</td><td>\(esc(servicio))</td></tr></table>
        <div class="total"><span>Total</span><b>\(totalGrande(monto))</b></div>
        <div class="gracias">Gracias por confiar en Nokta. ✦</div>
        """
        return calida(titulo: "Recibo · \(mesNombre) Q\(q)", chip: "PAGADO", chipOK: true, encabezado: "Recibo de pago",
                      numero: "#\(anio)\(mes)Q\(q) · \(mesNombre) \(anio)", contenido: contenido)
    }

    /// Recibo de una clase/sesión pagada.
    static func reciboSesion(cliente: String, servicio: String, fecha: String, numero: Int, total: Int, monto: Double, fechaPago: String?) -> String {
        let clase = fechaLegible(fecha) ?? fecha
        let pago = fechaLegible(fechaPago, conDia: false) ?? "—"
        let num = fecha.prefix(10).replacingOccurrences(of: "-", with: "") + "S\(numero)"
        let contenido = """
        <div class="blocks">
          \(bloque("Cliente", cliente, "Servicio: \(servicio)"))
          \(bloque("Clase", clase, "Sesión \(numero) de \(total)"))
        </div>
        <table class="lista"><tr><td>Fecha de pago</td><td>\(esc(pago))</td></tr></table>
        <div class="total"><span>Total</span><b>\(totalGrande(monto))</b></div>
        <div class="gracias">Gracias por confiar en Nokta. ✦</div>
        """
        return calida(titulo: "Recibo · Clase \(numero)", chip: "PAGADO", chipOK: true, encabezado: "Recibo de pago",
                      numero: "#\(num) · clase \(numero) de \(total)", contenido: contenido)
    }

    /// Reportes (mensual/clientes/galerías), con el cuerpo ya armado en HTML
    /// por el llamador (usa h3 + table como antes).
    static func reporte(titulo: String, cuerpoHTML: String) -> String {
        let f = DateFormatter(); f.dateFormat = "d 'de' MMMM 'de' yyyy, HH:mm"; f.locale = Locale(identifier: "es_MX")
        let fecha = f.string(from: Date())
        let extra = """
        .cuerpo{margin-top:30px}
        .cuerpo h3{font-size:9px;letter-spacing:.2em;color:#B85228;font-weight:600;text-transform:uppercase;margin:26px 0 10px}
        .cuerpo table{width:100%;border-collapse:collapse}
        .cuerpo th{font-size:9px;letter-spacing:.14em;color:#999;text-transform:uppercase;padding:8px 0;text-align:left;font-weight:500;border-bottom:1px solid #E6DFD4}
        .cuerpo td{padding:9px 0;font-size:12px;border-bottom:1px dashed #E6DFD4}
        """
        return calida(titulo: titulo, chip: "REPORTE", encabezado: titulo, numero: "Generado el \(fecha)",
                      contenido: "<div class=\"cuerpo\">\(cuerpoHTML)</div>", extraCSS: extra,
                      pie: "Generado por Nokta Studio · \(fecha)")
    }

    /// Contrato de prestación de servicios generado desde un trabajo real —
    /// mismo layout/cláusulas que `contratoHTML()` en admin.html, ya lleno
    /// con los datos del cliente en vez de dejarlos en blanco.
    static func contrato(_ d: ContratoParaPDF) -> String {
        func clause(_ n: Int, _ titulo: String, _ explica: String, _ cuerpoHTML: String) -> String {
            """
            <div class="clause">
              <h2><span class="num">\(n)</span> \(esc(titulo))</h2>
              <p class="explain">En palabras simples: \(esc(explica))</p>
              \(cuerpoHTML)
            </div>
            """
        }
        func row(_ label: String, _ value: String) -> String {
            "<tr><td>\(esc(label))</td><td>\(value.isEmpty ? "—" : esc(value))</td></tr>"
        }

        let cuerpo = """
        <div class="top">\(logoTag(height: 44))<span class="chip">CONTRATO</span></div>
        <h1>Contrato de prestación de servicios</h1>
        <div class="num">\(esc(d.clienteNombre)) · \(esc(d.ciudad)), \(esc(d.fechaContrato))</div>
        <p class="subtitle">Nokta Studio — agencia creativa · Fotografía · Video · Marketing · Gestión de redes</p>

        <p class="intro">En \(esc(d.ciudad)), El Salvador, el \(esc(d.fechaContrato)), se celebra el presente
        contrato de prestación de servicios (en adelante, el "Contrato") entre <strong>Nokta Studio</strong>
        (en adelante, el "Prestador de Servicios") y el Cliente identificado a continuación:</p>

        <table class="datos">
          \(row("Nombre del cliente", d.clienteNombre))
          \(row("Documento de identidad", d.clienteDui))
          \(row("Teléfono", d.clienteTelefono))
          \(row("Correo electrónico", d.clienteEmail))
          \(row("Dirección", d.clienteDireccion))
        </table>

        \(clause(1, "Objeto del contrato",
            "aquí se define exactamente qué servicio se va a dar, cuándo y dónde.",
            """
            <table class="tbl">
              <tr><th>Servicio contratado</th><th>Fecha</th><th>Lugar</th><th>Entregables</th></tr>
              <tr><td>\(esc(d.servicioTipo))</td><td>\(esc(d.servicioFecha))</td><td>\(esc(d.servicioLugar))</td><td>\(esc(d.entregables))</td></tr>
            </table>
            """))

        \(clause(2, "Precio y forma de pago",
            "cuánto cuesta el servicio y en qué momentos se paga.",
            """
            <table class="tbl">
              <tr><th>Concepto</th><th>Monto (USD)</th><th>Fecha límite</th></tr>
              <tr><td>Anticipo — reserva la fecha</td><td>$\(fmt(d.anticipoMonto))</td><td>\(esc(d.anticipoFecha))</td></tr>
              <tr><td>Saldo — contra entrega del material</td><td>$\(fmt(d.saldoMonto))</td><td>\(esc(d.saldoFecha))</td></tr>
              <tr class="total-row"><td>Total</td><td>$\(fmt(d.anticipoMonto + d.saldoMonto))</td><td></td></tr>
            </table>
            """))

        \(clause(3, "Mora por pago tardío",
            "si el pago se atrasa, se cobran $\(fmt(d.mora)) extra por cada día de retraso.",
            """
            <p>En caso de que el Cliente no realice el pago (anticipo o saldo) en la fecha límite pactada, se
            aplicará una multa por mora de <span class="hit">\(fmt(d.mora)) DÓLARES DE LOS ESTADOS UNIDOS
            DE AMÉRICA (US$\(fmt(d.mora)))</span> por cada día calendario de atraso, contado a partir
            del día siguiente a la fecha límite establecida, hasta la fecha en que se haga efectivo el pago
            total adeudado. El Prestador de Servicios podrá suspender el servicio o retener los entregables
            mientras el pago y la mora acumulada no estén cubiertos en su totalidad.</p>
            """))

        \(clause(4, "Plazo de entrega",
            "cuántos días hábiles hay para entregar el material final ya editado.",
            "<p>El Prestador de Servicios entregará el material final en un plazo de <strong>\(esc(d.plazoDias)) días hábiles</strong>, contados a partir de la fecha del servicio y/o de la recepción del pago del saldo, lo que ocurra después.</p>"))

        \(clause(5, "Derechos de uso y propiedad",
            "las fotos/videos finales son del cliente para usar; Nokta también puede mostrarlos en su portafolio.",
            """
            <ul>
              <li>El Cliente recibe una licencia de uso personal y/o comercial sobre el material entregado, una vez cubierto el pago total.</li>
              <li>Nokta Studio conserva el derecho de utilizar el material producido con fines de portafolio, promoción y publicidad, salvo acuerdo expreso en contrario por escrito.</li>
              <li>El material en bruto (RAW, tomas descartadas, archivos sin editar) no forma parte de los entregables y permanece en propiedad exclusiva de Nokta Studio.</li>
            </ul>
            """))

        \(clause(6, "Cancelaciones y reprogramaciones",
            "avisar con 72 horas de anticipación si se necesita cambiar la fecha; el anticipo no se devuelve pero sí se puede reagendar.",
            """
            <ul>
              <li>Toda cancelación o reprogramación debe notificarse con al menos 72 horas de anticipación a la fecha del servicio.</li>
              <li>El anticipo no es reembolsable en caso de cancelación por parte del Cliente, pero podrá aplicarse a una nueva fecha sujeta a disponibilidad.</li>
              <li>Si Nokta Studio debe cancelar por fuerza mayor, se reprogramará sin costo adicional o se reembolsará el anticipo, a elección del Cliente.</li>
            </ul>
            """))

        \(clause(7, "Confidencialidad y datos personales",
            "la información personal compartida se usa solo para este trabajo.",
            "<p>Ambas partes se comprometen a mantener confidencial la información personal y comercial compartida durante la prestación del servicio, utilizándola únicamente para los fines de este Contrato.</p>"))

        \(clause(8, "Ley aplicable y jurisdicción",
            "si hubiera un conflicto legal, se resuelve bajo las leyes de El Salvador.",
            "<p>El presente Contrato se rige por las leyes de la República de El Salvador. Cualquier controversia se resolverá primero por arreglo directo entre las partes y, de no ser posible, ante los tribunales competentes de El Salvador.</p>"))

        \(clause(9, "Aceptación",
            "firmando abajo, ambas partes aceptan todo lo anterior.",
            "<p>Ambas partes declaran haber leído, entendido y aceptado en su totalidad los términos de este Contrato, firmándolo de conformidad en dos tantos, uno para cada parte.</p>"))

        <div class="sign-grid">
          <div class="sign-box"><div class="who">Por Nokta Studio</div><div class="line">Nombre: ______________________</div><div class="line">Fecha: ______________________</div></div>
          <div class="sign-box"><div class="who">Por el Cliente</div><div class="line">Nombre: ______________________</div><div class="line">Fecha: ______________________</div></div>
        </div>
        """

        return """
        <!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Contrato · \(esc(d.clienteNombre))</title>
        <style>
        \(fuentesCSS)\(calidaCSS)
        .card{color:#2A2620}
        .subtitle{color:#8B8378;font-size:12px;margin:14px 0 26px}
        .intro{font-size:12.5px;line-height:1.7;margin-bottom:16px}
        table.datos{width:100%;border-collapse:collapse;margin-bottom:22px}
        table.datos td{padding:5px 0;font-size:12px;border-bottom:1px solid #EFE9DE}
        table.datos td:first-child{color:#8B8378;width:38%}
        table.datos td:last-child{font-weight:600}
        .clause{margin:26px 0 16px}
        .clause h2{display:flex;align-items:baseline;gap:9px;font-size:14px;font-weight:700;color:#B85228;margin:0 0 4px}
        .clause h2 .num{font-size:10px;font-weight:700;color:#fff;background:#B85228;border-radius:5px;padding:2px 6px}
        .explain{font-size:11px;font-style:italic;color:#8B8378;margin:0 0 10px}
        .clause p, .clause li{font-size:12.5px;line-height:1.65}
        .clause ul{margin:0 0 6px;padding-left:18px}
        .clause li{margin-bottom:5px}
        .hit{color:#B85228;font-weight:700}
        table.tbl{width:100%;border-collapse:collapse;margin:8px 0 12px;font-size:11.5px}
        table.tbl th{background:#B8522814;color:#B85228;text-align:left;font-size:9.5px;letter-spacing:.05em;text-transform:uppercase;padding:7px 9px;border:1px solid #B8522840}
        table.tbl td{padding:8px 9px;border:1px solid #E6DFD3}
        table.tbl .total-row td{font-weight:700}
        .sign-grid{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-top:34px}
        .sign-box{border-top:1.5px solid #2A2620;padding-top:8px}
        .sign-box .who{font-weight:700;font-size:12px;margin-bottom:8px}
        .sign-box .line{font-size:11.5px;color:#8B8378;margin-bottom:6px}
        .foot{margin-top:44px;padding-top:14px;border-top:1px solid #E6DFD3;text-align:center;font-size:10px;color:#8B8378}
        </style></head><body><div class="card">\(cuerpo)<i class="puntos"></i></div><div class="pie">Nokta Studio · contacto@noktastudio.com</div></body></html>
        """
    }

    private static func field(_ label: String, _ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return "<div class=\"field\"><span>\(label)</span>\(esc(value))</div>"
    }
    private static func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func fechaHoyLarga() -> String {
        let f = DateFormatter(); f.dateFormat = "d 'de' MMMM 'de' yyyy"; f.locale = Locale(identifier: "es_ES")
        return f.string(from: Date())
    }
}
