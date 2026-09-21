require('dotenv').config();
const express = require('express');
const session = require('express-session');
const MongoStore = require('connect-mongo').default || require('connect-mongo');
const mongoose = require('mongoose');
const cloudinary = require('cloudinary').v2;
const bcrypt = require('bcryptjs');
const path = require('path');
const os = require('os');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});
console.log('Cloudinary config:', {
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || '(no configurado)',
  api_key: process.env.CLOUDINARY_API_KEY ? '✓ set' : '(no configurado)',
  api_secret: process.env.CLOUDINARY_API_SECRET ? '✓ set' : '(no configurado)',
});

// ── Mongoose schemas ────────────────────────────────────────
const clienteSchema = new mongoose.Schema({
  codigo: { type: String, unique: true },
  nombre: String, tipo: String, whatsapp: String,
  dias: Number, creado: String, expira: String, estado: String,
  visitas: [String], descargas: [Object], favoritos: [String],
  reactivaciones: [Object]
}, { strict: false });

const usuarioSchema = new mongoose.Schema({
  username: { type: String, unique: true },
  nombre: String,
  password: String,
  role: { type: String, default: 'editor' },
  creado: String,
}, { strict: false });
const Usuario = mongoose.model('Usuario', usuarioSchema);

// ── Seed admin user on first run ─────────────────────────────
async function seedAdmin() {
  const exists = await Usuario.findOne({ role: 'admin' });
  if (!exists) {
    let password = process.env.ADMIN_PASSWORD;
    if (!password) {
      password = crypto.randomBytes(9).toString('base64url');
      console.warn(`  ⚠️  ADMIN_PASSWORD no configurado. Se generó una contraseña temporal para "admin": ${password}`);
      console.warn('  ⚠️  Guárdala y define ADMIN_PASSWORD en las variables de entorno cuanto antes.');
    }
    const hash = await bcrypt.hash(password, 10);
    await Usuario.create({ username: 'admin', nombre: 'Administrador', password: hash, role: 'admin', creado: new Date().toISOString() });
    console.log('  Admin user creado ✓');
  }
}

const trabajoSchema = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const gastoSchema   = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const cotSchema     = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const reciboSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const contratoSchema = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const alertaSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const equipoSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const eventoSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
// Relación comercial por cliente (activo / pausado / cancelado). Independiente
// del Cliente de galerías: un cliente financiero (agrupado por nombre desde
// Trabajo.cliente) no siempre tiene una galería asociada.
const clienteEstadoSchema = new mongoose.Schema({ nombre: { type: String, unique: true } }, { strict: false });

const Cliente       = mongoose.model('Cliente',       clienteSchema);
const Trabajo       = mongoose.model('Trabajo',       trabajoSchema);
const Gasto         = mongoose.model('Gasto',         gastoSchema);
const Cotizacion    = mongoose.model('Cotizacion',    cotSchema);
const Recibo        = mongoose.model('Recibo',        reciboSchema);
const Contrato      = mongoose.model('Contrato',      contratoSchema);
const Alerta        = mongoose.model('Alerta',        alertaSchema);
const Equipo        = mongoose.model('Equipo',        equipoSchema);
const Evento        = mongoose.model('Evento',        eventoSchema);
const ClienteEstado = mongoose.model('ClienteEstado', clienteEstadoSchema);

// ── Connect MongoDB ─────────────────────────────────────────
mongoose.connect(process.env.MONGODB_URI)
  .then(async () => { console.log('  MongoDB conectado ✓'); await seedAdmin(); })
  .catch(err => { console.error('MongoDB error:', err); process.exit(1); });

// ── Express setup ───────────────────────────────────────────
const app = express();
// Render terminates TLS and proxies over HTTP internally — without this,
// a `secure` session cookie would never actually get set in production.
app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use('/img', express.static(path.join(__dirname, '../img')));
app.use('/public', express.static(path.join(__dirname, 'public')));

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: { error: 'Demasiados intentos. Espera 15 minutos.' },
  skipSuccessfulRequests: true,
});

// Public gallery routes have no login — this is the only thing standing
// between them and being hammered to enumerate codes or run up Cloudinary
// zip-download costs.
const galeriaLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 120,
  message: { error: 'Demasiadas solicitudes. Intenta de nuevo en unos minutos.' },
});

