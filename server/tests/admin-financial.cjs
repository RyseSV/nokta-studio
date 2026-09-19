const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../views/admin.html'),'utf8');
const functions=html.slice(html.indexOf('  function ingresosDelPeriodo'),html.indexOf('async function loadDashboard'));
const dates=html.slice(html.indexOf('function mesAnioDeFecha'),html.indexOf('\n}',html.indexOf('function mesAnioDeFecha'))+2);
const ctx={allTrabajos:[],allClienteEstados:[],SVC_GRUPO:{}};
vm.createContext(ctx); vm.runInContext(dates+'\n'+functions,ctx);
const jobs=[
 {id:'class',cliente:'Fátima',grupo:'A',fecha:'2026-08-01',saldo:100,sesiones:[
 {fecha:'2026-09-12',monto:20,estado:'pagado'},
 {fecha:'2026-09-19',monto:20,estado:'pendiente'},
 {fecha:'2026-09-26',monto:20,estado:'pendiente'}]},
 {id:'paused',cliente:'TuBoleto',grupo:'B',pagoMensual:250,estadoContrato:'activo'},
 {id:'future',grupo:'B',fechaInicio:'2026-10-01',pagoMensual:600},
 {id:'paid',grupo:'B',pagoMensual:100,quincenas:[{periodo:'2026-09',q:1,monto:50,estado:'pagado'},{periodo:'2026-09',q:2,monto:50,estado:'oculta'}]},
 {id:'ordinary',estado:'pendiente',fecha:'2026-09-01',saldo:30,monto:50},
 {id:'old',estado:'pendiente',fecha:'2026-08-01',saldo:500},
 {id:'cancelled',grupo:'B',pagoMensual:100,estadoContrato:'cancelado'},
];
const states=[{nombre:'TuBoleto',estado:'pausado'}];
const sum=(j=jobs,period='2026-09',st=states)=>ctx.cobrosPendientes(period,j,st).reduce((s,c)=>s+c.monto,0);
assert.equal(sum(),50);
assert.equal(ctx.ingresosDelPeriodo('2026-09',jobs),120);
assert.equal(new Set(ctx.cobrosPendientes('2026-09',jobs,states).map(c=>c.trabajoId)).size,2);
jobs[0].sesiones[1].estado='pagado';
assert.match(ctx.cobrosPendientes('2026-09',[jobs[0]],states)[0].concepto,/2026-09-26/);
assert.match(ctx.cobrosPendientes('2026-10',[jobs[0]],states)[0].concepto,/fuera del mes/);
jobs[0].sesiones[2].estado='cancelado'; assert.equal(sum([jobs[0]]),0);
assert.equal(sum([{cliente:'C',grupo:'B',pagoMensual:100,estadoContrato:'cancelado'}],'2026-09',[{nombre:'C',estado:'activo'}]),100);
assert.equal(sum([{grupo:'B',pagoMensual:100,quincenas:[{periodo:'2026-09',q:1,monto:0,estado:'pendiente'},{periodo:'2026-09',q:2,estado:'oculta'}]}]),0);
// Parse the actual complete inline script: catches syntax breaks in neighboring UI.
const scripts=[...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
for(const [,script] of scripts) if(script.trim()) new vm.Script(script);
console.log('PASS: browser financial calculations, session advance, paused/future contracts, month revenue, zero amounts and script syntax');
// Exercise actual report integration, not just the reusable calculation.
const report=html.slice(html.indexOf('async function genReporte'),html.indexOf('// HELPERS',html.indexOf('async function genReporte')));
let output='';
ctx.Date=class extends Date { constructor(...args){ super(...(args.length?args:['2026-09-19T12:00:00-06:00'])); } };
ctx.location={origin:'https://example.test'};
ctx.window={open:()=>({document:{write:s=>{output=s;},close(){}}})};
ctx.esc=s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
ctx.api=async path=>({'/api/trabajos':jobs,'/api/gastos':[],'/api/clientes':[],'/api/clientes-estados':states})[path];
vm.runInContext(report,ctx);
(async()=>{
 jobs[0].sesiones[1].estado='pendiente';jobs[0].sesiones[2].estado='pendiente';
 await ctx.genReporte('mensual');assert.match(output,/\$120\.00/);
 await ctx.genReporte('clientes');assert.match(output,/Fátima[\s\S]*?\$20\.00/);assert.match(output,/Cobro del mes \/ próxima sesión/);
 console.log('PASS: monthly/client report integration');
})().catch(e=>{console.error(e);process.exitCode=1;});
