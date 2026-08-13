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
    const hash = await bcrypt.hash(process.env.ADMIN_PASSWORD || 'Nokta2026!', 10);
    await Usuario.create({ username: 'admin', nombre: 'Administrador', password: hash, role: 'admin', creado: new Date().toISOString() });
    console.log('  Admin user creado ✓');
  }
}

const trabajoSchema = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const gastoSchema   = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const cotSchema     = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const reciboSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const alertaSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const equipoSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });
const eventoSchema  = new mongoose.Schema({ id: { type: String, unique: true } }, { strict: false });

const Cliente    = mongoose.model('Cliente',    clienteSchema);
const Trabajo    = mongoose.model('Trabajo',    trabajoSchema);
const Gasto      = mongoose.model('Gasto',      gastoSchema);
const Cotizacion = mongoose.model('Cotizacion', cotSchema);
const Recibo     = mongoose.model('Recibo',     reciboSchema);
const Alerta     = mongoose.model('Alerta',     alertaSchema);
const Equipo     = mongoose.model('Equipo',     equipoSchema);
const Evento     = mongoose.model('Evento',     eventoSchema);

// ── Connect MongoDB ─────────────────────────────────────────
mongoose.connect(process.env.MONGODB_URI)
  .then(async () => { console.log('  MongoDB conectado ✓'); await seedAdmin(); })
  .catch(err => { console.error('MongoDB error:', err); process.exit(1); });

