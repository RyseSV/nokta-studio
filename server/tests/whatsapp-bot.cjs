// Bot de WhatsApp: rutas reales de Express + conversación completa, con
// Mongo y la API de Meta/Telegram sustituidos por dobles en memoria.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const express = require('express');
const bot = require('../whatsapp-bot');

// ── Mongo en memoria ─────────────────────────────────────────
const chats = new Map(), vistos = new Set();
bot.BotMensaje.create = async ({ _id }) => { if (vistos.has(_id)) throw Object.assign(Error('dup'), { code: 11000 }); vistos.add(_id); };
bot.BotChat.findOneAndUpdate = async ({ telefono }, { $set }) => { const c = { ...(chats.get(telefono) || { telefono }), ...$set }; chats.set(telefono, c); return { ...c }; };
bot.BotChat.findOne = ({ telefono }) => ({ lean: async () => (chats.has(telefono) ? { ...chats.get(telefono) } : null) });
bot.BotChat.updateOne = async ({ telefono }, { $set }) => { chats.set(telefono, { ...chats.get(telefono), ...$set }); };

// ── Meta / Telegram simulados ────────────────────────────────
let enviados = [], telegram = [], alertas = [];
const fetchImpl = async (url, opts) => {
  const body = JSON.parse(opts.body);
  if (url.includes('api.telegram.org')) telegram.push(body); else enviados.push({ url, auth: opts.headers.Authorization, ...body });
  return { ok: true, status: 200, text: async () => '' };
};
// Colección Alerta en memoria (lo que ve Gabriel en Nokta)
let store = [];
const addAlert = async (tipo, datos) => { alertas.push({ tipo, datos }); store.push({ id: `a${store.length}`, tipo, datos: { ...datos }, leida: false }); };
const Alerta = {
  findOne: (q) => ({ lean: async () => store.find((a) => a.tipo === q.tipo && a.datos.telefono === q['datos.telefono'] && a.leida === q.leida) || null }),
  updateOne: async ({ id }, { $set }) => { const a = store.find((x) => x.id === id); a.datos.mensaje = $set['datos.mensaje']; a.datos.nombre = $set['datos.nombre']; a.fecha = $set.fecha; },
};
const logs = []; const log = { warn: (...a) => logs.push(a.join(' ')), error: (...a) => logs.push(a.join(' ')) };

Object.assign(process.env, {
  WHATSAPP_TOKEN: 'tok', WHATSAPP_PHONE_NUMBER_ID: '123', WHATSAPP_VERIFY_TOKEN: 'palabra',
  WHATSAPP_APP_SECRET: 'secreto', TELEGRAM_BOT_TOKEN: 'tg', TELEGRAM_CHAT_ID: '99',
});

const { procesar } = bot.crearBot({ addAlert, Alerta, fetchImpl, log, pausaEntreTarjetasMs: 0 });
const BASE = 'https://nokta.test';
let n = 0;
const msg = (m, nombre = 'Ana') => ({ entry: [{ changes: [{ value: { contacts: [{ wa_id: '50370000000', profile: { name: nombre } }], messages: [{ from: '50370000000', id: `wamid.${++n}`, ...m }] } }] }] });
const texto = (t) => msg({ type: 'text', text: { body: t } });
const toque = (id, title = id) => msg({ type: 'interactive', interactive: { type: id.startsWith('interes_') || id === 'menu' ? 'button_reply' : 'list_reply', [id.startsWith('interes_') || id === 'menu' ? 'button_reply' : 'list_reply']: { id, title } } });
const limpiar = () => { enviados = []; telegram = []; alertas = []; };