// Every route below does `catch (err) { ... }` around a DB call — this
// keeps the response generic instead of leaking raw Mongo/Mongoose error
// text (field names, duplicate-key details, etc.) to whoever's asking.
function handleError(res, err) {
  console.error(err);
  res.status(500).json({ error: 'Ocurrió un error interno. Intenta de nuevo.' });
}

// These "strict:false" schemas were designed to accept whatever fields the
// web form for that record's group sends — but that also meant `...req.body`
// would happily write ANY key a caller sent (e.g. `role`, `estado`, or a
// Mongo operator-shaped key) straight into the document. Whitelisting to
// the fields each form actually uses closes that off without touching the
// flexible-schema design.
function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (obj[k] !== undefined) out[k] = obj[k];
  return out;
}
const TRABAJO_FIELDS = [
  'cliente', 'clienteId', 'servicio', 'grupo', 'grupoNombre', 'notas', 'estado',
  'fecha', 'horaInicio', 'horaFin', 'lugar', 'monto', 'anticipo', 'saldo',
  'empresa', 'pagoMensual', 'fechaInicio', 'diaCobro', 'estadoContrato',
  'cantPiezas', 'formato', 'alcance', 'fechaEntrega',
];
const GASTO_FIELDS = ['concepto', 'categoria', 'monto', 'fecha'];
const EQUIPO_FIELDS = ['nombre', 'rol', 'tipo', 'comision', 'pagado', 'pendiente'];
const DOCUMENTO_FIELDS = ['clienteNombre', 'empresa', 'telefono', 'email', 'fechaEmision', 'fechaValidez', 'servicios', 'total', 'notas'];
const CONTRATO_FIELDS = [
  'trabajoId', 'ciudad', 'fechaContrato', 'clienteNombre', 'clienteDui', 'clienteTelefono',
  'clienteEmail', 'clienteDireccion', 'servicioTipo', 'servicioFecha', 'servicioLugar',
  'entregables', 'anticipoMonto', 'anticipoFecha', 'saldoMonto', 'saldoFecha', 'plazoDias', 'mora',
];
const EVENTO_FIELDS = ['titulo', 'tipo', 'fecha', 'horaInicio', 'horaFin', 'lugar', 'monto', 'anticipo', 'saldo'];
let sessionSecret = process.env.SESSION_SECRET;
if (!sessionSecret) {
  sessionSecret = crypto.randomBytes(32).toString('hex');
  console.warn('  ⚠️  SESSION_SECRET no configurado. Se generó uno aleatorio para este arranque');
  console.warn('  ⚠️  (esto cierra la sesión de todos al reiniciar el server) — define SESSION_SECRET en las variables de entorno.');
}
app.use(session({
  secret: sessionSecret,
  resave: false,
  saveUninitialized: false,
  store: MongoStore.create({ mongoUrl: process.env.MONGODB_URI }),
  cookie: {
    maxAge: null,  // session cookie — expires when browser closes
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
  }
}));

// ── Auth middleware ─────────────────────────────────────────
function requireAdmin(req, res, next) {
  if (req.session.userId) return next();
  res.status(401).json({ error: 'No autorizado' });
}
function requireSuperAdmin(req, res, next) {
  if (req.session.role === 'admin') return next();
  res.status(403).json({ error: 'Acceso denegado' });
}

// ── Generate client code ────────────────────────────────────
async function generateCode(tipo) {
  const year = new Date().getFullYear();
  const map = { boda:'BD', xvanios:'XV', corporativo:'CO', deportivo:'DP', graduacion:'GR', otro:'EV' };
  const prefix = map[tipo] || 'EV';
  const count = await Cliente.countDocuments({ codigo: new RegExp(`NK-${year}-${prefix}-`) });
  // A random suffix (not just a sequential number) keeps gallery links from
  // being guessable — otherwise anyone could enumerate NK-2026-BD-0001,
  // -0002, -0003... and view/download a stranger's private photos.
  const suffix = crypto.randomBytes(4).toString('hex');
  return `NK-${year}-${prefix}-${String(count + 1).padStart(4, '0')}-${suffix}`;
}

// `new Date('YYYY-MM-DD')` parses as UTC midnight, which rolls back a day
// (and, at day 1, a whole month) in negative-UTC timezones like El Salvador
// — parse the "YYYY-MM" text directly instead, same fix already applied to
// admin.html's mesAnioDeFecha/_generarPeriodos.
function anioMesDeFecha(f) {
  if (!f || f.length < 7) return null;
  const anio = parseInt(f.slice(0, 4), 10), mes = parseInt(f.slice(5, 7), 10);
  if (!anio || !mes) return null;
  return { anio, mes: mes - 1 };
}

