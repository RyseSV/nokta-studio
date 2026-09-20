const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync('/Users/gabrielcerritos/Library/Mobile Documents/com~apple~CloudDocs/Nokta Apps/NOKTA/server/views/admin.html', 'utf8');

// Pull out just the pieces contratoHTML needs, same slicing technique the
// other admin-*.cjs tests use, then run the whole inline <script> through
// new vm.Script() to catch any syntax error in the new code.
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
for (const [, script] of scripts) if (script.trim()) new vm.Script(script);
console.log('PASS: no syntax errors in any inline <script>');

const esc = s => String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const code = html.slice(html.indexOf('function contratoHTML'), html.indexOf('function confirmarContrato'));
const ctx = { esc, location: { origin: 'https://example.test' } };
vm.createContext(ctx);
vm.runInContext(code, ctx);

const out = ctx.contratoHTML({
  ciudad: 'San Salvador', fechaContrato: '20 de septiembre de 2026',
  clienteNombre: 'Fátima', clienteDui: '01234567-8', clienteTelefono: '7000-0000',
  clienteEmail: 'f@x.com', clienteDireccion: 'Col. Ejemplo',
  servicioTipo: 'Clases', servicioFecha: '12 sep 2026', servicioLugar: 'Online',
  entregables: 'Grabaciones', anticipoMonto: '60', anticipoFecha: '20 de septiembre de 2026',
  saldoMonto: '60', saldoFecha: '30 de septiembre de 2026', plazoDias: '7', mora: '10',
});
assert.match(out, /Fátima/);
assert.match(out, /10\.00 DÓLARES DE LOS ESTADOS UNIDOS DE AMÉRICA\s*\(US\$10\.00\)/);
assert.match(out, /\$120\.00/); // total = 60+60
assert.match(out, /<span class="num">9<\/span>/); // all 9 clauses present
console.log('PASS: contratoHTML renders client data, mora clause, and total correctly');
