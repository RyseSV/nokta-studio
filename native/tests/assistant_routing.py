#!/usr/bin/env python3
"""Exercise the actual read-only route without Apple Intelligence or network access."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / "NoktaStudio"
source = (root / "Assistant/ConsultaCobrosRouting.swift").read_text()
source += r'''
for prompt in ["¿Cuánto me deben este mes?", "CUÁNTO ME DEBEN", "saldo pendiente este mes"] {
    assert(ConsultaCobrosRouting.esConsultaDirecta(prompt, siguiendoCobros: false))
    assert(!ConsultaCobrosRouting.esSeguimiento(prompt))
}
for prompt in ["trabajos", "pq", "¿Por qué?", "dame el desglose"] {
    assert(ConsultaCobrosRouting.esConsultaDirecta(prompt, siguiendoCobros: true))
    assert(!ConsultaCobrosRouting.esConsultaDirecta(prompt, siguiendoCobros: false))
    assert(ConsultaCobrosRouting.esSeguimiento(prompt))
}
for prompt in ["registra un pago", "cuánto me debe Juan", "cuánto me deben en agosto", "gastos de equipo", "crea un trabajo", "cuánto me deben este mes y pausa a Juan"] {
    assert(!ConsultaCobrosRouting.esConsultaDirecta(prompt, siguiendoCobros: true))
}
print("PASS: debt queries, screenshot follow-ups, reset context, client/month-specific requests and mutation boundaries")
'''
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / "main.swift"
    script.write_text(source)
    subprocess.run(["swift", str(script)], check=True)
