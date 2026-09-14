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
          <div>\(logoFallback)</div>
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
