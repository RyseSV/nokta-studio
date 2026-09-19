#!/usr/bin/env python3
"""Evaluate the current production selector with local Apple FoundationModels.

Requires an available on-device model. Uses synthetic conversations and no tools,
network calls, or real business data. Fails if an area/action expectation differs.
Usage: python3 native/tests/conversation_model.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / 'NoktaStudio'
conversation = (root / 'Assistant/AssistantConversation.swift').read_text()
# Keep the real generated schema and routing instructions; exclude app-only code.
source = conversation.split('    static let instructions', 1)[0] + '}\n'
source += r'''
guard case .available = SystemLanguageModel.default.availability else {
    print("FAIL: local FoundationModels unavailable: \(SystemLanguageModel.default.availability)")
    exit(1)
}
let cases: [(String, String, String, Bool)] = [
    ("pago informal", "Historial reciente: \nMensaje actual de Gabriel: Fátima ya me pagó. el sábado", "pagos", true),
    ("dictado", "Mensaje actual de Gabriel: marca como... marca como pagado lo 20 de Fátima del sábado 19", "pagos", true),
    ("consulta", "Mensaje actual de Gabriel: cuanto me debe fatima", "pagos", false),
    ("negación", "Gabriel: marca el pago de Fátima\nAsistente: ¿De qué fecha?\nMensaje actual de Gabriel: no lo marques todavía", "pagos", false),
    ("fecha contextual", "Gabriel: Fátima ya me pagó los 20\nAsistente: ¿De qué fecha es la sesión?\nMensaje actual de Gabriel: la del sábado 19", "pagos", true),
    ("confirmación", "Gabriel: poné en pausa a TuBoleto\nAsistente: ¿Confirmas pausar a TuBoleto?\nMensaje actual de Gabriel: sí hacelo", "clientes", true),
    ("pq no repite", "Gabriel: marca pagada Fátima\nAsistente: Sesión del 19 marcada pagada\nMensaje actual de Gabriel: pq", "pagos", false),
    ("crear", "Mensaje actual de Gabriel: agregale una clase a Fatima el sábado 26 por 20", "trabajos", true)
]
var failures = 0
for (label, prompt, area, action) in cases {
    do {
        let session = LanguageModelSession(instructions: AssistantConversation.routingInstructions)
        let result = try await session.respond(to: prompt, generating: AssistantSelection.self, options: GenerationOptions(sampling: .greedy)).content
        let matches = Set(result.areas.map(\.rawValue)) == Set([area]) && result.accion == action
        print("\(matches ? "PASS" : "FAIL"): \(label): areas=\(result.areas.map(\.rawValue)), accion=\(result.accion)")
        if !matches { failures += 1 }
    } catch {
        print("FAIL: \(label): \(error)")
        failures += 1
    }
}
guard failures == 0 else {
    print("FAIL: \(failures) routing assertions did not pass")
    exit(1)
}
print("PASS: all 8 production-selector assertions")
'''
with tempfile.TemporaryDirectory(prefix='nokta-conversation-check-') as directory:
    path = Path(directory) / 'check.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True, timeout=240)
