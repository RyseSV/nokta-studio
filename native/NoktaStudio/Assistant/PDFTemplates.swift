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

    static func documento(_ d: DocumentoParaPDF) -> String {
        let titulo = d.tipo == "cotizacion" ? "Cotización" : "Recibo de Pago"

        let filas = d.servicios.map { s in
            "<tr><td>\(esc(s.descripcion.isEmpty ? "—" : s.descripcion))</td><td>$\(fmt(s.monto))</td></tr>"
        }.joined()

        let clientGrid = """
        <div class="field"><span>Nombre</span>\(esc(d.clienteNombre))</div>
        \(field("Empresa", d.empresa)) \(field("Teléfono", d.telefono)) \(field("Email", d.email))
        """

        let notas = (d.notas?.isEmpty == false)
            ? "<div class=\"notas\"><strong>Notas y condiciones</strong>\(esc(d.notas!))</div>" : ""

        let body = """
        <div class="header">
          <div>\(logoTag(height: 40))</div>
          <div style="text-align:right">
            <div class="doc-tipo">\(titulo)</div>
            <div class="doc-num">\(esc(d.numero))</div>
            <div class="doc-date">Emisión: \(d.fechaEmision)</div>
          </div>
        </div>
        <hr class="divider">
        <div class="section-label">Cliente</div>
        <div class="client-grid">\(clientGrid)</div>
        <hr class="divider-light">
        <div class="section-label">Servicios</div>
        <table>
          <thead><tr><th>Descripción</th><th style="text-align:right">Monto</th></tr></thead>
          <tbody>\(filas)<tr class="total-row"><td>Total</td><td>$\(fmt(d.total))</td></tr></tbody>
        </table>
        \(notas)
        <div class="footer"><span>Nokta Studio</span><span>Generado el \(fechaHoyLarga())</span></div>
        """

        return """
        <!DOCTYPE html><html><head><meta charset="UTF-8"><title>\(titulo) \(d.numero)</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,'Helvetica Neue',sans-serif;color:#1C1C1A;background:#fff}
        #wrap{padding:40px 48px;max-width:794px;margin:0 auto}
        .header{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:28px}
        .doc-tipo{font-size:20px;font-weight:700;color:#1C1C1A;margin-bottom:4px}
        .doc-num{font-size:12px;color:#B85228;font-weight:600;letter-spacing:1px}
        .doc-date{font-size:11px;color:#888;margin-top:2px}
        .divider{border:none;border-top:2px solid #B85228;margin:20px 0}
        .divider-light{border:none;border-top:1px solid #e8e4df;margin:16px 0}
        .section-label{font-size:9px;letter-spacing:2px;color:#B85228;font-weight:600;margin-bottom:8px;text-transform:uppercase}
        .client-grid{display:grid;grid-template-columns:1fr 1fr;gap:6px 20px;margin-bottom:6px}
        .field{font-size:12px;color:#1C1C1A}
        .field span{color:#888;font-size:10px;display:block;letter-spacing:1px;text-transform:uppercase;margin-bottom:1px}
        table{width:100%;border-collapse:collapse;margin-top:6px}
        thead tr{border-bottom:2px solid #B85228}
        th{font-size:10px;letter-spacing:1px;color:#888;text-transform:uppercase;padding:7px 0;text-align:left;font-weight:500}
        th:last-child{text-align:right}
        td{padding:8px 0;font-size:12px;border-bottom:1px solid #f0ebe5}
        td:last-child{text-align:right}
        .total-row td{border-top:2px solid #B85228;border-bottom:none;padding-top:12px;font-weight:700;font-size:14px}
        .total-row td:last-child{color:#B85228;font-size:16px}
        .notas{margin-top:24px;padding:14px;background:#faf8f5;border-left:3px solid #B85228;font-size:11px;color:#555;line-height:1.6}
        .notas strong{display:block;font-size:10px;letter-spacing:1px;color:#B85228;text-transform:uppercase;margin-bottom:4px}
        .footer{margin-top:40px;padding-top:12px;border-top:1px solid #e8e4df;display:flex;justify-content:space-between;align-items:center;font-size:10px;color:#bbb}
        </style></head><body>
        <div id="wrap">\(body)</div>
        </body></html>
        """
    }

    /// Recibo de una quincena individual (grupo B) — mismo layout que
    /// `generarFacturaQ` en admin.html, para que el PDF nativo se vea igual
    /// al que se genera desde el panel web.
    static func facturaQuincena(cliente: String, empresa: String?, servicio: String, periodo: String, q: Int, monto: Double, fechaPago: String?) -> String {
        let parts = periodo.split(separator: "-")
        let anio = String(parts.first ?? "")
        let mes = String(parts.count > 1 ? parts[1] : "01")
        let mesIdx = (Int(mes) ?? 1) - 1
        let mesNombre = FechaUtil.mesesCompletos[max(0, min(11, mesIdx))]
        let calendario = Calendar(identifier: .gregorian)
        let inicioMes = calendario.date(from: DateComponents(year: Int(anio) ?? 2000, month: Int(mes) ?? 1, day: 1))
        let ultimoDia = inicioMes.flatMap { calendario.range(of: .day, in: .month, for: $0)?.count } ?? 30
        let rango = q == 1 ? "1 al 15" : "16 al \(ultimoDia)"
        let fechaPagoLabel = fechaPago.flatMap { iso -> String? in
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.calendar = Calendar(identifier: .gregorian)
            day.dateFormat = "yyyy-MM-dd"
            day.isLenient = false
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            // Web payments store a calendar day; native payments store an instant.
            let date = iso.count == 10
                ? day.date(from: iso)
                : (fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso))
            guard let date else { return nil }
            let f = DateFormatter(); f.locale = Locale(identifier: "es_MX")
            f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = "d 'de' MMMM 'de' yyyy"
            return f.string(from: date)
        } ?? "—"

        let empresaRow = empresa.flatMap { $0.isEmpty ? nil : $0 }.map { "<tr><td>Empresa</td><td>\(esc($0))</td></tr>" } ?? ""

        return """
        <!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Recibo · \(mesNombre) Q\(q)</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,'Helvetica Neue',sans-serif;background:#fff;color:#1C1C1A;padding:60px;max-width:680px;margin:0 auto}
        .doc-tipo{font-size:11px;color:#888;text-transform:uppercase;letter-spacing:.06em}
        .doc-num{font-size:22px;font-weight:800;margin-top:4px;color:#1C1C1A}
        .divider{border:none;border-top:2px solid #B85228;margin:28px 0 32px}
        h2{font-size:10px;letter-spacing:2px;text-transform:uppercase;color:#B85228;font-weight:600;margin-bottom:16px}
        table{width:100%;border-collapse:collapse;margin-bottom:8px}
        td{padding:10px 0;border-bottom:1px solid #f0ebe5;font-size:14px}
        td:first-child{color:#888;width:45%}
        td:last-child{font-weight:600;text-align:right}
        .total-row td{border-top:2px solid #B85228;border-bottom:none;padding-top:16px;font-size:18px}
        .total-row td:first-child{color:#1C1C1A;font-weight:700}
        .total-row td:last-child{color:#B85228;font-size:20px}
        .footer{margin-top:60px;padding-top:24px;border-top:1px solid #e8e4df;font-size:11px;color:#bbb;text-align:center}
        </style></head><body>
        <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:8px">
          \(logoTag(height: 40))
          <div style="text-align:right">
            <div class="doc-tipo">Recibo de pago</div>
            <div class="doc-num">#\(anio)\(mes)Q\(q)</div>
          </div>
        </div>
        <hr class="divider">
        <h2>Detalle del servicio</h2>
        <table>
          <tr><td>Cliente</td><td>\(esc(cliente))</td></tr>
          \(empresaRow)
          <tr><td>Servicio</td><td>\(esc(servicio))</td></tr>
          <tr><td>Periodo</td><td>\(mesNombre) \(anio) · del \(rango) de \(mesNombre)</td></tr>
          <tr><td>Quincena</td><td>Q\(q) de 2</td></tr>
          <tr><td>Fecha de pago</td><td>\(fechaPagoLabel)</td></tr>
          <tr class="total-row"><td>Total</td><td>$\(fmt(monto))</td></tr>
        </table>
        <div class="footer">Nokta Studio · contacto@noktastudio.com<br>Este documento es un comprobante interno de pago.</div>
        </body></html>
        """
    }

    /// Reportes (mensual/clientes/galerías) — mismo layout que `genReporte`
    /// en admin.html, con el cuerpo ya armado en HTML por el llamador.
    static func reporte(titulo: String, cuerpoHTML: String) -> String {
        let f = DateFormatter(); f.dateFormat = "d 'de' MMMM 'de' yyyy, HH:mm"; f.locale = Locale(identifier: "es_MX")
        let fecha = f.string(from: Date())
        return """
        <!DOCTYPE html><html><head><meta charset="UTF-8"><title>\(titulo)</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,'Helvetica Neue',sans-serif;color:#1C1C1A;background:#fff}
        #wrap{padding:40px 48px;max-width:900px;margin:0 auto}
        .header{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:28px}
        .title{font-size:20px;font-weight:700;color:#1C1C1A;margin-bottom:2px}
        .sub{font-size:12px;color:#888}
        h3{font-size:10px;letter-spacing:2px;color:#B85228;font-weight:600;text-transform:uppercase;margin-bottom:10px}
        table{width:100%;border-collapse:collapse}
        thead tr{border-bottom:2px solid #B85228}
        th{font-size:10px;letter-spacing:1px;color:#888;text-transform:uppercase;padding:7px 0;text-align:left;font-weight:500}
        td{padding:7px 0;font-size:12px;border-bottom:1px solid #f0ebe5}
        .footer{margin-top:48px;padding-top:14px;border-top:1px solid #e8e4df;font-size:11px;color:#bbb;text-align:center}
        </style></head><body>
        <div id="wrap">
          <div class="header">
            \(logoTag(height: 36))
            <div style="text-align:right"><div class="title">\(esc(titulo))</div><div class="sub">\(fecha)</div></div>
          </div>
          <hr style="border:none;border-top:2px solid #B85228;margin-bottom:28px">
          \(cuerpoHTML)
          <div class="footer">Generado por Nokta Studio · \(fecha)</div>
        </div>
        </body></html>
        """
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
        <div class="mast">
          \(logoTag(height: 30))
          <div class="tag">Contrato de prestación de servicios</div>
        </div>
        <div class="title">Contrato de Prestación de Servicios</div>
        <p class="subtitle">Nokta Studio — Fotografía · Video · Marketing · Gestión de redes</p>

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
            DE AMÉRICA (US$\(fmt(d.mora)).00)</span> por cada día calendario de atraso, contado a partir
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
        <div class="foot">Nokta Studio · contacto@noktastudio.com</div>
        """

        return """
        <!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Contrato · \(esc(d.clienteNombre))</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,'Helvetica Neue',sans-serif;color:#2A2620;background:#FAF7F2;padding:44px 52px}
        .sheet{max-width:720px;margin:0 auto}
        .mast{display:flex;align-items:baseline;justify-content:space-between;gap:16px;padding-bottom:18px;margin-bottom:6px;border-bottom:1px solid #E6DFD3}
        .tag{font-size:10px;letter-spacing:.08em;text-transform:uppercase;color:#8B8378}
        .title{text-align:center;margin:26px 0 6px;font-size:24px;font-weight:700}
        .subtitle{text-align:center;color:#8B8378;font-style:italic;font-size:13px;margin:0 0 26px}
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
        </style></head><body><div class="sheet">\(cuerpo)</div></body></html>
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
