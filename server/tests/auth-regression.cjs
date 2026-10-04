// Real middleware and route handlers, with local model/session doubles only.
const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const src=fs.readFileSync(require('node:path').join(__dirname,'../app.js'),'utf8');
const routes={}; let user={_id:'u1',username:'before',nombre:'Name',role:'admin'}, dbError=false, duplicate=false, lastUpdate;
const ctx={console, process:{env:{}}, Usuario:{
 findById:()=>({lean:async()=>{if(dbError)throw Error('db offline');return user&&{...user};}}),
 updateOne:async(query,update)=>{if(duplicate)throw Object.assign(Error('duplicate'),{code:11000});lastUpdate=update.$set;return{matchedCount:user?1:0};},
},bcrypt:{hash:async()=> 'hash'},logSecurity:()=>{},Date,handleError:(res)=>res.status(500).json({error:'server error'}),app:{}};
for(const method of ['post','get','put'])ctx.app[method]=(path,...handlers)=>{routes[method+' '+path]=handlers.at(-1)};
vm.createContext(ctx);
vm.runInContext(src.slice(src.indexOf('function pick('),src.indexOf('const TRABAJO_FIELDS')),ctx);
vm.runInContext(src.slice(src.indexOf('const INACTIVIDAD_MS'),src.indexOf('// ── Auth middleware')),ctx);
vm.runInContext(src.slice(src.indexOf('async function requireAdmin('),src.indexOf('// ── Generate client code')),ctx);
vm.runInContext(src.slice(src.indexOf("app.post('/api/admin/logout'"),src.indexOf("app.post('/api/usuarios/:id/foto'")),ctx);
function response(){return{code:200,body:undefined,cleared:false,status(n){this.code=n;return this},json(b){this.body=b;return this},clearCookie(){this.cleared=true;return this}}}
function request(h={}){return{session:{userId:'u1',role:'admin',username:'before',destroy(cb){cb()}},body:{},params:{id:'u1'},get:k=>h[k]}}
(async()=>{
 let req=request(),res=response(),next=0; await ctx.requireAdmin(req,res,()=>next++);ctx.requireSuperAdmin(req,res,()=>next++);assert.equal(next,2);
 user.role='editor';req=request();res=response();next=0;await ctx.requireAdmin(req,res,()=>next++);ctx.requireSuperAdmin(req,res,()=>next++);assert.equal(next,1);assert.equal(res.code,403);assert.equal(req.session.role,'editor');
 user=null;req=request();res=response();next=0;await ctx.requireAdmin(req,res,()=>next++);assert.equal(next,0);assert.equal(res.code,401);
 dbError=true;res=response();await ctx.requireAdmin(request(),res,()=>assert.fail('must fail closed'));assert.equal(res.code,500);dbError=false;
 const logout=routes['post /api/admin/logout'];let complete;req=request();req.session.destroy=cb=>{complete=cb};res=response();logout(req,res);assert.equal(res.body,undefined);complete();assert.equal(res.body.ok,true);assert.equal(res.cleared,true);
 res=response();logout(req,res);complete(Error('store failed'));assert.equal(res.code,500);assert.equal(res.body.ok,undefined);
 user={_id:'u1',username:'before',role:'admin'};const update=routes['put /api/usuarios/:id'];req=request();req.body={username:'  NewName  '};res=response();await update(req,res);assert.equal(lastUpdate.username,'newname');assert.equal(req.session.username,'newname');assert.equal(req.session.role,'admin');assert.equal(res.body.ok,true);
 for(const username of ['   ',{},null]){req=request();req.body={username};res=response();await update(req,res);assert.equal(res.code,400)}
 duplicate=true;req=request();req.body={username:'alreadyused'};res=response();await update(req,res);assert.equal(res.code,400);assert.match(res.body.error,/ya existe/);duplicate=false;
 user=null;req=request();req.body={username:'missing'};res=response();await update(req,res);assert.equal(res.code,404);
 // Inactividad: >12 min sin uso cierra la sesión; las consultas en segundo plano no cuentan como uso.
 user={_id:'u1',username:'before',role:'admin'};
 req=request();req.session.ultimaActividad=Date.now()-13*60*1000;res=response();next=0;await ctx.requireAdmin(req,res,()=>next++);assert.equal(next,0);assert.equal(res.code,401);assert.equal(res.body.inactividad,true);assert.equal(res.cleared,true);
 const antes=Date.now()-5*60*1000;req=request({'X-Nokta-Segundo-Plano':'1'});req.session.ultimaActividad=antes;res=response();next=0;await ctx.requireAdmin(req,res,()=>next++);assert.equal(next,1);assert.equal(req.session.ultimaActividad,antes);
 req=request();req.session.ultimaActividad=antes;res=response();next=0;await ctx.requireAdmin(req,res,()=>next++);assert.equal(next,1);assert.ok(req.session.ultimaActividad>antes);
 console.log('PASS auth (inactividad: vence a los 12 min, segundo plano no cuenta, uso real renueva) + current role, deleted user, DB fail closed, logout completion/errors, normalized username, validation, duplicate and missing user');
})().catch(e=>{console.error(e);process.exitCode=1});
