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