// ── Express setup ───────────────────────────────────────────
const app = express();
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
app.use(session({
  secret: process.env.SESSION_SECRET || 'nokta_secret',
  resave: false,
  saveUninitialized: false,
  store: MongoStore.create({ mongoUrl: process.env.MONGODB_URI }),
  cookie: { maxAge: null }  // session cookie — expires when browser closes
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
  return `NK-${year}-${prefix}-${String(count + 1).padStart(4, '0')}`;
}

// ── Auto-generate alerts ────────────────────────────────────
async function addAlert(tipo, datos) {
  const id = `a${Date.now()}${Math.random().toString(36).slice(2,6)}`;
  await Alerta.create({ id, tipo, datos, fecha: new Date().toISOString(), leida: false });
}

async function checkAlerts() {
  const now = new Date();

  // Expiring gallery links (≤ 3 days)
  const clientes = await Cliente.find({});
  for (const c of clientes) {
    if (!c.expira) continue;
    const exp = new Date(c.expira);
    const days = Math.ceil((exp - now) / 86400000);
    if (days <= 3 && days > 0 && c.estado === 'activo') {
      const exists = await Alerta.findOne({ tipo: 'link_venciendo', 'datos.codigo': c.codigo });
      if (!exists) await addAlert('link_venciendo', { nombre: c.nombre, codigo: c.codigo, diasRestantes: days });
    }
    if (exp < now && c.estado === 'activo') {
      await Cliente.updateOne({ codigo: c.codigo }, { estado: 'expirado' });
    }
  }

  // Pending payments > 7 days
  const trabajos = await Trabajo.find({});
  for (const t of trabajos) {
    if (t.estado !== 'pendiente' || !t.creado) continue;
    const days = Math.ceil((now - new Date(t.creado)) / 86400000);
    if (days >= 7) {
      const exists = await Alerta.findOne({ tipo: 'pago_pendiente', 'datos.id': t.id });
      if (!exists) await addAlert('pago_pendiente', { id: t.id, cliente: t.cliente, servicio: t.servicio, saldo: t.saldo });
    }
  }

  // Upcoming events ≤ 48 hours
  for (const t of trabajos) {
    if (!t.fecha) continue;
    const fechaEvento = new Date(`${t.fecha}T${t.horaInicio || '00:00'}`);
    const diffH = (fechaEvento - now) / 3600000;
    if (diffH > 0 && diffH <= 48) {
      const exists = await Alerta.findOne({ tipo: 'evento_proximo', 'datos.id': t.id });
      if (!exists) await addAlert('evento_proximo', { id: t.id, cliente: t.cliente, tipo: t.servicio, hora: t.horaInicio, fecha: t.fecha });
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
  } catch (err) { res.status(500).json({ error: err.message }); }
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
  } catch (err) { res.status(500).json({ error: err.message }); }
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
    res.status(500).json({ error: err.message });
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
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/usuarios/:id/foto', requireAdmin, async (req, res) => {
  try {
    console.log('POST /api/usuarios/:id/foto — id:', req.params.id, 'body size:', JSON.stringify(req.body).length);
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
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/usuarios/:id', requireAdmin, requireSuperAdmin, async (req, res) => {
  try {
    const u = await Usuario.findById(req.params.id);
    if (u?.role === 'admin') return res.status(400).json({ error: 'No puedes eliminar al admin' });
    await Usuario.deleteOne({ _id: req.params.id });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// CLIENTES API
// ══════════════════════════════════════════════════════════════

app.get('/api/clientes', requireAdmin, async (req, res) => {
  try {
    await checkAlerts();
    const clientes = await Cliente.find({}).sort({ creado: -1 }).lean();
    res.json(clientes);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/clientes', requireAdmin, async (req, res) => {
  try {
    const { nombre, tipo, dias, whatsapp } = req.body;
    const codigo = await generateCode(tipo);
    const ahora = new Date();
    const diasNum = parseInt(dias);
    const expira = diasNum === 0 ? null : new Date(ahora.getTime() + diasNum * 86400000);

    try { await cloudinary.api.create_folder(`nokta-clientes/${codigo}`); } catch (e) {}

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
  } catch (err) { res.status(500).json({ error: err.message }); }
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
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/clientes/:codigo', requireAdmin, async (req, res) => {
  try {
    await Cliente.deleteOne({ codigo: req.params.codigo });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// GALERÍA PÚBLICA API
// ══════════════════════════════════════════════════════════════

app.get('/api/galeria/:codigo', async (req, res) => {
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
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/galeria/:codigo/visita', async (req, res) => {
  try {
    await Cliente.updateOne({ codigo: req.params.codigo }, { $push: { visitas: new Date().toISOString() } });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/galeria/:codigo/descarga', async (req, res) => {
  try {
    const c = await Cliente.findOne({ codigo: req.params.codigo });
    if (!c) return res.status(404).json({ error: 'No encontrado' });
    const descarga = { tipo: req.body.tipo || 'todo', fecha: new Date().toISOString() };
    c.descargas.push(descarga);
    c.estado = 'descargado';
    await c.save();
    await addAlert('descarga', { nombre: c.nombre, codigo: c.codigo, tipo: descarga.tipo, fecha: descarga.fecha });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/galeria/:codigo/favoritos', async (req, res) => {
  try {
    await Cliente.updateOne({ codigo: req.params.codigo }, { favoritos: req.body.favoritos || [] });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/galeria/:codigo/fotos', async (req, res) => {
  try {
    const result = await cloudinary.api.resources({ type: 'upload', prefix: `nokta-clientes/${req.params.codigo}/`, max_results: 500 });
    res.json(result.resources.map(r => ({
      public_id: r.public_id,
      url: r.secure_url,
      thumb: cloudinary.url(r.public_id, { width: 600, crop: 'fill', quality: 'auto', fetch_format: 'auto', secure: true })
    })));
  } catch (err) { res.json([]); }
});

app.get('/api/galeria/:codigo/zip', async (req, res) => {
  try {
    let zipUrl;
    if (req.query.tipo === 'favoritas' && req.query.ids) {
      zipUrl = cloudinary.utils.download_zip_url({ public_ids: req.query.ids.split(','), resource_type: 'image' });
    } else {
      zipUrl = cloudinary.utils.download_zip_url({ prefixes: [`nokta-clientes/${req.params.codigo}/`], resource_type: 'image' });
    }
    res.json({ url: zipUrl });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// TRABAJOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/trabajos', requireAdmin, async (req, res) => {
  try { res.json(await Trabajo.find({}).sort({ creado: -1 }).lean()); }
  catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/trabajos', requireAdmin, async (req, res) => {
  try {
    const monto = parseFloat(req.body.monto) || 0;
    const anticipo = parseFloat(req.body.anticipo) || 0;
    const trabajo = await Trabajo.create({ id: `t${Date.now()}`, ...req.body, monto, anticipo, saldo: monto - anticipo, creado: new Date().toISOString() });
    if (trabajo.fecha) {
      await Evento.create({ id: trabajo.id, titulo: `${trabajo.cliente} — ${trabajo.servicio}`, tipo: trabajo.servicio, fecha: trabajo.fecha, horaInicio: trabajo.horaInicio || '', horaFin: trabajo.horaFin || '', lugar: trabajo.lugar || '', monto, anticipo, saldo: monto - anticipo });
    }
    res.json({ ok: true, trabajo });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.put('/api/trabajos/:id', requireAdmin, async (req, res) => {
  try {
    const t = await Trabajo.findOne({ id: req.params.id });
    if (!t) return res.status(404).json({ error: 'No encontrado' });
    Object.assign(t, req.body);
    const m = parseFloat(t.monto) || 0;
    const a = parseFloat(t.anticipo) || 0;
    t.saldo = m - a;
    await t.save();
    res.json({ ok: true, trabajo: t });
  } catch (err) { res.status(500).json({ error: err.message }); }
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
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/trabajos/:id', requireAdmin, async (req, res) => {
  try {
    await Trabajo.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// GASTOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/gastos', requireAdmin, async (req, res) => {
  try { res.json(await Gasto.find({}).sort({ creado: -1 }).lean()); }
  catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/gastos', requireAdmin, async (req, res) => {
  try {
    const gasto = await Gasto.create({ id: `g${Date.now()}`, ...req.body, monto: parseFloat(req.body.monto) || 0, creado: new Date().toISOString() });
    res.json({ ok: true, gasto });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/gastos/:id', requireAdmin, async (req, res) => {
  try {
    await Gasto.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// DOCUMENTOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/documentos', requireAdmin, async (req, res) => {
  try {
    const cotizaciones = await Cotizacion.find({}).sort({ creado: -1 }).lean();
    const recibos = await Recibo.find({}).sort({ creado: -1 }).lean();
    res.json({ cotizaciones, recibos });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/documentos', requireAdmin, async (req, res) => {
  try {
    const { tipo, ...datos } = req.body;
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
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// ALERTAS API
// ══════════════════════════════════════════════════════════════

app.get('/api/alertas', requireAdmin, async (req, res) => {
  try {
    await checkAlerts();
    res.json(await Alerta.find({}).sort({ fecha: -1 }).lean());
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.put('/api/alertas/leer', requireAdmin, async (req, res) => {
  try {
    await Alerta.updateMany({}, { leida: true });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.put('/api/alertas/:id/leer', requireAdmin, async (req, res) => {
  try {
    await Alerta.updateOne({ id: req.params.id }, { leida: true });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/alertas/:id', requireAdmin, async (req, res) => {
  try {
    await Alerta.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// EQUIPO API
// ══════════════════════════════════════════════════════════════

app.get('/api/equipo', requireAdmin, async (req, res) => {
  try { res.json(await Equipo.find({}).lean()); }
  catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/equipo', requireAdmin, async (req, res) => {
  try {
    const m = await Equipo.create({ id: `m${Date.now()}`, ...req.body, creado: new Date().toISOString() });
    res.json({ ok: true, miembro: m });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.put('/api/equipo/:id', requireAdmin, async (req, res) => {
  try {
    await Equipo.updateOne({ id: req.params.id }, { $set: req.body });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/equipo/:id', requireAdmin, async (req, res) => {
  try {
    await Equipo.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ══════════════════════════════════════════════════════════════
// EVENTOS API
// ══════════════════════════════════════════════════════════════

app.get('/api/eventos', requireAdmin, async (req, res) => {
  try { res.json(await Evento.find({}).sort({ fecha: 1 }).lean()); }
  catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/eventos', requireAdmin, async (req, res) => {
  try {
    const ev = await Evento.create({ id: `ev${Date.now()}`, ...req.body, creado: new Date().toISOString() });
    res.json({ ok: true, evento: ev });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/api/eventos/:id', requireAdmin, async (req, res) => {
  try {
    await Evento.deleteOne({ id: req.params.id });
    res.json({ ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
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
