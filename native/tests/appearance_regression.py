#!/usr/bin/env python3
"""Real palette + Observation, isolated defaults; no app data or API calls."""
from pathlib import Path
import subprocess, tempfile, uuid
root=Path(__file__).resolve().parents[1]
source=(root/'NoktaStudio/Core/DesignSystem.swift').read_text().split('/// Flat surface card')[0]
suite='nokta.theme.test.'+str(uuid.uuid4())
source=source.replace('UserDefaults = .standard', f'UserDefaults = UserDefaults(suiteName: "{suite}")!')
source+='''
let store = NoktaAppearance.shared
let defaults = UserDefaults(suiteName: "SUITE")!
defer { defaults.removePersistentDomain(forName: "SUITE") }
func rgb(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }
store.selection = .oscuro
let dark = rgb(NoktaTheme.fondo)
var invalidated = false
withObservationTracking {
    _ = NoktaTheme.fondo
    _ = NoktaPalette.servicioPie
} onChange: { invalidated = true }
store.selection = .claro
precondition(invalidated, "Palette read must register an Observation dependency")
let light = rgb(NoktaTheme.fondo)
precondition(light.red > 0.9 && dark.red < 0.1)
precondition(rgb(NoktaPalette.bg) == light)
precondition(defaults.string(forKey: "noktaApariencia") == "claro")
precondition(NoktaAppearance(defaults: defaults).selection == .claro)
store.systemScheme = .dark
store.selection = .sistema
precondition(rgb(NoktaTheme.fondo) == dark)
var systemInvalidated = false
withObservationTracking { _ = NoktaPalette.bg } onChange: { systemInvalidated = true }
store.systemScheme = .light
precondition(systemInvalidated)
precondition(rgb(NoktaTheme.fondo) == light)
store.selection = .oscuro
store.systemScheme = .light
precondition(rgb(NoktaTheme.fondo) == dark)
print("PASS: concrete RGB, shared legacy colors, Observation invalidation, persistence, automatic system updates, explicit override")
'''.replace('SUITE',suite)
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)/'main.swift';p.write_text(source)
    subprocess.run(['swift',str(p)],check=True)
