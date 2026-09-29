// ── Bot de WhatsApp (menú, sin IA) ──────────────────────────
// Meta llama a POST /webhook/whatsapp cada vez que un cliente escribe al
// número del bot. El bot contesta con el menú y los planes, y cuando alguien
// quiere hablar con Gabriel crea una alerta en Nokta (+ aviso por Telegram).
//
// Todo se apaga solo si faltan las variables de entorno: sin
// WHATSAPP_APP_SECRET no se acepta ningún mensaje (no hay forma de saber si
// viene de Meta), y sin WHATSAPP_TOKEN no se puede responder.
//
// Variables (Render → Environment):
//   WHATSAPP_TOKEN            token permanente del usuario del sistema
//   WHATSAPP_PHONE_NUMBER_ID  id del número (no es secreto)
//   WHATSAPP_VERIFY_TOKEN     palabra inventada, igual que en Meta → Webhooks
//   WHATSAPP_APP_SECRET       "Clave secreta" de la app Nokta Bot
//   TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID   (opcional) aviso al móvil
//   PUBLIC_BASE_URL           (opcional) https://nokta-studio.onrender.com
const express = require('express');
const crypto = require('crypto');
const mongoose = require('mongoose');

const GRAPH_VERSION = process.env.WHATSAPP_GRAPH_VERSION || 'v25.0';
const INSTAGRAM = 'https://instagram.com/nokta.studiosv';
const TELEGRAM_CADA_MS = 60 * 1000;            // máx. 1 aviso al móvil por cliente/minuto
const PAUSA_HUMANO_MS = 12 * 3600 * 1000;   // Gabriel atiende; el bot calla
const BIENVENIDA_CADA_MS = 24 * 3600 * 1000; // imagen de bienvenida 1 vez/día

const PLANES = {
  inicio: {
    nombre: 'Inicio', precio: 150, imagen: 'plan-inicio.png',
    texto: '*Plan Inicio · $150 al mes*\nEl primer paso para su marca: contenido mensual diseñado y publicado en Facebook e Instagram. ✨',
  },
  presencia: {
    nombre: 'Presencia', precio: 250, imagen: 'plan-presencia.png',
    texto: '*Plan Presencia · $250 al mes*\nContenido constante, con fotos y reels de su negocio, para que su marca siempre se vea. 📸',
  },
  impulso: {
    nombre: 'Impulso', precio: 350, imagen: 'plan-impulso.png',
    texto: '*Plan Impulso · $350 al mes*\nContenido + publicidad en Facebook e Instagram, con seguimiento y reporte mensual. 🚀\n_La inversión en anuncios se paga aparte, directo a Meta._',
  },
};

// ── Estado por cliente (en Mongo: el servidor gratuito se duerme y pierde la memoria)
const botChatSchema = new mongoose.Schema({
  telefono: { type: String, unique: true },
  nombre: String,
  paso: String,          // null | 'cotizar'
  pausaHasta: Date,      // mientras esté en el futuro, el bot no contesta
  ultimaBienvenida: Date,
  ultimoTelegram: Date,
  actualizado: Date,
});
// Meta reintenta el mismo mensaje si el servidor tardó en despertar: se
// guarda el id de cada mensaje para no contestar dos veces.
const botMensajeSchema = new mongoose.Schema({
  _id: String,
  creado: { type: Date, default: Date.now, expires: 7 * 24 * 3600 },
});
// Historial para la bandeja de WhatsApp de Nokta (lo que escribe el cliente,
// lo que contesta el bot y lo que contesta Gabriel desde la app).
const waMensajeSchema = new mongoose.Schema({
  telefono: { type: String, index: true },
  nombre: String,
  autor: String,         // 'cliente' | 'bot' | 'gabriel'
  quien: String,         // usuario de Nokta que respondió (autor 'gabriel')
  texto: String,
  tipo: String,          // text, interactive, image, audio…
  leido: Boolean,        // solo mensajes del cliente
  fecha: { type: Date, default: Date.now, index: true },
});
waMensajeSchema.index({ telefono: 1, fecha: -1 });
const BotChat = mongoose.models.BotChat || mongoose.model('BotChat', botChatSchema);
const WaMensaje = mongoose.models.WaMensaje || mongoose.model('WaMensaje', waMensajeSchema);
const TIPOS_MEDIA = { image: '📷 Imagen', audio: '🎤 Audio', video: '🎬 Video', document: '📄 Documento', sticker: 'Sticker', location: '📍 Ubicación', contacts: '👤 Contacto' };

