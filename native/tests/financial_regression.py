#!/usr/bin/env python3
"""Compile actual model/core sources and exercise synthetic data, without a server."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1] / 'NoktaStudio'
models = (root / 'Assistant/NoktaAPI.swift').read_text().split('extension String {', 1)[0]
source = models + (root / 'Assistant/Tools/ServicioGrupoMap.swift').read_text() + (root / 'Core/Ingresos.swift').read_text()
source += r'''
let fixture = #"""
[
 {"id":"classes","cliente":"Fátima","servicio":"Clases","grupo":"A","estado":"pendiente","saldo":100,"sesiones":[
  {"id":"1","fecha":"2026-09-12","monto":20,"estado":"pagado"},
  {"id":"2","fecha":"2026-09-19","monto":20,"estado":"pendiente"},
  {"id":"3","fecha":"2026-09-26","monto":20,"estado":"pendiente"}]},
 {"id":"paused","cliente":"TuBoleto","servicio":"Gestión de redes","grupo":"B","estado":"pendiente","saldo":250,"pagoMensual":250,"fechaInicio":"2026-06-01","estadoContrato":"activo"},
 {"id":"ordinary","cliente":"Evento","servicio":"Foto","grupo":"A","estado":"pendiente","fecha":"2026-09-10","saldo":30},
 {"id":"old","cliente":"Anterior","servicio":"Foto","grupo":"A","estado":"pendiente","fecha":"2026-08-10","saldo":500},
 {"id":"future","cliente":"Futuro","servicio":"Redes","grupo":"B","estado":"pendiente","fechaInicio":"2026-10-01","pagoMensual":600},
 {"id":"half","cliente":"Media","servicio":"Redes","grupo":"B","estado":"pendiente","fechaInicio":"2026-09-20","pagoMensual":100},
 {"id":"paid","cliente":"Pagado","servicio":"Redes","grupo":"B","estado":"pendiente","fechaInicio":"2026-08-01","pagoMensual":100,"quincenas":[{"periodo":"2026-09","q":1,"monto":50,"estado":"pagado"},{"periodo":"2026-09","q":2,"monto":50,"estado":"oculta"}]},
 {"id":"fallback","cliente":"Cancelado","servicio":"Redes","grupo":"B","estado":"pendiente","fechaInicio":"2026-08-01","pagoMensual":100,"estadoContrato":"cancelado"}
]
"""#
var trabajos = try JSONDecoder().decode([NoktaTrabajo].self, from: Data(fixture.utf8))
let estados = [NoktaClienteEstado(nombre: "TuBoleto", estado: "pausado")]
let result = IngresosCalculator.pendienteDelMes("2026-09", trabajos: trabajos, estados: estados)
assert(result.monto == 150 && result.count == 3, "Expected class20 + ordinary30 + monthly100")
let resumen = IngresosCalculator.resumenCobros("2026-09", trabajos: trabajos, estados: estados)
assert(resumen.contains("$150.00") && resumen.contains("2026-09-19"))
assert(!resumen.contains("TuBoleto") && !resumen.contains("$350.00"))
trabajos[0].sesiones![1].estado = "pagado"
let next = IngresosCalculator.resumenCobros("2026-09", trabajos: [trabajos[0]], estados: estados)
assert(next.contains("2026-09-26") && next.contains("$20.00"))
let outside = IngresosCalculator.resumenCobros("2026-10", trabajos: [trabajos[0]], estados: [])
assert(outside.contains("fuera del mes consultado"))
let active = IngresosCalculator.pendienteDelMes("2026-09", trabajos: [trabajos[7]], estados: [NoktaClienteEstado(nombre: "Cancelado", estado: "activo")])
assert(active.monto == 100, "Live state overrides stored contract state")
print("PASS: screenshot scenario, month scope, future contracts, start month, paid/hidden installments, fallback/live states and advancing sessions")
'''
with tempfile.TemporaryDirectory() as d:
    path = Path(d) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)
