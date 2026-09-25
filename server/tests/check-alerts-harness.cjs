// Harness: extracts checkAlerts()+addAlert() straight from server/app.js source
// (same "slice the real function, run it in a vm context" technique the
// other server/tests/*.cjs files already use) and drives it against a tiny
// in-memory fake of the four Mongoose models it touches. This lets us test
// the actual production code, not a reimplementation of it.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const APP_PATH = path.join(__dirname, '..', 'app.js');

function getPath(obj, p) { return p.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj); }
function matches(doc, query) {
  return Object.entries(query).every(([k, v]) => getPath(doc, k) === v);
}

function makeModel(seed = []) {
  let docs = seed.map(d => ({ ...d }));
  const query = (list) => {
    const q = {};
    q.lean = () => Promise.resolve(list.map(d => ({ ...d })));
    q.then = (res, rej) => Promise.resolve(list).then(res, rej);
    q.catch = (rej) => Promise.resolve(list).catch(rej);
    return q;
  };
  return {
    _docs: () => docs,
    find(filter = {}) { return query(docs.filter(d => matches(d, filter))); },
    findOne(filter = {}) { return Promise.resolve(docs.find(d => matches(d, filter)) || null); },
    countDocuments(filter = {}) { return Promise.resolve(docs.filter(d => matches(d, filter)).length); },
    create(doc) { const d = { ...doc }; docs.push(d); return Promise.resolve(d); },
    updateOne(filter, update) {
      const doc = docs.find(d => matches(d, filter));
      if (!doc) return Promise.resolve({ matchedCount: 0 });
      const hasOperator = Object.keys(update).some(k => k.startsWith('$'));
      if (hasOperator) {
        if (update.$set) Object.assign(doc, update.$set);
        if (update.$push) for (const [k, v] of Object.entries(update.$push)) { doc[k] = doc[k] || []; doc[k].push(v); }
      } else {
        // Mongoose wraps plain updateOne fields in $set; it does not
        // replace the document (replaceOne is the separate replacement API).
        Object.assign(doc, update);
      }
      return Promise.resolve({ matchedCount: 1 });
    },
  };
}

function loadCheckAlerts() {
  const src = fs.readFileSync(APP_PATH, 'utf8');
  const start = src.indexOf('function anioMesDeFecha');
  const end = src.indexOf("app.get('/admin'");
  const code = src.slice(start, end) + '\nglobalThis.__checkAlerts = checkAlerts;';
  return code;
}

function newWorld({ clientes = [], trabajos = [], alertas = [], estados = [] } = {}, now = new Date()) {
  const ctx = {
    Cliente: makeModel(clientes),
    Trabajo: makeModel(trabajos),
    Alerta: makeModel(alertas),
    ClienteEstado: makeModel(estados),
    Date: (function () {
      // Allow tests to pin "now" without changing global Date everywhere else.
      class FixedDate extends Date {
        constructor(...args) { super(...(args.length ? args : [now])); }
        static now() { return args_now; }
      }
      const args_now = now.getTime();
      return FixedDate;
    })(),
    console,
  };
  vm.createContext(ctx);
  vm.runInContext(loadCheckAlerts(), ctx);
  return ctx;
}

module.exports = { newWorld, makeModel };