// Resumen legible de lo que se envió, para el historial.
function resumenEnvio(p) {
  if (p.type === 'text') return p.text.body;
  if (p.type === 'image') return `📷 ${p.image.caption || 'Imagen'}`;
  const i = p.interactive || {};
  const cuerpo = i.body?.text || '';
  if (i.type === 'button') return `${i.header?.image ? '📷 ' : ''}${cuerpo}\n[${i.action.buttons.map((b) => b.reply.title).join(' · ')}]`;
  if (i.type === 'list') return `${cuerpo}\n[Menú: ${i.action.sections.flatMap((x) => x.rows.map((r) => r.title)).join(' · ')}]`;
  return cuerpo || p.type;
}
async function registrar(doc, log = console) {
  try { await WaMensaje.create({ fecha: new Date(), ...doc }); }
  catch (e) { log.error('[WHATSAPP] No se pudo guardar el mensaje en el historial:', e.message); }
}
const BotMensaje = mongoose.models.BotMensaje || mongoose.model('BotMensaje', botMensajeSchema);

function firmaValida(rawBody, firma, secreto) {
  if (!secreto || !firma || !Buffer.isBuffer(rawBody)) return false;
  const esperada = 'sha256=' + crypto.createHmac('sha256', secreto).update(rawBody).digest('hex');
  const a = Buffer.from(firma), b = Buffer.from(esperada);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Lo que el cliente eligió o escribió, normalizado a { id, texto }.
function leerEntrada(m) {
  if (m.type === 'interactive') {
    const r = m.interactive?.button_reply || m.interactive?.list_reply;
    return { id: r?.id || null, texto: r?.title || '' };
  }
  if (m.type === 'button') return { id: m.button?.payload || null, texto: m.button?.text || '' };
  if (m.type === 'text') return { id: null, texto: String(m.text?.body || '').trim() };
  return { id: null, texto: '', otroTipo: m.type };
}

// Sin \b: no funciona tras letras con tilde ("menú").
const esSaludoOMenu = (t) => /^(hola|buenas|buenos|buen día|menu|menú|inicio|opciones|empezar)(?=$|[\s,.!?¡¿])/i.test(t.normalize('NFC'));

// Cada mensaje con imagen tarda distinto en llegar: se espera un poco entre
// tarjetas para que el cliente las reciba en orden.
function crearBot({ addAlert, Alerta, fetchImpl = globalThis.fetch, log = console, pausaEntreTarjetasMs = 1500 } = {}) {
  const esperar = (ms) => new Promise((r) => setTimeout(r, ms));
  const env = process.env;

  async function enviar(to, payload, autor = 'bot', quien) {
    if (!env.WHATSAPP_TOKEN || !env.WHATSAPP_PHONE_NUMBER_ID) {
      log.warn('[WHATSAPP] Falta WHATSAPP_TOKEN o WHATSAPP_PHONE_NUMBER_ID; no se envía respuesta');
      throw new Error('El bot de WhatsApp no está configurado');
    }
    const res = await fetchImpl(`https://graph.facebook.com/${GRAPH_VERSION}/${env.WHATSAPP_PHONE_NUMBER_ID}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.WHATSAPP_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', recipient_type: 'individual', to, ...payload }),
    });
    if (!res.ok) {
      // Nunca se registra el token: solo el código y el mensaje de error de Meta.
      const cuerpo = await res.text().catch(() => '');
      throw new Error(`WhatsApp API ${res.status}: ${cuerpo.slice(0, 300)}`);
    }
    if (autor) await registrar({ telefono: to, autor, ...(quien ? { quien } : {}), texto: resumenEnvio(payload), tipo: payload.type }, log);
  }

  const texto = (to, body) => enviar(to, { type: 'text', text: { body, preview_url: true } });
  const botones = (to, body, lista, imagen) => enviar(to, {
    type: 'interactive',
    interactive: {
      type: 'button',
      ...(imagen ? { header: { type: 'image', image: { link: imagen } } } : {}),
      body: { text: body },
      action: { buttons: lista.map(([id, title]) => ({ type: 'reply', reply: { id, title } })) },
    },
  });

  function menu(to) {
    return enviar(to, {
      type: 'interactive',
      interactive: {
        type: 'list',
        body: { text: '¿En qué le podemos ayudar? Toque *Ver opciones* 👇' },
        action: {
          button: 'Ver opciones',
          sections: [{
            title: 'Nokta Studio',
            rows: [
              { id: 'planes', title: 'Planes mensuales', description: 'Inicio, Presencia e Impulso' },
              { id: 'trabajo', title: 'Ver nuestro trabajo', description: 'Instagram @nokta.studiosv' },
              { id: 'cotizar', title: 'Pedir cotización', description: 'Cuéntenos qué necesita' },
              { id: 'humano', title: 'Hablar con Gabriel', description: 'Le responde en persona' },
            ],
          }],
        },
      },
    });
  }

  async function avisar(chat, mensaje) {
    const telefono = chat.telefono;
    const nombre = chat.nombre || 'Cliente';
    mensaje = String(mensaje).slice(0, 1000);
    // Una sola alerta sin leer por cliente: si escribe varias veces, se van
    // sumando sus mensajes en la misma (no se llena la lista de alertas).
    try {
      const previa = Alerta && await Alerta.findOne({ tipo: 'whatsapp', 'datos.telefono': telefono, leida: false }).lean();
      if (previa) {
        const juntos = `${previa.datos?.mensaje || ''}\n${mensaje}`.slice(-1500);
        await Alerta.updateOne({ id: previa.id }, { $set: { 'datos.mensaje': juntos, 'datos.nombre': nombre, fecha: new Date().toISOString() } });
      } else {
        await addAlert('whatsapp', { nombre, telefono, mensaje });
      }
    } catch (e) { log.error('[WHATSAPP] No se pudo crear la alerta:', e.message); }
    const reciente = chat.ultimoTelegram && Date.now() - new Date(chat.ultimoTelegram) < TELEGRAM_CADA_MS;
    if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID && !reciente) {
      await BotChat.updateOne({ telefono }, { $set: { ultimoTelegram: new Date() } }).catch(() => {});
      const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
      try {
        const res = await fetchImpl(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chat_id: env.TELEGRAM_CHAT_ID,
            parse_mode: 'HTML',
            text: `💬 <b>${esc(nombre)}</b> (WhatsApp)\n${esc(mensaje)}\n\nResponder: https://wa.me/${esc(telefono)}`,
          }),
        });
        if (!res.ok) log.error('[WHATSAPP] Telegram respondió', res.status);
      } catch (e) { log.error('[WHATSAPP] No se pudo avisar por Telegram:', e.message); }
    }
  }

  async function atender(m, perfil, base) {
    const telefono = String(m.from || '');
    if (!telefono || !m.id) return;
    // Ya procesado (Meta reintentó) → no contestar otra vez.
    try { await BotMensaje.create({ _id: m.id }); }
    catch (e) { if (e.code === 11000) return; throw e; }

    const ahora = new Date();
    const chat = await BotChat.findOneAndUpdate(
      { telefono },
      { $set: { actualizado: ahora, ...(perfil ? { nombre: perfil } : {}) } },
      { upsert: true, returnDocument: 'after' },
    );
    const { id, texto: escrito, otroTipo } = leerEntrada(m);
    const caption = m[m.type]?.caption;
    await registrar({
      telefono, nombre: perfil || chat.nombre, autor: 'cliente', tipo: m.type, leido: false,
      texto: escrito || [TIPOS_MEDIA[otroTipo] || `[${otroTipo}]`, caption].filter(Boolean).join(': '),
    }, log);
    const guardar = (cambios) => BotChat.updateOne({ telefono }, { $set: cambios });
    const img = (archivo) => `${base}/public/bot/${archivo}`;

    // "Borrar mis datos" (lo promete /privacidad): se borra al momento, haya
    // pausa o no. Solo queda un aviso SIN el número para Gabriel.
    if (/^borrar mis datos[.!]*$/i.test(escrito.replace(/["“”'‘’«»]/g, '').trim())) {
      await BotChat.deleteOne({ telefono });
      await WaMensaje.deleteMany({ telefono });
      if (Alerta) await Alerta.deleteMany({ tipo: 'whatsapp', 'datos.telefono': telefono }).catch(() => {});
      await addAlert('whatsapp', { nombre: 'Un cliente', mensaje: 'Pidió borrar sus datos: ya se borraron del bot y de las alertas. Si recibió avisos suyos en Telegram, bórrelos también.' }).catch(() => {});
      // autor null: esta confirmación no se guarda (acabamos de borrar su historial)
      await enviar(telefono, { type: 'text', text: { body: 'Listo. ✅ Hemos borrado su número y sus mensajes de nuestro sistema.' } }, null);
      return;
    }

    // En pausa: Gabriel está atendiendo. Se le reenvía lo que escriba el
    // cliente, salvo que pida el menú explícitamente.
    const pideMenu = id === 'menu' || /^(menu|menú)$/i.test(escrito);
    if (chat.pausaHasta && chat.pausaHasta > ahora && !pideMenu) {
      await avisar(chat, escrito || `Envió un ${otroTipo || 'mensaje'} (ábralo en WhatsApp)`);
      return;
    }

    if (chat.paso === 'cotizar' && !id) {
      if (!escrito) {
        await texto(telefono, 'Por ahora solo puedo leer texto. ¿Me lo escribe en un mensaje, por favor? 🙏');
        return;
      }
      await guardar({ paso: null, pausaHasta: new Date(ahora.getTime() + PAUSA_HUMANO_MS) });
      await avisar(chat, `Pide cotización: ${escrito}`);
      await texto(telefono, '¡Gracias! 🙌 Gabriel revisa su solicitud y le responde en breve con su cotización.');
      return;
    }

    if (id && id.startsWith('interes_') && PLANES[id.slice(8)]) {
      const plan = PLANES[id.slice(8)];
      await guardar({ paso: null, pausaHasta: new Date(ahora.getTime() + PAUSA_HUMANO_MS) });
      await avisar(chat, `Le interesa el plan ${plan.nombre} ($${plan.precio}/mes)`);
      await texto(telefono, `¡Excelente elección! 🙌 Gabriel le escribe en breve para conocer su negocio y arrancar con el plan ${plan.nombre}.`);
      return;
    }

    // Tocó una opción: se abandona cualquier paso a medias (p. ej. cotizar).
    if (id && chat.paso) await guardar({ paso: null });

    switch (id) {
      case 'planes':
        for (const [i, [clave, plan]] of Object.entries(PLANES).entries()) {
          if (i > 0) await esperar(pausaEntreTarjetasMs);
          await botones(telefono, plan.texto, [[`interes_${clave}`, 'Me interesa'], ['menu', 'Ver menú']], img(plan.imagen));
        }
        return;
      case 'trabajo':
        await texto(telefono, `Puede ver nuestro trabajo en Instagram 👉 ${INSTAGRAM}`);
        return;
      case 'cotizar':
        await guardar({ paso: 'cotizar' });
        await texto(telefono, 'Con gusto. 📝 Cuéntenos en un mensaje sobre su negocio y qué necesita.');
        return;
      case 'humano':
        await guardar({ paso: null, pausaHasta: new Date(ahora.getTime() + PAUSA_HUMANO_MS) });
        await avisar(chat, 'Quiere hablar con usted');
        await texto(telefono, 'Con gusto. 🙌 Gabriel le responde personalmente en breve.');
        return;
      case 'menu':
        await guardar({ paso: null, pausaHasta: null });
        await menu(telefono);
        return;
    }

    // Cualquier otra cosa (primer mensaje, "hola", texto libre): bienvenida + menú.
    const tocaBienvenida = !chat.ultimaBienvenida || ahora - chat.ultimaBienvenida > BIENVENIDA_CADA_MS;
    await guardar({ paso: null, pausaHasta: null, ...(tocaBienvenida ? { ultimaBienvenida: ahora } : {}) });
    if (tocaBienvenida) {
      // Imagen + saludo + botones en UN mensaje: así nunca llegan desordenados.
      await botones(telefono,
        `¡Hola! 👋 Gracias por escribir a *Nokta Studio*.\n¿En qué le podemos ayudar?\n\n📸 Nuestro trabajo: ${INSTAGRAM}`,
        [['planes', 'Ver planes'], ['cotizar', 'Pedir cotización'], ['humano', 'Hablar con Gabriel']],
        img('bienvenida.png'));
      return;
    }
    if (escrito && !esSaludoOMenu(escrito)) {
      await texto(telefono, 'Disculpe, no entendí su mensaje. 🙏');
    }
    await menu(telefono);
  }

  async function procesar(body, base) {
    for (const entry of body?.entry || []) {
      for (const change of entry.changes || []) {
        const value = change.value || {};
        const perfiles = Object.fromEntries((value.contacts || []).map((c) => [c.wa_id, c.profile?.name]));
        for (const m of value.messages || []) {
          try { await atender(m, perfiles[m.from], base); }
          catch (e) {
            log.error('[WHATSAPP] Error atendiendo mensaje:', e.message);
            // Que un cliente no se pierda en silencio (token caducado, Mongo dormido…)
            if (m.from) {
              const tel = String(m.from);
              const chat = await BotChat.findOne({ telefono: tel }).lean().catch(() => null);
              await avisar(chat || { telefono: tel, nombre: perfiles[m.from] }, 'El bot no pudo responderle. Escríbale usted.').catch(() => {});
            }
          }
        }
      }
    }
  }

  return { procesar, atender, enviar, firmaValida, leerEntrada };
}

// La cuenta de WhatsApp (WABA) tiene que estar suscrita a la app para que
// Meta entregue los mensajes reales (la prueba del panel funciona aunque no
// lo esté). Se asegura al arrancar; es idempotente y deja el resultado en el log.
async function asegurarSuscripcion(fetchImpl = globalThis.fetch, log = console) {
  const { WHATSAPP_TOKEN: token, WHATSAPP_WABA_ID: waba = '2075908746368446' } = process.env;
  if (!token) return;
  try {
    const res = await fetchImpl(`https://graph.facebook.com/${GRAPH_VERSION}/${waba}/subscribed_apps`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}` },
    });
    const cuerpo = await res.text().catch(() => '');
    if (res.ok) log.log('[WHATSAPP] Cuenta de WhatsApp suscrita a la app ✓');
    else log.error(`[WHATSAPP] No se pudo suscribir la cuenta (${res.status}): ${cuerpo.slice(0, 300)}`);
  } catch (e) { log.error('[WHATSAPP] No se pudo suscribir la cuenta:', e.message); }
}

// Soltar un número de la API para poder volver a usarlo en la app de WhatsApp
// del móvil: se pone su id en WHATSAPP_DESREGISTRAR y al arrancar se
// desregistra una vez (el resultado queda en el log). Reversible: el número se
// puede volver a registrar en Meta cuando se quiera.
async function desregistrarNumero(fetchImpl = globalThis.fetch, log = console) {
  const { WHATSAPP_TOKEN: token, WHATSAPP_DESREGISTRAR: id } = process.env;
  if (!token || !/^\d+$/.test(id || '')) return;
  try {
    const res = await fetchImpl(`https://graph.facebook.com/${GRAPH_VERSION}/${id}/deregister`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}` },
    });
    const cuerpo = await res.text().catch(() => '');
    if (res.ok) log.log(`[WHATSAPP] Número ${id} desconectado de la API ✓ (ya se puede usar en la app del móvil)`);
    else log.error(`[WHATSAPP] No se pudo desconectar el número ${id} (${res.status}): ${cuerpo.slice(0, 300)}`);
  } catch (e) { log.error('[WHATSAPP] No se pudo desconectar el número:', e.message); }
}