// ── Auto-generate alerts ────────────────────────────────────
async function addAlert(tipo, datos) {
  const id = `a${Date.now()}${Math.random().toString(36).slice(2,6)}`;
  await Alerta.create({ id, tipo, datos, fecha: new Date().toISOString(), leida: false });
}

async function checkAlerts() {
  const now = new Date();

  // Estado real de la relación por nombre de cliente (activo/pausado/cancelado) —
  // usado para congelar la generación de quincenas de contratos pausados/cancelados,
  // igual que _generarPeriodos en admin.html (misma fuente de verdad en ambos lados).
  const estadosCliente = await ClienteEstado.find({}).lean();
  const estadoClienteDe = (nombre) => estadosCliente.find(e => e.nombre === nombre)?.estado || 'activo';

  // One query for every alert that already exists, instead of one
  // Alerta.findOne() per candidate item below (a grupo B contract alone can
  // check up to ~48 quincena periods) — checked in memory from here on, and
  // kept in sync as addAlert() creates new ones within this same run.
  const alertasExistentes = await Alerta.find({}, 'tipo datos').lean();
  const existeAlerta = (tipo, campo, valor) => alertasExistentes.some(a => a.tipo === tipo && a.datos?.[campo] === valor);
  async function addAlertTracked(tipo, datos) {
    await addAlert(tipo, datos);
    alertasExistentes.push({ tipo, datos });
  }

  // Expiring gallery links (≤ 3 days)
  const clientes = await Cliente.find({});
  for (const c of clientes) {
    if (!c.expira) continue;
    const exp = new Date(c.expira);
    const days = Math.ceil((exp - now) / 86400000);
    if (days <= 3 && days > 0 && c.estado === 'activo') {
      if (!existeAlerta('link_venciendo', 'codigo', c.codigo)) await addAlertTracked('link_venciendo', { nombre: c.nombre, codigo: c.codigo, diasRestantes: days });
    }
    if (exp < now && c.estado === 'activo') {
      await Cliente.updateOne({ codigo: c.codigo }, { $set: { estado: 'expirado' } });
    }
  }

  // Pending payments > 7 days (non-recurrente only)
  const trabajos = await Trabajo.find({});
  for (const t of trabajos) {
    const g = t.grupo || '';
    if (g === 'B') continue; // handled separately below
    if (t.estado !== 'pendiente' || !t.creado) continue;
    const days = Math.ceil((now - new Date(t.creado)) / 86400000);
    if (days >= 7) {
      if (!existeAlerta('pago_pendiente', 'id', t.id)) await addAlertTracked('pago_pendiente', { id: t.id, cliente: t.cliente, servicio: t.servicio, saldo: t.saldo });
    }
  }

  // Quincenas vencidas sin pagar (grupo B — recurrentes)
  for (const t of trabajos) {
    const g = t.grupo || '';
    if (g !== 'B' || !t.fechaInicio) continue;
    // Contrato pausado/cancelado: no generar NINGÚN aviso de "quincena sin
    // pagar" para él — mientras esté en pausa no se le sigue cobrando, así
    // que no tiene sentido seguir recordando quincenas atrasadas tampoco.
    // (Antes solo se congelaba la generación de periodos NUEVOS, pero los ya
    // vencidos seguían generando alerta — confirmado con el dueño del
    // negocio que ninguna alerta debería salir mientras esté pausado.)
    if (estadoClienteDe(t.cliente) !== 'activo') continue;
    const montoQ = parseFloat(t.pagoMensual || 0) / 2;

    // Generate periods from start to current month
    const inicioAM = anioMesDeFecha(t.fechaInicio);
    let cur = inicioAM ? new Date(inicioAM.anio, inicioAM.mes, 1) : new Date(now.getFullYear(), now.getMonth(), 1);
    let fin = new Date(now.getFullYear(), now.getMonth() + 1, 1);

    while (cur < fin) {
      const yr = cur.getFullYear();
      const mn = String(cur.getMonth() + 1).padStart(2, '0');
      const periodo = `${yr}-${mn}`;

      for (const q of [1, 2]) {
        // Due date: q1 = 15th, q2 = last day of month
        const dueDay = q === 1 ? 15 : new Date(yr, cur.getMonth() + 1, 0).getDate();
        const due = new Date(yr, cur.getMonth(), dueDay, 23, 59, 59);
        if (due >= now) { cur.setMonth(cur.getMonth() + 1); continue; } // not due yet

        const stored = (t.quincenas || []).find(r => r.periodo === periodo && r.q === q);
        if (stored && (stored.estado === 'pagado' || stored.estado === 'oculta')) continue;

        const alertKey = `${t.id}-${periodo}-q${q}`;
        if (!existeAlerta('quincena_vencida', 'key', alertKey)) {
          const monto = stored ? parseFloat(stored.monto || montoQ) : montoQ;
          const label = q === 1 ? '1 al 15' : '15 al 30';
          await addAlertTracked('quincena_vencida', {
            key: alertKey, id: t.id, cliente: t.cliente,
            periodo, q, label, monto,
            mensaje: `${t.cliente} — ${periodo} (${label}) $${monto.toFixed(2)} sin pagar`
          });
        }
      }
      cur.setMonth(cur.getMonth() + 1);
    }
  }

  // Upcoming events ≤ 48 hours
  for (const t of trabajos) {
    if (!t.fecha) continue;
    const fechaEvento = new Date(`${t.fecha}T${t.horaInicio || '00:00'}`);
    const diffH = (fechaEvento - now) / 3600000;
    if (diffH > 0 && diffH <= 48) {
      if (!existeAlerta('evento_proximo', 'id', t.id)) await addAlertTracked('evento_proximo', { id: t.id, cliente: t.cliente, tipo: t.servicio, hora: t.horaInicio, fecha: t.fecha });
    }
  }
}

