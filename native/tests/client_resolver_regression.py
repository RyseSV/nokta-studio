#!/usr/bin/env python3
"""Synthetic resolver and state-tool checks. No network, server data, or app target."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / 'NoktaStudio'
api = (root / 'Assistant/NoktaAPI.swift').read_text()
source = api.split('enum NoktaAPIError', 1)[0]
source += (root / 'Assistant/Tools/ServicioGrupoMap.swift').read_text()
source += (root / 'Assistant/Tools/ClienteResolver.swift').read_text()
tool = (root / 'Assistant/Tools/CambiarEstadoClienteTool.swift').read_text()
tool = tool.replace('import FoundationModels\n', '').replace('@Generable\n', '')
tool = re.sub(r'^\s*@Guide\(.*\)\n', '\n', tool, flags=re.M)
source += '\nprotocol Tool {}\n' + tool
source += r'''
enum MockError: Error { case unavailable }
enum NoktaAPI {
    static var names = ["Fátima López", "Fátima Pérez", "TuBoleto"]
    static var writes = 0
    static var reads = 0
    static var failRead = false
    static var badResponse = false
    static var lastPath = ""
    static var lastBody: [String: String] = [:]
    static func get<T: Decodable>(_ path: String) async throws -> T {
        reads += 1
        if failRead { throw MockError.unavailable }
        if path == "/api/trabajos" {
            let items = names.map { ["id": $0, "cliente": $0, "servicio": "Clases", "estado": "pendiente"] }
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: items))
        }
        if path == "/api/clientes" {
            return try JSONDecoder().decode(T.self, from: Data(#"[{"codigo":"new","nombre":"Cliente Nuevo","estado":"activo"}]"#.utf8))
        }
        return try JSONDecoder().decode(T.self, from: Data("[]".utf8))
    }
    static func put<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        writes += 1
        lastPath = path
        lastBody = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(body))
        let name = String(path.dropFirst("/api/clientes-estados/".count)).removingPercentEncoding!
        let response: [String: Any] = ["ok": true, "clienteEstado": [
            "nombre": name, "estado": badResponse ? "incorrecto" : lastBody["estado"]!,
            "notas": lastBody["notas"] ?? "Nota anterior"
        ]]
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: response))
    }
}
let names = ["Fátima López", "Fátima Pérez", "TuBoleto", "Ana", "Mariana", "A/B", "Fátima López"]
assert(ClienteResolver.resolver(" FÁTIMA LÓPEZ ", nombres: names) == .encontrado("Fátima López"))
assert(ClienteResolver.resolver("fati lo", nombres: names) == .encontrado("Fátima López"))
assert(ClienteResolver.resolver("tu boleto", nombres: names) == .encontrado("TuBoleto"))
assert(ClienteResolver.resolver("fatima", nombres: names) == .ambiguo(["Fátima López", "Fátima Pérez"]))
assert(ClienteResolver.resolver("Ana", nombres: names) == .encontrado("Ana"))
assert(ClienteResolver.resolver("ana", nombres: ["Mariana"]) == .noEncontrado)
assert(ClienteResolver.resolver("Ftaima", nombres: names) == .noEncontrado)
assert(ClienteResolver.resolver("  ??? ", nombres: names) == .noEncontrado)
assert(ClienteResolver.resolver("FATIMA", nombres: ["Fátima", "Fatima"]) == .ambiguo(["Fatima", "Fátima"]))
assert(ClienteResolver.resolver("Fátima", nombres: ["Fátima", "Fatima"]) == .encontrado("Fátima"))
assert(ClienteResolver.resolver("a b", nombres: ["A/B", "AB"]) == .encontrado("A/B"))

let tool = CambiarEstadoClienteTool()
let ambiguous = try await tool.call(arguments: .init(nombre: "fatima", estado: "pausado", notas: nil))
assert(ambiguous.contains("varios clientes") && NoktaAPI.writes == 0)
let missing = try await tool.call(arguments: .init(nombre: "Ftaima", estado: "pausado", notas: nil))
assert(missing.contains("No encontré") && NoktaAPI.writes == 0)
let invalid = try await tool.call(arguments: .init(nombre: "TuBoleto", estado: "desconocido", notas: nil))
assert(invalid.contains("inválido") && NoktaAPI.writes == 0)
let paused = try await tool.call(arguments: .init(nombre: "fati lo", estado: " PAUSADO ", notas: "Pausa temporal"))
assert(paused.contains("Fátima López") && NoktaAPI.writes == 1)
assert(NoktaAPI.lastPath == "/api/clientes-estados/F%C3%A1tima%20L%C3%B3pez")
assert(NoktaAPI.lastBody["notas"] == "Pausa temporal" && NoktaAPI.lastBody["estado"] == "pausado")
_ = try await tool.call(arguments: .init(nombre: "tu boleto", estado: "activo", notas: nil))
assert(NoktaAPI.lastBody["notas"] == nil && NoktaAPI.lastBody["estado"] == "activo")
_ = try await tool.call(arguments: .init(nombre: "cliente nuevo", estado: "pausado", notas: nil))
assert(NoktaAPI.lastPath == "/api/clientes-estados/Cliente%20Nuevo")
NoktaAPI.failRead = true
let writesBeforeFailure = NoktaAPI.writes
do {
    _ = try await tool.call(arguments: .init(nombre: "TuBoleto", estado: "pausado", notas: nil))
    assertionFailure("A failed live read must not permit a write")
} catch {}
assert(NoktaAPI.writes == writesBeforeFailure)
NoktaAPI.failRead = false
NoktaAPI.badResponse = true
do {
    _ = try await tool.call(arguments: .init(nombre: "TuBoleto", estado: "pausado", notas: nil))
    assertionFailure("A mismatched response must not claim success")
} catch {}
print("PASS: canonical/partial/ambiguous/unknown names, no writes on ambiguity/read failure, validated state, note preservation and server response")
'''
with tempfile.TemporaryDirectory(prefix='nokta-resolver-check-') as directory:
    path = Path(directory) / 'check.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)
