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

const { procesar } = bot.crearBot({ addAlert, Alerta, fetchImpl, log });
const BASE = 'https://nokta.test';
let n = 0;
const msg = (m, nombre = 'Ana') => ({ entry: [{ changes: [{ value: { contacts: [{ wa_id: '50370000000', profile: { name: nombre } }], messages: [{ from: '50370000000', id: `wamid.${++n}`, ...m }] } }] }] });
const texto = (t) => msg({ type: 'text', text: { body: t } });
const toque = (id, title = id) => msg({ type: 'interactive', interactive: { type: id.startsWith('interes_') || id === 'menu' ? 'button_reply' : 'list_reply', [id.startsWith('interes_') || id === 'menu' ? 'button_reply' : 'list_reply']: { id, title } } });
const limpiar = () => { enviados = []; telegram = []; alertas = []; };

(async () => {
  // 1. Primer mensaje → imagen de bienvenida + menú (lista)
  await procesar(texto('Hola, info'), BASE);
  assert.equal(enviados.length, 2);
  assert.equal(enviados[0].type, 'image');
  assert.equal(enviados[0].image.link, `${BASE}/public/bot/bienvenida.png`);
  assert.equal(enviados[0].to, '50370000000');
  assert.equal(enviados[0].auth, 'Bearer tok');
  assert.match(enviados[0].url, /graph\.facebook\.com\/v\d+\.0\/123\/messages$/);
  assert.equal(enviados[1].interactive.type, 'list');
  const filas = enviados[1].interactive.action.sections[0].rows;
  assert.deepEqual(filas.map((r) => r.id), ['planes', 'trabajo', 'cotizar', 'humano']);
  // Límites de WhatsApp: título ≤24, descripción ≤72, botón ≤20
  filas.forEach((r) => { assert.ok(r.title.length <= 24, r.title); assert.ok(r.description.length <= 72); });
  assert.ok(enviados[1].interactive.action.button.length <= 20);
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

  // ── Rutas HTTP reales ──────────────────────────────────────
  const app = express();
  bot.montarWhatsAppBot(app, { addAlert });
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

  console.log('PASS whatsapp-bot: bienvenida, menú, planes, interés, pausa, cotización, humano, reintentos, límites de WhatsApp, HTML seguro, errores, firma y verificación');
})().catch((e) => { console.error(e); process.exitCode = 1; });
