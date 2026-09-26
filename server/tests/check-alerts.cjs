// QA sweep for checkAlerts() (server/app.js) — comportamiento esperado,
// entradas inválidas, valores vacíos, límites, errores esperados y casos
// poco comunes. Runs the REAL function (sliced out of app.js and executed
// in a vm context against fake in-memory models), not a reimplementation.
const assert = require('node:assert/strict');
const { newWorld } = require('./check-alerts-harness.cjs');

let pass = 0, fail = 0;
async function test(name, fn) {
  try { await fn(); pass++; console.log(`PASS: ${name}`); }
  catch (e) { fail++; console.log(`FAIL: ${name}\n  ${e.message}`); }
}
const iso = (d) => d.toISOString();
const daysFromNow = (n, base) => new Date(base.getTime() + n * 86400000);

(async () => {
  const NOW = new Date('2026-03-10T12:00:00Z'); // fixed "today" for every test below

  await test('fechas de inicio inválidas no inventan quincenas después del día 15', async () => {
    for (const fechaInicio of ['no-es-fecha', '2026-13-01', '2026-02-30', '2026-09-01Tinvalid', {}, '']) {
      const ctx = newWorld({ trabajos: [{ id: 'invalid', grupo: 'B', cliente: 'Demo', pagoMensual: 100, fechaInicio }] }, new Date('2026-09-24T12:00:00Z'));
      await ctx.__checkAlerts();
      assert.equal(ctx.Alerta._docs().length, 0, JSON.stringify(fechaInicio));
    }
  });

  // ── 1. Comportamiento esperado ─────────────────────────────────────
  await test('cliente a 2 días de expirar genera link_venciendo con diasRestantes correcto', async () => {
    const ctx = newWorld({
      clientes: [{ codigo: 'NK-1', nombre: 'Fátima', estado: 'activo', expira: iso(daysFromNow(2, NOW)) }],
    }, NOW);
    await ctx.__checkAlerts();
    const a = ctx.Alerta._docs().find(a => a.tipo === 'link_venciendo');
    assert.ok(a, 'esperaba una alerta link_venciendo');
    assert.equal(a.datos.codigo, 'NK-1');
    assert.equal(a.datos.diasRestantes, 2);
  });

  await test('trabajo grupo A pendiente hace 10 días genera pago_pendiente', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 't1', grupo: 'A', estado: 'pendiente', cliente: 'Ana', servicio: 'Fotos', saldo: 150, creado: iso(daysFromNow(-10, NOW)) }],
    }, NOW);
    await ctx.__checkAlerts();
    const a = ctx.Alerta._docs().find(a => a.tipo === 'pago_pendiente');
    assert.ok(a, 'esperaba una alerta pago_pendiente');
    assert.equal(a.datos.saldo, 150);
  });

  await test('quincena vencida sin pagar de contrato grupo B activo genera quincena_vencida', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 't2', grupo: 'B', cliente: 'TuBoleto', pagoMensual: 200, fechaInicio: '2026-01-01', quincenas: [] }],
      estados: [{ nombre: 'TuBoleto', estado: 'activo' }],
    }, NOW);
    await ctx.__checkAlerts();
    const alertas = ctx.Alerta._docs().filter(a => a.tipo === 'quincena_vencida');
    assert.ok(alertas.length > 0, 'esperaba al menos una alerta quincena_vencida (enero ya venció por completo)');
    assert.ok(alertas.every(a => a.datos.monto === 100), 'cada quincena debe ser la mitad del pago mensual');
  });

  await test('evento a 24 horas genera evento_proximo', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 't3', cliente: 'Boda López', servicio: 'boda', fecha: '2026-03-11', horaInicio: '12:00' }],
    }, NOW);
    await ctx.__checkAlerts();
    const a = ctx.Alerta._docs().find(a => a.tipo === 'evento_proximo');
    assert.ok(a, 'esperaba una alerta evento_proximo');
  });

  // ── 2. Entradas inválidas ───────────────────────────────────────────
  await test('fechaInicio no parseable en un contrato grupo B no truena ni genera alertas falsas', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 't4', grupo: 'B', cliente: 'X', pagoMensual: 100, fechaInicio: 'no-es-una-fecha', quincenas: [] }],
      estados: [{ nombre: 'X', estado: 'activo' }],
    }, NOW);
    await assert.doesNotReject(() => ctx.__checkAlerts());
    assert.equal(ctx.Alerta._docs().filter(a => a.tipo === 'quincena_vencida').length, 0);
  });

  await test('cliente con expira="" (fecha inválida) no truena ni genera link_venciendo', async () => {
    const ctx = newWorld({
      clientes: [{ codigo: 'NK-2', nombre: 'Y', estado: 'activo', expira: '' }],
    }, NOW);
    await assert.doesNotReject(() => ctx.__checkAlerts());
    assert.equal(ctx.Alerta._docs().length, 0);
  });

  // ── 3. Valores vacíos ────────────────────────────────────────────────
  await test('bases de datos completamente vacías no truenan y no generan nada', async () => {
    const ctx = newWorld({}, NOW);
    await assert.doesNotReject(() => ctx.__checkAlerts());
    assert.equal(ctx.Alerta._docs().length, 0);
  });

  await test('trabajo pendiente sin campo creado no genera pago_pendiente (guardado explícito)', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 't5', grupo: 'A', estado: 'pendiente', cliente: 'Z', saldo: 50 }], // sin `creado`
    }, NOW);
    await ctx.__checkAlerts();
    assert.equal(ctx.Alerta._docs().filter(a => a.tipo === 'pago_pendiente').length, 0);
  });

  // ── 4. Límites ───────────────────────────────────────────────────────
  await test('link a exactamente 3 días SÍ alerta; a 4 días NO alerta (borde inclusive en <=3)', async () => {
    const ctx = newWorld({
      clientes: [
        { codigo: 'A3', nombre: 'A3', estado: 'activo', expira: iso(daysFromNow(3, NOW)) },
        { codigo: 'A4', nombre: 'A4', estado: 'activo', expira: iso(daysFromNow(4, NOW)) },
      ],
    }, NOW);
    await ctx.__checkAlerts();
    const avisados = ctx.Alerta._docs().filter(a => a.tipo === 'link_venciendo').map(a => a.datos.codigo);
    assert.deepEqual(avisados, ['A3']);
  });

  await test('pago pendiente a exactamente 7 días SÍ alerta; a 6 días NO alerta (borde inclusive en >=7)', async () => {
    const ctx = newWorld({
      trabajos: [
        { id: 'p7', grupo: 'A', estado: 'pendiente', cliente: 'P7', saldo: 10, creado: iso(daysFromNow(-7, NOW)) },
        { id: 'p6', grupo: 'A', estado: 'pendiente', cliente: 'P6', saldo: 10, creado: iso(daysFromNow(-6, NOW)) },
      ],
    }, NOW);
    await ctx.__checkAlerts();
    const avisados = ctx.Alerta._docs().filter(a => a.tipo === 'pago_pendiente').map(a => a.datos.cliente);
    assert.deepEqual(avisados, ['P7']);
  });

  await test('quincena Q1 cuyo vencimiento (día 15) todavía no llega no genera alerta prematura', async () => {
    // "Hoy" = 10 de marzo, antes del vencimiento del 15 — ninguna quincena de
    // marzo debería avisar todavía, y el mes no debe "brincarse" meses
    // atrasados reales anteriores por el mismo cálculo (ver siguiente prueba).
    const ctx = newWorld({
      trabajos: [{ id: 'tq', grupo: 'B', cliente: 'Q', pagoMensual: 100, fechaInicio: '2026-03-01', quincenas: [] }],
      estados: [{ nombre: 'Q', estado: 'activo' }],
    }, NOW);
    await ctx.__checkAlerts();
    assert.equal(ctx.Alerta._docs().filter(a => a.tipo === 'quincena_vencida').length, 0);
  });

  await test('una quincena vieja sin pagar SÍ se avisa aunque el mes actual todavía no venza (no se salta por el avance de mes en cur)', async () => {
    // Regresión dirigida al bucle de checkAlerts: dentro del `for(q of [1,2])`,
    // la rama "not due yet" hace `cur.setMonth(cur.getMonth()+1)` y sigue
    // usando ese mismo `cur` mutado para calcular el vencimiento de la
    // segunda quincena, y el bucle exterior vuelve a avanzar el mes otra vez
    // al salir — tres avances de mes en una sola vuelta. Esta prueba confirma
    // que ese comportamiento no hace que se salte un mes anterior con una
    // quincena real y vieja sin pagar.
    const ctx = newWorld({
      trabajos: [{ id: 'tOld', grupo: 'B', cliente: 'Vieja', pagoMensual: 100, fechaInicio: '2026-01-01', quincenas: [] }],
      estados: [{ nombre: 'Vieja', estado: 'activo' }],
    }, NOW); // NOW = 10 de marzo: enero y febrero ya vencidos por completo; marzo Q1 aún no.
    await ctx.__checkAlerts();
    const periodos = ctx.Alerta._docs().filter(a => a.tipo === 'quincena_vencida').map(a => `${a.datos.periodo}-q${a.datos.q}`);
    for (const esperado of ['2026-01-q1', '2026-01-q2', '2026-02-q1', '2026-02-q2']) {
      assert.ok(periodos.includes(esperado), `esperaba ${esperado} entre las alertas generadas, salió: ${periodos.join(', ')}`);
    }
    assert.ok(!periodos.includes('2026-03-q1'), 'marzo Q1 no debería avisar todavía (vence el 15)');
  });

  // ── 5. Errores esperados / regresión ────────────────────────────────
  await test('no duplica una alerta link_venciendo ya existente para el mismo código', async () => {
    const ctx = newWorld({
      clientes: [{ codigo: 'DUP', nombre: 'Dup', estado: 'activo', expira: iso(daysFromNow(1, NOW)) }],
      alertas: [{ id: 'a1', tipo: 'link_venciendo', datos: { codigo: 'DUP' }, leida: false }],
    }, NOW);
    await ctx.__checkAlerts();
    assert.equal(ctx.Alerta._docs().filter(a => a.tipo === 'link_venciendo').length, 1);
  });

  await test('regresión: al expirar un cliente, sus demás campos siguen intactos (no se reemplaza el documento)', async () => {
    const ctx = newWorld({
      clientes: [{ codigo: 'EXP', nombre: 'Expira Ya', estado: 'activo', expira: iso(daysFromNow(-1, NOW)), visitas: ['2026-01-01'] }],
    }, NOW);
    await ctx.__checkAlerts();
    const c = ctx.Cliente._docs().find(c => c.codigo === 'EXP');
    assert.equal(c.estado, 'expirado');
    assert.equal(c.nombre, 'Expira Ya', 'el nombre no debería haberse borrado');
    assert.deepEqual(c.visitas, ['2026-01-01'], 'las visitas no deberían haberse borrado');
  });

  // ── 6. Casos poco comunes ───────────────────────────────────────────
  await test('contrato grupo B con cliente pausado no genera ninguna alerta de quincena vencida', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 'tPaused', grupo: 'B', cliente: 'Pausado', pagoMensual: 100, fechaInicio: '2026-01-01', quincenas: [] }],
      estados: [{ nombre: 'Pausado', estado: 'pausado' }],
    }, NOW);
    await ctx.__checkAlerts();
    assert.equal(ctx.Alerta._docs().filter(a => a.tipo === 'quincena_vencida').length, 0);
  });

  await test('quincena marcada "oculta" no vuelve a generar alerta aunque esté vencida', async () => {
    const ctx = newWorld({
      trabajos: [{
        id: 'tOculta', grupo: 'B', cliente: 'Oculta', pagoMensual: 100, fechaInicio: '2026-01-01',
        quincenas: [{ periodo: '2026-01', q: 1, estado: 'oculta', monto: 50 }],
      }],
      estados: [{ nombre: 'Oculta', estado: 'activo' }],
    }, NOW);
    await ctx.__checkAlerts();
    const periodos = ctx.Alerta._docs().filter(a => a.tipo === 'quincena_vencida').map(a => `${a.datos.periodo}-q${a.datos.q}`);
    assert.ok(!periodos.includes('2026-01-q1'), 'la quincena oculta no debería re-avisar');
    assert.ok(periodos.includes('2026-01-q2'), 'pero la otra quincena de enero sí debe avisar');
  });

  // ── Clases (sesiones) y eventos del calendario ─────────────────────
  const CLASE_NOW = new Date('2026-09-25T15:00:00Z');
  const fatima = (sesiones) => ({ id: 'tF', cliente: 'Clases de IA Fátima', servicio: 'Clases', estado: 'pendiente', sesiones });
  const proximos = (ctx) => ctx.Alerta._docs().filter(a => a.tipo === 'evento_proximo');

  await test('clase de mañana genera evento_proximo (una sola vez)', async () => {
    const ctx = newWorld({ trabajos: [fatima([{ id: 's1', fecha: '2026-09-26', monto: 60, estado: 'pendiente' }])] }, CLASE_NOW);
    await ctx.__checkAlerts(); await ctx.__checkAlerts();
    const a = proximos(ctx);
    assert.equal(a.length, 1);
    assert.equal(a[0].datos.tipo, 'Clase');
    assert.equal(a[0].datos.id, 'tF');
    assert.equal(a[0].datos.fecha, '2026-09-26');
  });

  await test('clase cancelada, oculta o lejana no genera alerta', async () => {
    const ctx = newWorld({ trabajos: [fatima([
      { id: 'c', fecha: '2026-09-26', estado: 'cancelado' },
      { id: 'o', fecha: '2026-09-26', estado: 'oculta' },
      { id: 'l', fecha: '2026-10-10', estado: 'pendiente' },
      { id: 'p', fecha: '2026-09-20', estado: 'pendiente' },
    ])] }, CLASE_NOW);
    await ctx.__checkAlerts();
    assert.equal(proximos(ctx).length, 0);
  });

  await test('cliente pausado: ni su clase ni su evento de calendario avisan', async () => {
    const ctx = newWorld({
      trabajos: [fatima([{ id: 's1', fecha: '2026-09-26', estado: 'pendiente' }])],
      eventos: [{ id: 'e1', titulo: 'Clases de IA Fátima — Clases', tipo: 'Clases', fecha: '2026-09-26' }],
      estados: [{ nombre: 'Clases de IA Fátima', estado: 'pausado' }],
    }, CLASE_NOW);
    await ctx.__checkAlerts();
    assert.equal(proximos(ctx).length, 0);
  });

  await test('clase con su evento en el calendario: una sola alerta, con la hora del evento', async () => {
    const ctx = newWorld({
      trabajos: [fatima([{ id: 's1', fecha: '2026-09-26', estado: 'pendiente' }])],
      eventos: [{ id: 'e1', titulo: 'Clases de IA Fátima — Clases', tipo: 'Clases', fecha: '2026-09-26', horaInicio: '10:00' }],
    }, CLASE_NOW);
    await ctx.__checkAlerts();
    const a = proximos(ctx);
    assert.equal(a.length, 1);
    assert.equal(a[0].datos.hora, '10:00');
  });

  await test('evento suelto del calendario en las próximas 48 h avisa; uno pasado o lejano no', async () => {
    const ctx = newWorld({ eventos: [
      { id: 'e1', titulo: 'Reunión Vértice — Branding', tipo: 'Branding', fecha: '2026-09-26', horaInicio: '9:30' },
      { id: 'e2', titulo: 'Boda López — Boda', tipo: 'Boda', fecha: '2026-10-20' },
      { id: 'e3', titulo: 'Ayer — Evento', tipo: 'Evento', fecha: '2026-09-24' },
    ] }, CLASE_NOW);
    await ctx.__checkAlerts();
    const a = proximos(ctx);
    assert.equal(a.length, 1);
    assert.equal(a[0].datos.id, 'e1');
    assert.equal(a[0].datos.cliente, 'Reunión Vértice');
    assert.equal(a[0].datos.key, 'ev-e1');
  });

  await test('evento que es el mismo de un trabajo no se duplica', async () => {
    const ctx = newWorld({
      trabajos: [{ id: 'tw', cliente: 'María López', servicio: 'Boda', estado: 'pendiente', fecha: '2026-09-26', horaInicio: '16:00' }],
      eventos: [{ id: 'tw', titulo: 'María López — Boda', tipo: 'Boda', fecha: '2026-09-26', horaInicio: '16:00' }],
    }, CLASE_NOW);
    await ctx.__checkAlerts();
    assert.equal(proximos(ctx).length, 1);
  });

  console.log(`\n${pass} pasaron, ${fail} fallaron`);
  process.exitCode = fail ? 1 : 0;
})();