let botCompartido = null;

function montarWhatsAppBot(app, deps) {
  const bot = botCompartido = crearBot(deps);
  asegurarSuscripcion(deps?.fetchImpl, deps?.log);
  desregistrarNumero(deps?.fetchImpl, deps?.log);

  // Meta comprueba la dirección una sola vez al guardar el webhook.
  app.get('/webhook/whatsapp', (req, res) => {
    const verify = process.env.WHATSAPP_VERIFY_TOKEN;
    if (verify && req.query['hub.mode'] === 'subscribe' && req.query['hub.verify_token'] === verify) {
      return res.type('text/plain').send(String(req.query['hub.challenge'] || ''));
    }
    res.sendStatus(403);
  });

  // express.raw: la firma de Meta se calcula sobre el cuerpo exacto, por eso
  // esta ruta se monta antes del express.json() global.
  app.post('/webhook/whatsapp', express.raw({ type: '*/*', limit: '1mb' }), (req, res) => {
    if (!firmaValida(req.body, req.get('x-hub-signature-256'), process.env.WHATSAPP_APP_SECRET)) {
      console.warn(`[SEGURIDAD] Webhook de WhatsApp con firma inválida | ip=${req.ip}`);
      return res.sendStatus(401);
    }
    let body;
    try { body = JSON.parse(req.body.toString('utf8')); } catch { return res.sendStatus(400); }
    // Responder ya: si Meta no recibe el 200 rápido, reintenta.
    res.sendStatus(200);
    const base = (process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`).replace(/\/$/, '');
    bot.procesar(body, base).catch((e) => console.error('[WHATSAPP]', e.message));
  });
}

// ── Bandeja de WhatsApp en Nokta (panel web + app) ──────────
// Se monta después de la sesión (requireAdmin la necesita) y del express.json global.
const VENTANA_MS = 24 * 3600 * 1000; // Meta: respuestas libres (y gratis) hasta 24 h después del último mensaje del cliente
const telValido = (t) => /^\d{6,16}$/.test(String(t || ''));

function montarBandejaWhatsApp(app, { requireAdmin, bot = null, log = console }) {
  const obtenerBot = () => bot || botCompartido;

  async function estadoChat(telefono) {
    const [chat, ultimoCliente] = await Promise.all([
      BotChat.findOne({ telefono }).lean(),
      WaMensaje.findOne({ telefono, autor: 'cliente' }).sort({ fecha: -1 }).lean(),
    ]);
    const ahora = Date.now();
    const cierra = ultimoCliente ? new Date(ultimoCliente.fecha).getTime() + VENTANA_MS : 0;
    return {
      botPausado: !!(chat?.pausaHasta && new Date(chat.pausaHasta).getTime() > ahora),
      pausaHasta: chat?.pausaHasta || null,
      ventanaAbierta: cierra > ahora,
      ventanaCierra: cierra ? new Date(cierra).toISOString() : null,
    };
  }

  // Lista de conversaciones, la más reciente primero.
  app.get('/api/whatsapp/chats', requireAdmin, async (req, res) => {
    try {
      // Un resumen por chat, calculado en Mongo (no se traen los mensajes).
      const esCliente = { $eq: ['$autor', 'cliente'] };
      const chats = (await WaMensaje.aggregate([
        { $sort: { fecha: -1 } },
        { $group: {
          _id: '$telefono',
          ultimo: { $first: '$texto' }, autorUltimo: { $first: '$autor' }, fecha: { $first: '$fecha' },
          nombre: { $max: { $cond: [esCliente, '$nombre', null] } },
          ultimoCliente: { $max: { $cond: [esCliente, '$fecha', null] } },
          noLeidos: { $sum: { $cond: [{ $and: [esCliente, { $eq: ['$leido', false] }] }, 1, 0] } },
        } },
        { $sort: { fecha: -1 } },
        { $limit: 500 },
      ])).map(({ _id, ...c }) => ({ telefono: _id, ...c }));
      const pausas = await BotChat.find({ telefono: { $in: chats.map((c) => c.telefono) } }, 'telefono pausaHasta nombre').lean();
      const ahora = Date.now();
      for (const c of chats) {
        const b = pausas.find((x) => x.telefono === c.telefono);
        if (!c.nombre) c.nombre = b?.nombre || null;
        c.botPausado = !!(b?.pausaHasta && new Date(b.pausaHasta).getTime() > ahora);
        c.ventanaAbierta = !!(c.ultimoCliente && new Date(c.ultimoCliente).getTime() + VENTANA_MS > ahora);
        delete c.ultimoCliente;
      }
      res.json({ chats, noLeidos: chats.reduce((n, c) => n + c.noLeidos, 0) });
    } catch (e) { log.error('[WHATSAPP] bandeja:', e.message); res.status(500).json({ error: 'No se pudieron cargar los chats' }); }
  });

  // Una conversación (y se marca como leída).
  app.get('/api/whatsapp/chats/:telefono', requireAdmin, async (req, res) => {
    const { telefono } = req.params;
    if (!telValido(telefono)) return res.status(400).json({ error: 'Número inválido' });
    try {
      const ultimos = await WaMensaje.find({ telefono }).sort({ fecha: -1 }).limit(300).lean();
      await WaMensaje.updateMany({ telefono, autor: 'cliente', leido: false }, { $set: { leido: true } });
      const nombre = ultimos.find((m) => m.autor === 'cliente' && m.nombre)?.nombre || null;
      res.json({
        telefono, nombre, ...(await estadoChat(telefono)),
        mensajes: ultimos.reverse().map(({ _id, autor, quien, texto, tipo, fecha }) => ({ id: String(_id), autor, quien, texto, tipo, fecha })),
      });
    } catch (e) { log.error('[WHATSAPP] chat:', e.message); res.status(500).json({ error: 'No se pudo cargar la conversación' }); }
  });

  // Gabriel responde desde Nokta con el número de Nokta. El bot se pausa
  // para no hablar a la vez que él.
  app.post('/api/whatsapp/chats/:telefono/enviar', requireAdmin, async (req, res) => {
    const { telefono } = req.params;
    const texto = typeof req.body?.texto === 'string' ? req.body.texto.trim() : '';
    if (!telValido(telefono)) return res.status(400).json({ error: 'Número inválido' });
    if (!texto) return res.status(400).json({ error: 'Escribe un mensaje' });
    if (texto.length > 4096) return res.status(400).json({ error: 'El mensaje es demasiado largo (máx. 4096 caracteres)' });
    const b = obtenerBot();
    if (!b) return res.status(503).json({ error: 'El bot de WhatsApp no está activo' });
    try {
      const estado = await estadoChat(telefono);
      if (!estado.ventanaAbierta) {
        return res.status(409).json({ error: 'Pasaron más de 24 horas desde el último mensaje de este cliente. WhatsApp solo permite responder gratis dentro de ese plazo: pídale que le escriba de nuevo.' });
      }
      await b.enviar(telefono, { type: 'text', text: { body: texto, preview_url: true } }, 'gabriel', req.authUser?.nombre || req.authUser?.username);
      await BotChat.updateOne({ telefono }, { $set: { pausaHasta: new Date(Date.now() + PAUSA_HUMANO_MS), paso: null } }, { upsert: true });
      res.json({ ok: true });
    } catch (e) {
      log.error('[WHATSAPP] enviar desde bandeja:', e.message);
      res.status(502).json({ error: 'WhatsApp no aceptó el mensaje. Inténtelo de nuevo en un momento.' });
    }
  });

  // Encender o apagar el bot para un cliente.
  app.post('/api/whatsapp/chats/:telefono/bot', requireAdmin, async (req, res) => {
    const { telefono } = req.params;
    if (!telValido(telefono)) return res.status(400).json({ error: 'Número inválido' });
    if (typeof req.body?.activo !== 'boolean') return res.status(400).json({ error: 'Falta "activo"' });
    try {
      const pausaHasta = req.body.activo ? null : new Date(Date.now() + PAUSA_HUMANO_MS);
      await BotChat.updateOne({ telefono }, { $set: { pausaHasta, paso: null } }, { upsert: true });
      res.json({ ok: true, ...(await estadoChat(telefono)) });
    } catch (e) { log.error('[WHATSAPP] bot on/off:', e.message); res.status(500).json({ error: 'No se pudo cambiar el bot' }); }
  });
}

module.exports = { montarWhatsAppBot, montarBandejaWhatsApp, asegurarSuscripcion, desregistrarNumero, crearBot, WaMensaje, resumenEnvio, firmaValida, leerEntrada, PLANES, BotChat, BotMensaje };
