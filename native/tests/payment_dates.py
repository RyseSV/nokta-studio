#!/usr/bin/env python3
"""Regression coverage for ambiguous spoken dates; no network/model calls."""
from pathlib import Path
import tempfile
import subprocess
root=Path(__file__).resolve().parents[1]/'NoktaStudio'
source='import Foundation\n'+(root/'Assistant/AssistantPayment.swift').read_text().split('enum PagoFechaResolver {',1)[1]
source=source.replace('import Foundation\n','import Foundation\nenum PagoFechaResolver {',1)
source+=r'''
let now=ISO8601DateFormatter().date(from:"2026-09-19T18:00:00Z")!
let fechas=["2026-09-02","2026-09-05","2026-09-12","2026-09-19","2026-09-20","2026-09-26"]
func date(_ text:String,_ expected:String) {
 assert(PagoFechaResolver.resolver(text,fechas:fechas,ahora:now) == .fecha(expected),text)
}
func unclear(_ text:String) {
 if case .aclarar = PagoFechaResolver.resolver(text,fechas:fechas,ahora:now) {} else { fatalError(text) }
}
date("sábado 19","2026-09-19")
date("sábado 19 por la mañana","2026-09-19")
date("20 de Fátima del sábado 19","2026-09-19")
date("mañana","2026-09-20")
date("ayer","2026-09-18")
date("sábado pasado","2026-09-12")
date("2026-09-19","2026-09-19")
unclear("el sábado")
unclear("hace 2 semanas")
unclear("martes o jueves")
unclear("septiembre u octubre")
unclear("sábado pasado 19")
unclear("el 19 del mes pasado")
unclear("19 de octubre del año pasado")
unclear("sábado anterior")
unclear("sábado siguiente")
unclear("último sábado")
unclear("2026-13-32")
print("PASS: spoken dates, amount vs day, morning vs tomorrow, ambiguity, unsupported relatives and invalid dates")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'main.swift';p.write_text(source)
 subprocess.run(['swift',str(p)],check=True)
