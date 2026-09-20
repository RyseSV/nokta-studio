const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname,'../views/admin.html'),'utf8');
const code = html.slice(html.indexOf('function renderSesionesPanel('), html.indexOf('function animateStatNums('));
let fail = false, calls = 0, closed = 0, pending = null;
const notices = [], fields = {'as-fecha':{value:'2026-09-26'},'as-monto':{value:'20'}};
const t = {id:'t1',cliente:'Fátima',sesiones:[{id:'s1',fecha:'2026-09-19',monto:20,estado:'pendiente',fechaPago:null}]};
const sandbox = {
  allTrabajos:[t], _panelTrabajoId:'t1', console, Date, Set, Number, JSON, Error,
  crypto:require('node:crypto').webcrypto, fmtFecha:x=>x,
  toast:(m,t)=>notices.push({m,t}), confirm:()=>true, prompt:()=> '35',
  document:{getElementById:id=>fields[id]}, closeModal:()=>closed++, openModal:()=>{},
  openTrabajo:async()=>{},loadDashboard:async()=>{},
  fetch:async(url,options)=>{
    calls++; if(pending) await pending;
    if(fail) return {ok:false,json:async()=>({error:'Prueba de error'})};
    const sesiones = JSON.parse(options.body).sesiones;
    const monto = sesiones.reduce((s,x)=>s+x.monto,0);
    const anticipo = sesiones.filter(x=>x.estado==='pagado').reduce((s,x)=>s+x.monto,0);
    return {ok:true,json:async()=>({ok:true,trabajo:{...t,sesiones,monto,anticipo,saldo:monto-anticipo}})};
  }
};
vm.createContext(sandbox);vm.runInContext(code,sandbox);
(async()=>{
  assert(sandbox.renderSesionesPanel(t).includes('Editar monto'));
  await sandbox.marcarSesionPagada('t1','s1');assert.equal(t.sesiones[0].estado,'pagado');assert(t.sesiones[0].fechaPago);
  assert(sandbox.renderSesionesPanel(t).includes('Revertir'));
  await sandbox.editarMontoSesion('t1','s1');assert.equal(t.sesiones[0].monto,35);assert.equal(t.sesiones[0].estado,'pagado');assert.equal(t.anticipo,35);
  await sandbox.revertirSesionPagada('t1','s1');assert.equal(t.sesiones[0].estado,'pendiente');assert.equal(t.sesiones[0].fechaPago,null);assert.equal(t.saldo,35);
  fail=true;const before=JSON.stringify(t);const successes=notices.filter(x=>x.m.startsWith('✓')).length;
  await sandbox.marcarSesionPagada('t1','s1');assert.equal(JSON.stringify(t),before);assert.equal(notices.filter(x=>x.m.startsWith('✓')).length,successes);
  vm.runInContext("_asTrabajoId='t1'",sandbox);
  await sandbox.confirmarAgregarSesion();assert.equal(closed,0);assert.equal(t.sesiones.length,1);
  fail=false;
  fields['as-fecha'].value='2026-02-30';let previous=calls;await sandbox.confirmarAgregarSesion();assert.equal(calls,previous);
  fields['as-fecha'].value='2026-09-19';await sandbox.confirmarAgregarSesion();assert.equal(calls,previous);
  fields['as-fecha'].value='2026-09-26';fields['as-monto'].value='-2';await sandbox.confirmarAgregarSesion();assert.equal(calls,previous);
  fields['as-monto'].value='20';await sandbox.confirmarAgregarSesion();assert.equal(closed,1);assert.equal(t.sesiones.length,2);
  let release;pending=new Promise(r=>release=r);
  const first=sandbox.marcarSesionPagada('t1','s1');previous=calls;await sandbox.editarMontoSesion('t1','s1');assert.equal(calls,previous);release();await first;pending=null;
  for(const s of [...t.sesiones]) await sandbox.eliminarSesion('t1',s.id);
  assert.equal(t.sesiones.length,0);
  // Real openTrabajo must leave an explicitly empty collection empty after deletion.
  const openCode=html.slice(html.indexOf('async function openTrabajo('),html.indexOf("document.getElementById('td-title')",html.indexOf('async function openTrabajo(')));
  assert(openCode.includes('esRecurrente && !Array.isArray(t.sesiones)'));
  t.sesiones=[{id:'legacy1',fecha:'2026-09-19',monto:0,estado:'pendiente'},{id:'legacy2',fecha:'2026-09-26',monto:0,estado:'pendiente'}];
  previous=calls;await sandbox.editarMontoSesion('t1','legacy1');assert.equal(calls,previous+1);assert.equal(t.sesiones[0].monto,35);assert.equal(t.sesiones[1].monto,0);
  t.sesiones[0].monto=0;previous=calls;await sandbox.eliminarSesion('t1','legacy1');assert.equal(calls,previous+1);assert.equal(t.sesiones.length,1);
  console.log('PASS: legacy invalid sessions can be repaired/deleted individually');
  console.log('PASS: pay/revert/edit, failures preserve state/modal, invalid/duplicate creation, double submit lock, last deletion stays empty');
})().catch(e=>{console.error(e);process.exitCode=1});
