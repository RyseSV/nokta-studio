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
const BotChat = mongoose.models.BotChat || mongoose.model('BotChat', botChatSchema);
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

function crearBot({ addAlert, Alerta, fetchImpl = globalThis.fetch, log = console } = {}) {
  const env = process.env;

  async function enviar(to, payload) {
    if (!env.WHATSAPP_TOKEN || !env.WHATSAPP_PHONE_NUMBER_ID) {
      log.warn('[WHATSAPP] Falta WHATSAPP_TOKEN o WHATSAPP_PHONE_NUMBER_ID; no se envía respuesta');
      return;
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
    const guardar = (cambios) => BotChat.updateOne({ telefono }, { $set: cambios });
    const img = (archivo) => `${base}/public/bot/${archivo}`;

    // "Borrar mis datos" (lo promete /privacidad): se borra al momento, haya
    // pausa o no. Solo queda un aviso SIN el número para Gabriel.
    if (/^borrar mis datos[.!]*$/i.test(escrito)) {
      await BotChat.deleteOne({ telefono });
      if (Alerta) await Alerta.deleteMany({ tipo: 'whatsapp', 'datos.telefono': telefono }).catch(() => {});
      await addAlert('whatsapp', { nombre: 'Un cliente', mensaje: 'Pidió borrar sus datos: ya se borraron del bot y de las alertas. Si recibió avisos suyos en Telegram, bórrelos también.' }).catch(() => {});
      await texto(telefono, 'Listo. ✅ Hemos borrado su número y sus mensajes de nuestro sistema.');
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
        for (const [clave, plan] of Object.entries(PLANES)) {
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
      await enviar(telefono, { type: 'image', image: { link: img('bienvenida.png'), caption: '¡Hola! 👋 Gracias por escribir a *Nokta Studio*.' } });
    } else if (escrito && !esSaludoOMenu(escrito)) {
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

  return { procesar, atender, firmaValida, leerEntrada };
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

function montarWhatsAppBot(app, deps) {
  const bot = crearBot(deps);
  asegurarSuscripcion(deps?.fetchImpl, deps?.log);

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

module.exports = { montarWhatsAppBot, asegurarSuscripcion, crearBot, firmaValida, leerEntrada, PLANES, BotChat, BotMensaje };
