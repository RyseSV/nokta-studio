#!/usr/bin/env python3
"""Actual Apple Intelligence + actual payment core; all API calls use synthetic fixtures."""
from pathlib import Path
import tempfile
import subprocess
r=Path(__file__).resolve().parents[1]/'NoktaStudio'
s='import Foundation\nimport FoundationModels\n'
s+=(r/'Assistant/NoktaAPI.swift').read_text().split('extension String {')[0]
s+=(r/'Assistant/Tools/ServicioGrupoMap.swift').read_text()
s+=(r/'Assistant/Tools/ClienteResolver.swift').read_text()
create=(r/'Assistant/Tools/CrearTrabajoTool.swift').read_text()
s+=create[create.index('enum AnyEncodableValue'):create.index('enum CrearTrabajoValidacion')]
s+='struct ChatMessage { enum Role { case user, assistant, system }; var role: Role; var text: String }\n'
s+=(r/'Assistant/AssistantConversation.swift').read_text()
s+=(r/'Assistant/Tools/MarcarTrabajoPagadoTool.swift').read_text()
s+=(r/'Assistant/AssistantPayment.swift').read_text()
s+=r'''
let fixture = #"""
[{"id":"test","cliente":"Clases de IA Fátima","servicio":"Clases","grupo":"A","estado":"pendiente","monto":60,"saldo":40,"sesiones":[{"id":"a","fecha":"2026-09-12","monto":20,"estado":"pagado"},{"id":"b","fecha":"2026-09-19","monto":20,"estado":"pendiente"},{"id":"c","fecha":"2026-09-26","monto":20,"estado":"pendiente"}]}]
"""#
actor Recorder {
 var bodies: [Data] = []
 func add(_ data: Data) { bodies.append(data) }
 func all() -> [Data] { bodies }
}
let recorder = Recorder()
enum NoktaAPI {
 static func get<T: Decodable>(_ path: String) async throws -> T {
  guard path == "/api/trabajos" else { throw NSError(domain:"Forbidden test endpoint", code:1) }
  return try JSONDecoder().decode(T.self, from: Data(fixture.utf8))
 }
 static func patch<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
  guard path == "/api/trabajos/test/sesiones" else { throw NSError(domain:"Unexpected write", code:1) }
  try await recorder.add(JSONEncoder().encode(body))
  return try JSONDecoder().decode(T.self,from:Data(#"{"ok":true}"#.utf8))
 }
 static func put<T: Decodable>(_ path: String, body: Encodable) async throws -> T { throw NSError(domain:"Must not pay whole job", code:1) }
}
@Generable struct ReadArgs { var cliente: String? }
struct ReadTool: Tool {
 let name = "consultar_trabajos"
 let description = "Consulta las sesiones del cliente antes de registrar pagos."
 func call(arguments: ReadArgs) async throws -> String { fixture }
}
@main struct Probe {
 static func main() async throws {
  print("Testing on-device model with SYNTHETIC API, no network writes")
  let now = ISO8601DateFormatter().date(from:"2026-09-18T18:00:00Z")!
  let prompt = "marca como... marca como pagado lo 20 de Fátima del sábado 19"
  let s = LanguageModelSession(instructions:AssistantPayment.instructions)
  let plan = try await s.respond(to:"Mensaje actual de Gabriel: " + prompt,generating:AssistantPaymentPlan.self,options:GenerationOptions(samplingMode:.greedy)).content
  print("PLAN",plan)
  let works = try JSONDecoder().decode([NoktaTrabajo].self,from:Data(fixture.utf8))
  let result = try await AssistantPayment.ejecutar(plan,historialUsuario:prompt,trabajos:works,ahora:now)
  print(result ?? "No result")
  let bodies = await recorder.all()
  guard bodies.count == 1 else { fatalError("Expected exactly one session PATCH, received \(bodies.count)") }
  let body = try JSONSerialization.jsonObject(with:bodies[0]) as! [String:Any]
  let sessions = body["sesiones"] as! [[String:Any]]
  assert(sessions[0]["estado"] as! String == "pagado")
  assert(sessions[1]["estado"] as! String == "pagado")
  assert(sessions[2]["estado"] as! String == "pendiente")
  let ambiguousPrompt = "Fátima ya me pagó. el sábado."
  let a = LanguageModelSession(instructions:AssistantPayment.instructions)
  let ambiguous = try await a.respond(to:"Mensaje actual de Gabriel: " + ambiguousPrompt,generating:AssistantPaymentPlan.self,options:GenerationOptions(samplingMode:.greedy)).content
  let clarification = try await AssistantPayment.ejecutar(ambiguous,historialUsuario:ambiguousPrompt,trabajos:works,ahora:now)
  print("CLARIFICATION",clarification ?? "nil")
  let afterAmbiguous = await recorder.all(); assert(afterAmbiguous.count == 1, "An ambiguous Saturday must not write")
  let continuation = "la del sábado 19"
  let followup = LanguageModelSession(instructions:AssistantPayment.instructions)
  let followupPlan = try await followup.respond(to:"Historial: Gabriel: " + ambiguousPrompt + "\\nAsistente: " + (clarification ?? "¿Cuál fecha?") + "\\nMensaje actual de Gabriel: " + continuation,generating:AssistantPaymentPlan.self,options:GenerationOptions(samplingMode:.greedy)).content
  let followupResult = try await AssistantPayment.ejecutar(followupPlan,historialUsuario:ambiguousPrompt+" " + continuation,trabajos:works,ahora:now)
  print("FOLLOWUP",followupResult ?? "nil")
  let allBodies = await recorder.all()
  assert(allBodies.count == 2,"Followup should complete exactly one payment")
  let followBody=try JSONSerialization.jsonObject(with:allBodies[1]) as! [String:Any]
  let followSessions=followBody["sesiones"] as! [[String:Any]]
  assert(followSessions[1]["estado"] as! String == "pagado" && followSessions[2]["estado"] as! String == "pendiente")
  print("PASS: actual model payment, ambiguous Saturday no write, contextual date followup, preserved other sessions")
 }
}
'''
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory)/'main.swift'
    executable = Path(directory)/'payment-model'
    source.write_text(s)
    subprocess.run(['swiftc','-parse-as-library','-target','arm64-apple-macos27.0',str(source),'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True)

