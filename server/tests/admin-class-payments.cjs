const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../views/admin.html'),'utf8');
const code=html.slice(html.indexOf('async function openTrabajo('),html.indexOf('function _generarPeriodos('));
const els={};
const t={id:'clase',cliente:'Fátima',servicio:'Clases',grupo:'A',monto:999,anticipo:999,saldo:999,sesiones:[
 {id:'1',fecha:'2026-09-12',monto:20,estado:'pagado'},
 {id:'2',fecha:'2026-09-19',monto:20,estado:'pagado'},
 {id:'3',fecha:'2026-09-26',monto:20,estado:'pendiente'},
 {id:'4',fecha:'2026-10-03',monto:20,estado:'pendiente'}]};
const context={allTrabajos:[t],allClienteEstados:[{nombre:'Fátima',estado:'activo'}],currentUser:{role:'admin'},SVC_GRUPO:{},GRUPO_NOMBRES:{},ESTADO_CLIENTE_PILL:{activo:''},ESTADO_CLIENTE_LABEL:{activo:'Activo'},estadoClienteDe:()=> 'activo',esc:x=>String(x),fmtFecha:x=>x,renderSesionesPanel:()=>'',animateStatNums:()=>{},document:{getElementById:id=>els[id]??=( {classList:{add(){}},innerHTML:'',textContent:''}),querySelectorAll:()=>[]}};
vm.createContext(context);vm.runInContext(code,context);
(async()=>{
 await context.openTrabajo('clase');let result=els['td-body'].innerHTML;
 assert(!result.includes('>ANTICIPO<'));assert(!result.includes('$999'));
 assert.match(result,/PAGOS DE SESIONES[\s\S]*?\$40\.00/);
 assert.match(result,/PRÓXIMA SESIÓN SIN PAGAR[\s\S]*?2026-09-26 · \$20\.00/);
 t.sesiones.forEach(s=>s.estado='pendiente');await context.openTrabajo('clase');
 assert.match(els['td-body'].innerHTML,/PAGOS DE SESIONES[\s\S]*?\$0\.00/);
 t.servicio='Foto';t.sesiones=undefined;await context.openTrabajo('clase');
 assert(els['td-body'].innerHTML.includes('>ANTICIPO<'));
 console.log('PASS: classes derive collected payments from sessions, no invented deposit, next charge, ordinary deposits preserved');
})().catch(e=>{console.error(e);process.exitCode=1});
