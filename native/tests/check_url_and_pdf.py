#!/usr/bin/env python3
"""Run Foundation-only regressions against the production URL/PDF code, without API access.

Usage: python3 native/tests/check_url_and_pdf.py
The temporary Swift harness is outside the app target and deleted after execution.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / "NoktaStudio"
api = (root / "Assistant/NoktaAPI.swift").read_text()
encoding = api[api.index("extension String {"):api.index("enum NoktaAPIError")]
url_code = api[api.index("        guard let url = URL(string: path"):api.index("        var req = URLRequest(url: url)")]
source = '''import Foundation
enum NoktaAPIError: Error { case invalidURL }
'''
source += encoding
source += '\nfunc makeURL(_ path: String) throws -> URL { let baseURL = URL(string:"https://example.test")!\n'
source += url_code + 'return url\n}\n'
pdf = (root / "Assistant/PDFTemplates.swift").read_text()
# Test the actual templates, excluding the network/render orchestration enum.
source += pdf[:pdf.index("enum ContratoGenerator")] + pdf[pdf.index("enum PDFTemplates"):]

source += '''
enum FechaUtil {
    static let mesesCompletos = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
}
'''
source += r'''
for name in ["Cliente A/B", "Fátima", "100% Nokta", "A?B#C&D", "A%2FB", "Simple"] {
    let url = try makeURL("/api/clientes-estados/\(name.urlPathComponentEncoded)")
    let component = URLComponents(url: url, resolvingAgainstBaseURL: true)!.percentEncodedPath.components(separatedBy: "/").last!
    precondition(component.removingPercentEncoding == name, "Name did not roundtrip: \(name)")
}
precondition((try! makeURL("/api/alertas")).absoluteString == "https://example.test/api/alertas")
for date in ["2026-09-18", "2026-09-18T12:00:00Z", "2026-09-18T12:00:00.123Z"] {
    let html = PDFTemplates.facturaQuincena(cliente: "Prueba", empresa: nil, servicio: "Prueba", periodo: "2026-09", q: 2, monto: 20, fechaPago: date)
    precondition(html.contains("18 de septiembre de 2026"), "Missing date: \(date)")
}
for (periodo, ultimoDia) in [("2026-01", 31), ("2026-04", 30), ("2026-02", 28), ("2028-02", 29)] {
    let segunda = PDFTemplates.facturaQuincena(cliente: "Prueba", empresa: nil, servicio: "Prueba", periodo: periodo, q: 2, monto: 20, fechaPago: nil)
    precondition(segunda.contains("del 16 al \(ultimoDia)"), "Incorrect second-half range: \(periodo)")
    let primera = PDFTemplates.facturaQuincena(cliente: "Prueba", empresa: nil, servicio: "Prueba", periodo: periodo, q: 1, monto: 20, fechaPago: nil)
    precondition(primera.contains("del 1 al 15"))
}
for date: String? in [nil, "invalid"] {
    let html = PDFTemplates.facturaQuincena(cliente: "Prueba", empresa: nil, servicio: "Prueba", periodo: "2026-09", q: 2, monto: 20, fechaPago: date)
    precondition(!html.contains("18 de septiembre de 2026"))
}
let contrato = ContratoParaPDF(ciudad: "Prueba", fechaContrato: "2026-09-24", clienteNombre: "Prueba", clienteDui: "prueba", clienteTelefono: "", clienteEmail: "", clienteDireccion: "", servicioTipo: "Clases", servicioFecha: "", servicioLugar: "", entregables: "", anticipoMonto: 0, anticipoFecha: "", saldoMonto: 120, saldoFecha: "", plazoDias: "7", mora: 0)
let contratoHTML = PDFTemplates.contrato(contrato)
precondition(contratoHTML.contains("US$0.00)"))
precondition(!contratoHTML.contains("US$0.00.00"))
print("PASS: 6 client names, static API path, and PDF HTML dates/month ranges")
'''
with tempfile.TemporaryDirectory(prefix="nokta-native-check-") as tmp:
    swift_file = Path(tmp) / "checks.swift"
    swift_file.write_text(source)
    for timezone in ["UTC", "America/El_Salvador"]:
        print(f"Timezone: {timezone}", flush=True)
        subprocess.run(["swift", str(swift_file)], check=True, env={**os.environ, "TZ": timezone})