// ══════════════════════════════════════════════════════════════
// VIEWS
// ══════════════════════════════════════════════════════════════

app.get('/admin', (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (!req.session.userId) return res.sendFile(path.join(__dirname, 'views', 'login-admin.html'));
  res.sendFile(path.join(__dirname, 'views', 'admin.html'));
});

app.get('/galeria', (req, res) => {
  res.sendFile(path.join(__dirname, 'views', 'galeria.html'));
});

// ══════════════════════════════════════════════════════════════
// AUTH API
// ══════════════════════════════════════════════════════════════

app.post('/api/admin/login', loginLimiter, async (req, res) => {
  try {
    const { username, password, remember } = req.body;
    const user = await Usuario.findOne({ username: username?.trim().toLowerCase() });
    if (!user || !(await bcrypt.compare(password, user.password)))
      return res.status(401).json({ error: 'Usuario o contraseña incorrectos' });
    if (remember) req.session.cookie.maxAge = 30 * 24 * 60 * 60 * 1000; // 30 días
    req.session.userId = user._id.toString();
    req.session.username = user.username;
    req.session.nombre = user.nombre;
    req.session.role = user.role;
    res.json({ ok: true, role: user.role, nombre: user.nombre });
  } catch (err) { handleError(res, err); }
});

app.post('/api/admin/logout', (req, res) => {
  req.session.destroy();
  res.json({ ok: true });
});


app.get('/api/admin/me', requireAdmin, async (req, res) => {
  try {
    const u = await Usuario.findById(req.session.userId, '-password').lean();
    res.json(u || { _id: req.session.userId, username: req.session.username, nombre: req.session.nombre, role: req.session.role });
  } catch { res.json({ _id: req.session.userId, username: req.session.username, nombre: req.session.nombre, role: req.session.role }); }
});

// ══════════════════════════════════════════════════════════════
// USUARIOS API (solo admin)
// ══════════════════════════════════════════════════════════════

app.get('/api/usuarios', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    const users = await Usuario.find({}, '-password').lean();
    res.json(users);
  } catch (err) { handleError(res, err); }
});

app.post('/api/usuarios', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    const { username, nombre, password, role } = req.body;
    if (!username || !password) return res.status(400).json({ error: 'Faltan campos' });
    const hash = await bcrypt.hash(password, 10);
    const u = await Usuario.create({ username: username.trim().toLowerCase(), nombre, password: hash, role: role || 'editor', creado: new Date().toISOString() });
    res.json({ ok: true, usuario: { _id: u._id, username: u.username, nombre: u.nombre, role: u.role } });
  } catch (err) {
    if (err.code === 11000) return res.status(400).json({ error: 'El usuario ya existe' });
    handleError(res, err);
  }
});

