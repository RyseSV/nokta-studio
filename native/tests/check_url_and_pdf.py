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
source += (root / "Assistant/PDFTemplates.swift").read_text()
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
for date: String? in [nil, "invalid"] {
    let html = PDFTemplates.facturaQuincena(cliente: "Prueba", empresa: nil, servicio: "Prueba", periodo: "2026-09", q: 2, monto: 20, fechaPago: date)
    precondition(!html.contains("18 de septiembre de 2026"))
}
print("PASS: 6 client names, static API path, and PDF HTML dates")
'''
with tempfile.TemporaryDirectory(prefix="nokta-native-check-") as tmp:
    swift_file = Path(tmp) / "checks.swift"
    swift_file.write_text(source)
    for timezone in ["UTC", "America/El_Salvador"]:
        print(f"Timezone: {timezone}", flush=True)
        subprocess.run(["swift", str(swift_file)], check=True, env={**os.environ, "TZ": timezone})
