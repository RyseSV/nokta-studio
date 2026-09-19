#!/usr/bin/env python3
"""Actual Swift selection/validation code, synthetic fixtures; no network or writes."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1] / 'NoktaStudio'
tools = root / 'Assistant/Tools'
models = (root / 'Assistant/NoktaAPI.swift').read_text().split('extension String {', 1)[0]
payment = (tools / 'MarcarTrabajoPagadoTool.swift').read_text().split('enum MarcarTrabajoPagadoCore {', 1)[1].split('    static func run(', 1)[0]
validation = (tools / 'CrearTrabajoTool.swift').read_text().split('enum CrearTrabajoValidacion {', 1)[1]
source = models + (tools / 'ServicioGrupoMap.swift').read_text() + (tools / 'ClienteResolver.swift').read_text()
source += '\nenum MarcarTrabajoPagadoCore {' + payment + '}\nenum CrearTrabajoValidacion {' + validation
source += r'''
let fixture = #"""
[
 {"id":"classes","cliente":"Clases de IA Fátima","servicio":"Clases","estado":"pendiente","saldo":100,"sesiones":[
  {"id":"1","fecha":"2026-09-12","monto":20,"estado":"pagado"},
  {"id":"2","fecha":"2026-09-19","monto":20,"estado":"pendiente"},
  {"id":"3","fecha":"2026-09-26","monto":20,"estado":"pendiente"}]},
 {"id":"monthly","cliente":"TuBoleto","servicio":"Gestión de redes","grupo":"B","estado":"pendiente","pagoMensual":250},
 {"id":"normal","cliente":"Empresa","servicio":"Foto","estado":"pendiente","monto":50,"saldo":20,"fecha":"2026-09-19"}
]
"""#
let trabajos = try JSONDecoder().decode([NoktaTrabajo].self, from: Data(fixture.utf8))
func select(_ cliente: String = "fatima", fecha: String? = nil, proxima: Bool = false, monto: Double? = nil, ts: [NoktaTrabajo]? = nil) -> MarcarTrabajoPagadoCore.Seleccion {
    MarcarTrabajoPagadoCore.seleccionar(trabajos: ts ?? trabajos, cliente: cliente, servicio: nil, fechaSesion: fecha, proximaSesion: proxima, monto: monto)
}
func aclaracion(_ s: MarcarTrabajoPagadoCore.Seleccion) { guard case .aclarar = s else { fatalError("Expected clarification, no payment") } }
aclaracion(select()) // Fátima ya me pagó el sábado: date must be resolved or requested.
aclaracion(select(fecha: "   ", monto: 20))
guard case .sesion(_, let espacio) = select(fecha: "   ", proxima: true, monto: 20), espacio == 1 else { fatalError("Blank date must act like nil") }
aclaracion(select(monto: 20)) // Both unpaid sessions cost 20; price is not enough.
guard case .sesion(let t, let s) = select(fecha: "2026-09-19", monto: 20), t == 0, s == 1 else { fatalError("Must select September 19 only") }
guard case .sesion(_, let s) = select(proxima: true), s == 1 else { fatalError("Explicit next selects earliest unpaid") }
aclaracion(select(fecha: "2026-09-12", monto: 20)) // Already paid
aclaracion(select(fecha: "2026-09-19", monto: 30)) // Wrong amount
aclaracion(select("TuBoleto")) // Monthly never marked globally
aclaracion(select("Fatmia", fecha: "2026-09-19")) // No typo guessing on payment
var duplicate = trabajos[0]; duplicate.id = "other"; duplicate.cliente = "Fátima López"
aclaracion(select(fecha: "2026-09-19", ts: trabajos + [duplicate]))
guard case .trabajo(let n) = select("Empresa", monto: 20), n == 2 else { fatalError("Normal saldo payment preserved") }
assert(CrearTrabajoValidacion.error(cliente: "Fátima", servicio: "Clases", fecha: nil, monto: 20, anticipo: nil) != nil)
assert(CrearTrabajoValidacion.error(cliente: "Fátima", servicio: "Clases", fecha: "2026-09-19", monto: nil, anticipo: nil) != nil)
assert(!CrearTrabajoValidacion.fechaValida("2026-02-30"))
assert(!CrearTrabajoValidacion.fechaValida("2026-9-19"))
assert(CrearTrabajoValidacion.error(cliente: "Fátima", servicio: "Clases", fecha: "2026-09-19", monto: 20, anticipo: nil) == nil)
assert(CrearTrabajoValidacion.error(cliente: "Fátima", servicio: "Clases", fecha: "2026-09-19", monto: 20, anticipo: 0, pagado: true) != nil)
assert(CrearTrabajoValidacion.error(cliente: "Fátima", servicio: "Clases", fecha: "2026-09-19", monto: 20, anticipo: 20, pagado: false) != nil)
assert(CrearTrabajoValidacion.error(cliente: "Fátima", servicio: "Clases", fecha: "2026-09-19", monto: 20, anticipo: 20) == nil)
print("PASS: payment examples, amount/date disambiguation, next only explicit, paid exclusion, monthly exclusion, ambiguous/typo names, ordinary payments, creation missing/invalid fields")
'''
with tempfile.TemporaryDirectory() as d:
    path = Path(d) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)