app.put('/api/usuarios/:id', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    const update = { nombre: req.body.nombre, role: req.body.role, icono: req.body.icono };
    if (req.body.password) update.password = await bcrypt.hash(req.body.password, 10);
    // Clear foto if user explicitly reset to an icon (no foto sent)
    if (req.body.foto === null) update.foto = null;
    await Usuario.updateOne({ _id: req.params.id }, { $set: update });
    // If editing own profile, refresh session data so sidebar updates immediately
    if (req.session.userId === req.params.id) {
      req.session.nombre = req.body.nombre;
      req.session.role = req.body.role;
    }
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.post('/api/usuarios/:id/foto', requireAdmin, async (req, res) => {
  try {
    // Anyone can update their own photo; changing someone else's requires the
    // same requireSuperAdmin check the other user-mutating routes already have.
    if (req.session.userId !== req.params.id && req.session.role !== 'admin') {
      return res.status(403).json({ error: 'Acceso denegado' });
    }
    const { base64 } = req.body;
    if (!base64) return res.status(400).json({ error: 'No image' });
    const result = await cloudinary.uploader.upload(base64, {
      folder: 'nokta-usuarios',
      public_id: `user_${req.params.id}`,
      overwrite: true,
      transformation: [{ width: 200, height: 200, crop: 'fill', gravity: 'face' }],
    });
    await Usuario.updateOne({ _id: req.params.id }, { $set: { foto: result.secure_url } });
    res.json({ ok: true, url: result.secure_url });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/usuarios/:id', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    const u = await Usuario.findById(req.params.id);
    if (u?.role === 'admin') return res.status(400).json({ error: 'No puedes eliminar al admin' });
    await Usuario.deleteOne({ _id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// CLIENTES API
// ══════════════════════════════════════════════════════════════

app.get('/api/clientes', requireAdmin, async (req, res) => {
  try {
    await checkAlerts();
    const clientes = await Cliente.find({}).sort({ creado: -1 }).lean();
    res.json(clientes);
  } catch (err) { handleError(res, err); }
});

app.post('/api/clientes', requireAdmin, async (req, res) => {
  try {
    const { nombre, tipo, dias, whatsapp } = req.body;
    const codigo = await generateCode(tipo);
    const ahora = new Date();
    const diasNum = parseInt(dias);
    const expira = diasNum === 0 ? null : new Date(ahora.getTime() + diasNum * 86400000);

    if (tipo !== 'contacto') {
      try { await cloudinary.api.create_folder(`nokta-clientes/${codigo}`); } catch (e) {}
    }

    const cliente = await Cliente.create({
      codigo, nombre, tipo,
      whatsapp: whatsapp || '',
      dias: diasNum,
      creado: ahora.toISOString(),
      expira: expira ? expira.toISOString() : null,
      estado: 'activo',
      visitas: [], descargas: [], favoritos: [], reactivaciones: []
    });
    res.json({ ok: true, cliente, link: `${process.env.BASE_URL}/galeria?codigo=${codigo}` });
  } catch (err) { handleError(res, err); }
});

app.put('/api/clientes/:codigo/reactivar', requireAdmin, async (req, res) => {
  try {
    const c = await Cliente.findOne({ codigo: req.params.codigo });
    if (!c) return res.status(404).json({ error: 'No encontrado' });
    const dias = parseInt(req.body.dias) || 7;
    const base = c.expira && new Date(c.expira) > new Date() ? new Date(c.expira) : new Date();
    c.expira = new Date(base.getTime() + dias * 86400000).toISOString();
    c.estado = 'activo';
    if (!c.reactivaciones) c.reactivaciones = [];
    c.reactivaciones.push({ fecha: new Date().toISOString(), dias });
    await c.save();
    res.json({ ok: true, expira: c.expira });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/clientes/:codigo', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    await Cliente.deleteOne({ codigo: req.params.codigo });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// ESTADO DE RELACIÓN DEL CLIENTE (activo / pausado / cancelado)
// ══════════════════════════════════════════════════════════════

app.get('/api/clientes-estados', requireAdmin, async (req, res) => {
  try {
    const estados = await ClienteEstado.find({}).lean();
    res.json(estados);
  } catch (err) { handleError(res, err); }
});

app.put('/api/clientes-estados/:nombre', requireAdmin, async (req, res) => {
  try {
    const { estado, notas } = req.body;
    if (!['activo', 'pausado', 'cancelado'].includes(estado)) {
      return res.status(400).json({ error: 'Estado inválido' });
    }
    // Express already URL-decodes route params once; decoding again here
    // would throw for names containing a literal "%" (e.g. "100% Nokta").
    const nombre = req.params.nombre;
    const update = { nombre, estado, actualizado: new Date().toISOString() };
    if (notas !== undefined) update.notas = notas;
    const doc = await ClienteEstado.findOneAndUpdate(
      { nombre },
      update,
      { upsert: true, new: true }
    );
    res.json({ ok: true, clienteEstado: doc });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// GALERÍA PÚBLICA API
// ══════════════════════════════════════════════════════════════

app.get('/api/galeria/:codigo', galeriaLimiter, async (req, res) => {
  try {
    const c = await Cliente.findOne({ codigo: req.params.codigo });
    if (!c) return res.status(404).json({ error: 'Código no válido' });
    if (c.expira && new Date(c.expira) < new Date()) {
      c.estado = 'expirado';
      await c.save();
      return res.status(410).json({ error: 'Este link ya no está disponible. Contactá a Nokta Studio.' });
    }
    const diasRestantes = c.expira ? Math.max(0, Math.ceil((new Date(c.expira) - new Date()) / 86400000)) : null;
    res.json({ codigo: c.codigo, nombre: c.nombre, tipo: c.tipo, expira: c.expira, diasRestantes, favoritos: c.favoritos || [] });
  } catch (err) { handleError(res, err); }
});

app.post('/api/galeria/:codigo/visita', galeriaLimiter, async (req, res) => {
  try {
    await Cliente.updateOne({ codigo: req.params.codigo }, { $push: { visitas: new Date().toISOString() } });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.post('/api/galeria/:codigo/descarga', galeriaLimiter, async (req, res) => {
  try {
    const c = await Cliente.findOne({ codigo: req.params.codigo });
    if (!c) return res.status(404).json({ error: 'No encontrado' });
    const descarga = { tipo: req.body.tipo || 'todo', fecha: new Date().toISOString() };
    c.descargas.push(descarga);
    c.estado = 'descargado';
    await c.save();
    await addAlert('descarga', { nombre: c.nombre, codigo: c.codigo, tipo: descarga.tipo, fecha: descarga.fecha });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.post('/api/galeria/:codigo/favoritos', galeriaLimiter, async (req, res) => {
  try {
    await Cliente.updateOne({ codigo: req.params.codigo }, { $set: { favoritos: req.body.favoritos || [] } });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.get('/api/galeria/:codigo/fotos', galeriaLimiter, async (req, res) => {
  try {
    const result = await cloudinary.api.resources({ type: 'upload', prefix: `nokta-clientes/${req.params.codigo}/`, max_results: 500 });
    res.json(result.resources.map(r => ({
      public_id: r.public_id,
      url: r.secure_url,
      thumb: cloudinary.url(r.public_id, { width: 600, crop: 'fill', quality: 'auto', fetch_format: 'auto', secure: true })
    })));
  } catch (err) { res.json([]); }
});

app.get('/api/galeria/:codigo/zip', galeriaLimiter, async (req, res) => {
  try {
    let zipUrl;
    if (req.query.tipo === 'favoritas' && req.query.ids) {
      zipUrl = cloudinary.utils.download_zip_url({ public_ids: req.query.ids.split(','), resource_type: 'image' });
    } else {
      zipUrl = cloudinary.utils.download_zip_url({ prefixes: [`nokta-clientes/${req.params.codigo}/`], resource_type: 'image' });
    }
    res.json({ url: zipUrl });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// TRABAJOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/trabajos', requireAdmin, async (req, res) => {
  try { res.json(await Trabajo.find({}).sort({ creado: -1 }).lean()); }
  catch (err) { handleError(res, err); }
});

app.post('/api/trabajos', requireAdmin, async (req, res) => {
  try {
    const datos = pick(req.body, TRABAJO_FIELDS);
    const monto = parseFloat(datos.monto) || 0;
    const anticipo = parseFloat(datos.anticipo) || 0;
    const trabajo = await Trabajo.create({ id: `t${Date.now()}`, ...datos, monto, anticipo, saldo: monto - anticipo, creado: new Date().toISOString() });
    if (trabajo.fecha) {
      await Evento.create({ id: trabajo.id, titulo: `${trabajo.cliente} — ${trabajo.servicio}`, tipo: trabajo.servicio, fecha: trabajo.fecha, horaInicio: trabajo.horaInicio || '', horaFin: trabajo.horaFin || '', lugar: trabajo.lugar || '', monto, anticipo, saldo: monto - anticipo });
    }
    res.json({ ok: true, trabajo });
  } catch (err) { handleError(res, err); }
});

app.put('/api/trabajos/:id', requireAdmin, async (req, res) => {
  try {
    const t = await Trabajo.findOne({ id: req.params.id });
    if (!t) return res.status(404).json({ error: 'No encontrado' });
    Object.assign(t, pick(req.body, TRABAJO_FIELDS));
    const m = parseFloat(t.monto) || 0;
    const a = parseFloat(t.anticipo) || 0;
    t.saldo = m - a;
    await t.save();
    res.json({ ok: true, trabajo: t });
  } catch (err) { handleError(res, err); }
});

app.patch('/api/trabajos/:id/quincenas', requireAdmin, async (req, res) => {
  try {
    const t = await Trabajo.findOneAndUpdate(
      { id: req.params.id },
      { $set: { quincenas: req.body.quincenas } },
      { new: true }
    );
    if (!t) return res.status(404).json({ error: 'No encontrado' });
    res.json({ ok: true, quincenas: t.quincenas });
  } catch (err) { handleError(res, err); }
});

// Sesiones: pagos recurrentes sueltos (ej. clases semanales) sin periodo fijo,
// a diferencia de las quincenas (grupo B) que están ancladas a mes/día 15-30.
// El monto/anticipo/saldo/estado del trabajo se recalculan aquí a partir de
// las sesiones para que el dashboard, el perfil del cliente y las alertas
// (que ya leen esos campos) sigan funcionando sin cambios adicionales.
app.patch('/api/trabajos/:id/sesiones', requireAdmin, async (req, res) => {
  try {
    const sesiones = req.body.sesiones || [];
    const monto = sesiones.reduce((s, x) => s + (parseFloat(x.monto) || 0), 0);
    const anticipo = sesiones.filter(x => x.estado === 'pagado').reduce((s, x) => s + (parseFloat(x.monto) || 0), 0);
    const estado = sesiones.length && sesiones.every(x => x.estado === 'pagado') ? 'pagado' : 'pendiente';
    const t = await Trabajo.findOneAndUpdate(
      { id: req.params.id },
      { $set: { sesiones, monto, anticipo, saldo: monto - anticipo, estado } },
      { new: true }
    );
    if (!t) return res.status(404).json({ error: 'No encontrado' });
    res.json({ ok: true, trabajo: t });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/trabajos/:id', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    await Trabajo.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// GASTOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/gastos', requireAdmin, async (req, res) => {
  try { res.json(await Gasto.find({}).sort({ creado: -1 }).lean()); }
  catch (err) { handleError(res, err); }
});

app.post('/api/gastos', requireAdmin, async (req, res) => {
  try {
    const datos = pick(req.body, GASTO_FIELDS);
    const gasto = await Gasto.create({ id: `g${Date.now()}`, ...datos, monto: parseFloat(datos.monto) || 0, creado: new Date().toISOString() });
    res.json({ ok: true, gasto });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/gastos/:id', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    await Gasto.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// DOCUMENTOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/documentos', requireAdmin, async (req, res) => {
  try {
    const cotizaciones = await Cotizacion.find({}).sort({ creado: -1 }).lean();
    const recibos = await Recibo.find({}).sort({ creado: -1 }).lean();
    res.json({ cotizaciones, recibos });
  } catch (err) { handleError(res, err); }
});

app.post('/api/documentos', requireAdmin, async (req, res) => {
  try {
    const tipo = req.body.tipo;
    const datos = pick(req.body, DOCUMENTO_FIELDS);
    let numero, doc;
    if (tipo === 'cotizacion') {
      const count = await Cotizacion.countDocuments({ clienteNombre: datos.clienteNombre });
      numero = `NK-COT-${String(count + 1).padStart(3, '0')}`;
      doc = await Cotizacion.create({ id: `cot${Date.now()}`, numero, tipo: 'cotizacion', ...datos, creado: new Date().toISOString() });
    } else {
      const count = await Recibo.countDocuments({ clienteNombre: datos.clienteNombre });
      numero = `NK-REC-${String(count + 1).padStart(3, '0')}`;
      doc = await Recibo.create({ id: `rec${Date.now()}`, numero, tipo: 'recibo', ...datos, creado: new Date().toISOString() });
    }
    res.json({ ok: true, numero, doc });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/documentos/:tipo/:id', requireAdmin, async (req, res) => {
  try {
    const { tipo, id } = req.params;
    if (tipo !== 'cotizacion' && tipo !== 'recibo') return res.status(400).json({ error: 'Tipo inválido' });
    const Model = tipo === 'cotizacion' ? Cotizacion : Recibo;
    await Model.deleteOne({ id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// CONTRATOS API — historial de contratos generados desde un Trabajo
// (ver PDFTemplates.contrato() en la app / contratoHTML() en admin.html,
// que renderizan estos mismos campos).
// ══════════════════════════════════════════════════════════════

app.get('/api/contratos', requireAdmin, async (req, res) => {
  try { res.json(await Contrato.find({}).sort({ creado: -1 }).lean()); }
  catch (err) { handleError(res, err); }
});

app.post('/api/contratos', requireAdmin, async (req, res) => {
  try {
    const datos = pick(req.body, CONTRATO_FIELDS);
    const contrato = await Contrato.create({ id: `con${Date.now()}`, ...datos, creado: new Date().toISOString() });
    res.json({ ok: true, contrato });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/contratos/:id', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    await Contrato.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// ALERTAS API
// ══════════════════════════════════════════════════════════════

app.get('/api/alertas', requireAdmin, async (req, res) => {
  try {
    await checkAlerts();
    const estados = await ClienteEstado.find({}).lean();
    const inactivos = new Set(estados.filter(e => e.estado === 'pausado' || e.estado === 'cancelado').map(e => e.nombre));
    const alertas = await Alerta.find({}).sort({ fecha: -1 }).lean();
    // Hide existing overdue alerts too, while retaining their read/deduplication state.
    res.json(alertas.filter(a => a.tipo !== 'quincena_vencida' || !inactivos.has(a.datos?.cliente)));
  } catch (err) { handleError(res, err); }
});

app.put('/api/alertas/leer', requireAdmin, async (req, res) => {
  try {
    await Alerta.updateMany({}, { $set: { leida: true } });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.put('/api/alertas/:id/leer', requireAdmin, async (req, res) => {
  try {
    await Alerta.updateOne({ id: req.params.id }, { $set: { leida: true } });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/alertas/:id', requireAdmin, async (req, res) => {
  try {
    await Alerta.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// EQUIPO API
// ══════════════════════════════════════════════════════════════

app.get('/api/equipo', requireAdmin, async (req, res) => {
  try { res.json(await Equipo.find({}).lean()); }
  catch (err) { handleError(res, err); }
});

app.post('/api/equipo', requireAdmin, async (req, res) => {
  try {
    const m = await Equipo.create({ id: `m${Date.now()}`, ...pick(req.body, EQUIPO_FIELDS), creado: new Date().toISOString() });
    res.json({ ok: true, miembro: m });
  } catch (err) { handleError(res, err); }
});

app.put('/api/equipo/:id', requireAdmin, async (req, res) => {
  try {
    await Equipo.updateOne({ id: req.params.id }, { $set: pick(req.body, EQUIPO_FIELDS) });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/equipo/:id', requireAdmin, async (req, res) => {
  try {
    await Equipo.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// EVENTOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/eventos', requireAdmin, async (req, res) => {
  try { res.json(await Evento.find({}).sort({ fecha: 1 }).lean()); }
  catch (err) { handleError(res, err); }
});

app.post('/api/eventos', requireAdmin, async (req, res) => {
  try {
    const ev = await Evento.create({ id: `ev${Date.now()}`, ...pick(req.body, EVENTO_FIELDS), creado: new Date().toISOString() });
    res.json({ ok: true, evento: ev });
  } catch (err) { handleError(res, err); }
});

app.delete('/api/eventos/:id', requireAdmin, async (req, res) => {
  try {
    await Evento.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { handleError(res, err); }
});

// ══════════════════════════════════════════════════════════════
// 404
// ══════════════════════════════════════════════════════════════
app.use((req, res) => res.status(404).send('Página no encontrada'));

// ── Start server ────────────────────────────────────────────
function getLanIP() {
  const nets = os.networkInterfaces();
  for (const iface of Object.values(nets))
    for (const net of iface)
      if (net.family === 'IPv4' && !net.internal) return net.address;
  return 'tu-ip-local';
}

const PORT = process.env.PORT || 3000;
const HOST = process.env.NODE_ENV === 'production' && !process.send ? '0.0.0.0' : '127.0.0.1';
const server = app.listen(PORT, HOST, () => {
  const actualPort = server.address().port;
  if (process.send) process.send({ type: 'ready', port: actualPort });
  console.log(`Nokta server running on http://${HOST}:${actualPort}/admin`);
});