(async () => {
  // 1. Primer mensaje → UN solo mensaje: imagen + saludo + 3 botones (en orden garantizado)
  await procesar(texto('Hola, info'), BASE);
  assert.equal(enviados.length, 1);
  assert.equal(enviados[0].interactive.type, 'button');
  assert.equal(enviados[0].interactive.header.image.link, `${BASE}/public/bot/bienvenida.png`);
  assert.deepEqual(enviados[0].interactive.action.buttons.map((b) => b.reply.id), ['planes', 'cotizar', 'humano']);
  enviados[0].interactive.action.buttons.forEach((b) => assert.ok(b.reply.title.length <= 20, b.reply.title));
  assert.ok(enviados[0].interactive.body.text.length <= 1024);
  assert.equal(enviados[0].to, '50370000000');
  assert.equal(enviados[0].auth, 'Bearer tok');
  assert.match(enviados[0].url, /graph\.facebook\.com\/v\d+\.0\/123\/messages$/);
  // El menú completo (lista) sale cuando el cliente vuelve a escribir
  limpiar(); await procesar(texto('Hola'), BASE);
  assert.equal(enviados[0].interactive.type, 'list');
  const filas = enviados[0].interactive.action.sections[0].rows;
  assert.deepEqual(filas.map((r) => r.id), ['planes', 'trabajo', 'cotizar', 'humano']);
  // Límites de WhatsApp: título ≤24, descripción ≤72, botón ≤20
  filas.forEach((r) => { assert.ok(r.title.length <= 24, r.title); assert.ok(r.description.length <= 72); });
  assert.ok(enviados[0].interactive.action.button.length <= 20);
  assert.equal(chats.get('50370000000').nombre, 'Ana');

  // 2. Reintento de Meta del mismo mensaje → no contesta dos veces
  limpiar(); const repetido = texto('otra vez'); await procesar(repetido, BASE); const primeraVez = enviados.length;
  await procesar(repetido, BASE); assert.equal(enviados.length, primeraVez);

  // 3. Texto libre el mismo día → sin imagen, "no entendí" + menú
  limpiar(); await procesar(texto('cuánto cuesta?'), BASE);
  assert.deepEqual(enviados.map((e) => e.type), ['text', 'interactive']);
  assert.match(enviados[0].text.body, /no entendí/);
  // …pero "hola" no lleva "no entendí"
  limpiar(); await procesar(texto('Hola'), BASE);
  assert.deepEqual(enviados.map((e) => e.type), ['interactive']);

  // 4. Planes → 3 tarjetas con imagen y botones
  limpiar(); await procesar(toque('planes', 'Planes mensuales'), BASE);
  assert.equal(enviados.length, 3);
  enviados.forEach((e, i) => {
    const archivo = ['plan-inicio.png', 'plan-presencia.png', 'plan-impulso.png'][i];
    assert.equal(e.interactive.header.image.link, `${BASE}/public/bot/${archivo}`);
    assert.ok(e.interactive.body.text.split('\n').length <= 3, 'textos cortos');
    e.interactive.action.buttons.forEach((b) => assert.ok(b.reply.title.length <= 20));
  });
  assert.equal(enviados[2].interactive.action.buttons[0].reply.id, 'interes_impulso');

  // 5. "Me interesa" → alerta + Telegram + respuesta, y el bot se pausa
  limpiar(); await procesar(toque('interes_impulso', 'Me interesa'), BASE);
  assert.deepEqual(alertas, [{ tipo: 'whatsapp', datos: { nombre: 'Ana', telefono: '50370000000', mensaje: 'Le interesa el plan Impulso ($350/mes)' } }]);
  assert.equal(telegram.length, 1);
  assert.equal(telegram[0].parse_mode, 'HTML');
  assert.match(telegram[0].text, /wa\.me\/50370000000/);
  assert.match(enviados[0].text.body, /Gabriel le escribe/);
  assert.ok(chats.get('50370000000').pausaHasta > new Date());

  // 6. En pausa: lo que escriba se suma a la MISMA alerta (sin llenar la
  // lista) y el bot no contesta; Telegram máx. 1 aviso por minuto
  limpiar(); await procesar(texto('Tengo una panadería'), BASE);
  assert.equal(enviados.length, 0); assert.equal(alertas.length, 0); assert.equal(telegram.length, 0);
  assert.equal(store.length, 1);
  assert.equal(store[0].datos.mensaje, 'Le interesa el plan Impulso ($350/mes)\nTengo una panadería');
  // …un audio también se avisa
  limpiar(); await procesar(msg({ type: 'audio', audio: {} }), BASE);
  assert.equal(enviados.length, 0); assert.match(store[0].datos.mensaje, /audio/); assert.equal(store.length, 1);
  // Cuando Gabriel la marca como leída, el siguiente mensaje crea una nueva
  store[0].leida = true; chats.get('50370000000').ultimoTelegram = null;
  limpiar(); await procesar(texto('¿Sigue ahí?'), BASE);
  assert.equal(store.length, 2); assert.equal(telegram.length, 1); store = [];
  // …pero "menú" (o el botón "Ver menú") quita la pausa
  limpiar(); await procesar(toque('menu', 'Ver menú'), BASE);
  assert.equal(enviados[0].interactive.type, 'list'); assert.equal(alertas.length, 0);
  assert.equal(chats.get('50370000000').pausaHasta, null);

  // 7. Cotización: pide detalle, luego alerta con lo que escribió
  limpiar(); await procesar(toque('cotizar', 'Pedir cotización'), BASE);
  assert.match(enviados[0].text.body, /Cuéntenos/);
  limpiar(); await procesar(msg({ type: 'image', image: {} }), BASE);
  assert.match(enviados[0].text.body, /solo puedo leer texto/); assert.equal(alertas.length, 0);
  limpiar(); await procesar(texto('Restaurante, necesito redes'), BASE);
  assert.equal(alertas[0].datos.mensaje, 'Pide cotización: Restaurante, necesito redes');
  store = [];
  assert.match(enviados[0].text.body, /cotización/);
  assert.equal(chats.get('50370000000').paso, null);

  // 8. Hablar con Gabriel
  await procesar(toque('menu', 'Ver menú'), BASE);
  limpiar(); await procesar(toque('humano', 'Hablar con Gabriel'), BASE);
  assert.equal(alertas[0].datos.mensaje, 'Quiere hablar con usted');
  assert.match(enviados[0].text.body, /Gabriel le responde/);

  // 8b. "Pedir cotización" y luego otra opción: el texto siguiente ya no es cotización
  await procesar(toque('menu', 'Ver menú'), BASE); store = [];
  await procesar(toque('cotizar'), BASE); await procesar(toque('planes'), BASE);
  limpiar(); await procesar(texto('gracias'), BASE);
  assert.equal(alertas.length, 0); assert.equal(enviados.at(-1).interactive.type, 'list');
  // "menú" con tilde no es "no entendí"
  limpiar(); await procesar(texto('Menú'), BASE);
  assert.deepEqual(enviados.map((e) => e.type), ['interactive']);

  // 8c. "Borrar mis datos" borra el chat y sus alertas, incluso en pausa
  await procesar(toque('humano'), BASE);
  store.push({ id: 'otra', tipo: 'whatsapp', datos: { telefono: '50370000000', mensaje: 'x' }, leida: true });
  let borradas = null; Alerta.deleteMany = async (q) => { borradas = q; store = store.filter((a) => !(a.tipo === q.tipo && a.datos.telefono === q['datos.telefono'])); };
  bot.BotChat.deleteOne = async ({ telefono }) => { chats.delete(telefono); };
  limpiar(); await procesar(texto('Borrar mis datos'), BASE);
  assert.equal(chats.has('50370000000'), false);
  assert.deepEqual(borradas, { tipo: 'whatsapp', 'datos.telefono': '50370000000' });
  assert.equal(store.length, 1); assert.equal(store[0].datos.telefono, undefined, 'el aviso no guarda el número');
  assert.match(enviados[0].text.body, /borrado/); store = [];

  // 9. Telegram: el nombre del cliente no rompe el HTML
  chats.clear(); limpiar();
  await procesar(texto('Hola'), BASE); await procesar(toque('humano'), BASE, 'x');
  const conEtiqueta = msg({ type: 'interactive', interactive: { type: 'list_reply', list_reply: { id: 'humano' } } }, '<b>Eva & Co</b>');
  chats.clear(); limpiar(); await procesar(conEtiqueta, BASE);
  assert.match(telegram[0].text, /&lt;b&gt;Eva &amp; Co&lt;\/b&gt;/);

  // 10. Un fallo de Meta no tumba el resto ni filtra el token en los logs
  delete process.env.TELEGRAM_BOT_TOKEN;
  const { procesar: procesarFalla } = bot.crearBot({ addAlert, Alerta, log, fetchImpl: async () => ({ ok: false, status: 400, text: async () => '{"error":"x"}' }) });
  chats.clear(); logs.length = 0; store = []; limpiar(); await procesarFalla(texto('Hola'), BASE);
  assert.ok(logs.some((l) => /WhatsApp API 400/.test(l)));
  // …y el cliente no se pierde: Gabriel recibe una alerta
  assert.match(store[0].datos.mensaje, /no pudo responderle/);
  assert.ok(!logs.some((l) => l.includes('tok')), 'no se registra el token');

  // 11. Suscripción de la cuenta al arrancar: POST correcto, sin filtrar el token
  const llamadas = []; const out = [];
  await bot.asegurarSuscripcion(async (u, o) => { llamadas.push({ u, o }); return { ok: true, text: async () => '{"success":true}' }; }, { log: (m) => out.push(m), error: (m) => out.push(m) });
  assert.match(llamadas[0].u, /\/2075908746368446\/subscribed_apps$/); assert.equal(llamadas[0].o.method, 'POST');
  assert.match(out[0], /suscrita/);
  await bot.asegurarSuscripcion(async () => ({ ok: false, status: 403, text: async () => '{"error":"perm"}' }), { log: (m) => out.push(m), error: (m) => out.push(m) });
  assert.match(out[1], /403/); assert.ok(!out.join('').includes('Bearer'));
  process.env.WHATSAPP_TOKEN = 'tok'; // (el caso 10 lo dejó igual)

  const lg = { log: () => {}, error: () => {} };

  // 14. Coexistencia: si Gabriel contesta desde la app del móvil (eco), el bot se calla
  chats.clear(); limpiar();
  await procesar({ entry: [{ changes: [{ field: 'smb_message_echoes', value: { message_echoes: [{ from: '50374539315', to: '50370000000', id: 'eco1', type: 'text', text: { body: 'Hola, soy Gabriel' } }] } }] }] }, BASE);
  assert.ok(chats.get('50370000000').pausaHasta > new Date()); assert.equal(enviados.length, 0);
  await procesar({ entry: [{ changes: [{ value: { message_echoes: [{ to: 'x;drop' }] } }] }] }, BASE); // ignorado
  limpiar(); await procesar(texto('¿Y el precio?'), BASE);
  assert.equal(enviados.length, 0, 'en pausa no contesta');
  // Historial/contactos sincronizados no disparan respuestas
  limpiar(); chats.clear();
  await procesar({ entry: [{ changes: [{ field: 'history', value: { history: [{ threads: [{ id: '50370000000', messages: [{ from: '50370000000', id: 'h1', type: 'text', text: { body: 'viejo' } }] }] }] } }] }] }, BASE);
  assert.equal(enviados.length, 0);
  assert.equal(chats.get('50370000000').conocido, true);
  // …y a ese contacto de antes el bot no lo saluda; si pide "menú", sí
  limpiar(); await procesar(texto('Hola Gabriel, ¿cómo va mi pedido?'), BASE);
  assert.equal(enviados.length, 0); assert.equal(alertas.length, 0);
  limpiar(); await procesar(texto('menú'), BASE);
  assert.equal(enviados.length, 1, 'si pide el menú, el bot sí responde');
  // Contactos sincronizados (state_sync) también cuentan como conocidos
  await procesar({ entry: [{ changes: [{ value: { state_sync: [{ type: 'contact', action: 'add', contact: { full_name: 'Eva', phone_number: '+503 7111-2222' } }] } }] }] }, BASE);
  assert.equal(chats.get('50371112222').conocido, true);
  // Un número nuevo sí recibe la bienvenida
  limpiar(); await procesar(msg({ from: '50379990000', type: 'text', text: { body: 'Hola' } }), BASE);
  assert.ok(enviados.some((e) => e.to === '50379990000'));

  // 15. Sincronización tras conectar: contactos y luego historial, solo con id numérico
  const sincr = [];
  const fs2 = async (u, o) => { sincr.push({ u, b: JSON.parse(o.body) }); return { ok: true, text: async () => '{"success":true}' }; };
  delete process.env.WHATSAPP_SINCRONIZAR; await bot.sincronizarCoexistencia(fs2, lg); assert.equal(sincr.length, 0);
  process.env.WHATSAPP_SINCRONIZAR = '1234567890'; await bot.sincronizarCoexistencia(fs2, lg);
  assert.deepEqual(sincr.map((x) => x.b.sync_type), ['smb_app_state_sync', 'history']);
  assert.match(sincr[0].u, /\/1234567890\/smb_app_data$/); assert.equal(sincr[0].b.messaging_product, 'whatsapp');
  delete process.env.WHATSAPP_SINCRONIZAR;

  // ── Rutas HTTP reales ──────────────────────────────────────
  const app = express();
  bot.montarWhatsAppBot(app, { addAlert, fetchImpl, log }); // sin llamadas reales a Meta
  app.use(express.json()); // como en app.js: el json global va después
  const server = app.listen(0); const url = `http://127.0.0.1:${server.address().port}/webhook/whatsapp`;
  try {
    let r = await fetch(`${url}?hub.mode=subscribe&hub.verify_token=palabra&hub.challenge=abc123`);
    assert.equal(r.status, 200); assert.equal(await r.text(), 'abc123');
    r = await fetch(`${url}?hub.mode=subscribe&hub.verify_token=mala&hub.challenge=abc123`);
    assert.equal(r.status, 403);

    const cuerpo = JSON.stringify({ entry: [] });
    const firma = 'sha256=' + crypto.createHmac('sha256', 'secreto').update(cuerpo).digest('hex');
    r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Hub-Signature-256': firma }, body: cuerpo });
    assert.equal(r.status, 200);
    r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Hub-Signature-256': 'sha256=' + '0'.repeat(64) }, body: cuerpo });
    assert.equal(r.status, 401);
    r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: cuerpo });
    assert.equal(r.status, 401);
    // Sin clave secreta configurada: se rechaza todo (falla cerrado)
    delete process.env.WHATSAPP_APP_SECRET;
    r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Hub-Signature-256': firma }, body: cuerpo });
    assert.equal(r.status, 401);
    delete process.env.WHATSAPP_VERIFY_TOKEN;
    r = await fetch(`${url}?hub.mode=subscribe&hub.verify_token=&hub.challenge=abc`);
    assert.equal(r.status, 403);
  } finally { server.close(); }

  // ── Página de conexión (rutas reales con sesión simulada) ──
  const app3 = express(); let sesion = null; const vistos3 = []; const llam3 = [];
  app3.use(express.json()); app3.use((req, res, next) => { req.session = sesion; next(); });
  const reqAdmin = (req, res, next) => (req.session?.userId ? ((req.authUser = { username: 'gabo' }), next()) : res.status(401).json({ error: 'No autorizado' }));
  bot.montarConexionWhatsApp(app3, { requireAdmin: reqAdmin, log: { log: (m) => vistos3.push(m), error: (m) => vistos3.push(m) },
    fetchImpl: async (u) => { llam3.push(u); return { ok: true, text: async () => '{"data":[{"id":"999"}]}' }; } });
  const srv3 = app3.listen(0); const B3 = `http://127.0.0.1:${srv3.address().port}`;
  try {
    let r = await fetch(`${B3}/whatsapp/conectar`, { redirect: 'manual' });
    assert.equal(r.status, 302); assert.equal(r.headers.get('location'), '/admin');
    sesion = { userId: 'u1' };
    r = await fetch(`${B3}/whatsapp/conectar`);
    assert.equal(r.status, 200);
    assert.match(r.headers.get('content-security-policy'), /connect\.facebook\.net/);
    assert.equal(r.headers.get('cross-origin-opener-policy'), 'same-origin-allow-popups');
    assert.match(await r.text(), /whatsapp_business_app_onboarding/);
    delete process.env.WHATSAPP_APP_ID; delete process.env.WHATSAPP_CONFIG_ID;
    assert.equal((await fetch(`${B3}/api/whatsapp/config`)).status, 503);
    process.env.WHATSAPP_APP_ID = '111'; process.env.WHATSAPP_CONFIG_ID = '222';
    const cfg = await (await fetch(`${B3}/api/whatsapp/config`)).json();
    assert.equal(cfg.appId, '111'); assert.equal(cfg.configId, '222');
    const pj3 = (body) => fetch(`${B3}/api/whatsapp/coexistencia`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal((await pj3({ waba_id: 'abc' })).status, 400);
    assert.equal((await pj3({})).status, 400);
    process.env.WHATSAPP_TOKEN = 'tok';
    r = await pj3({ event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING<script>', waba_id: '945936821410540' });
    assert.equal(r.status, 200);
    await new Promise((ok) => setTimeout(ok, 30));
    assert.ok(vistos3.some((m) => /Coexistencia conectada \(FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING\): waba=945936821410540/.test(m)));
    assert.match(llam3[0], /\/945936821410540\/phone_numbers/); assert.ok(vistos3.some((m) => /"id":"999"/.test(m)));
    sesion = null; assert.equal((await pj3({ waba_id: '945936821410540' })).status, 401);
    assert.equal((await fetch(`${B3}/api/whatsapp/config`)).status, 401);
  } finally { srv3.close(); }

  console.log('PASS whatsapp-bot: bienvenida, menú, planes, interés, pausa, cotización, humano, reintentos, límites de WhatsApp, HTML seguro, errores, firma y verificación');
})().catch((e) => { console.error(e); process.exitCode = 1; });
