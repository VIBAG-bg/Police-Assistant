/* Own adapter, deterministic clocks and transport; no GTA/server or private text. */
'use strict';
const {page}=require('./test_cef_chat.js');
const install=require('../cef/assets/hud/pa26-chat.js');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
let checks=0;const cases=[];
const eq=(a,b,m)=>{checks++;assert.deepEqual(a,b,m);};
const flush=()=>new Promise(resolve=>setImmediate(resolve));
const url=n=>'http://127.0.0.1:39001/'+n.repeat(48)+'/exchange';
function handshake(p,challenge='b') {
 const original=p.root.fetch,metadata={protocol:2,challenge:challenge.repeat(48),fingerprint:'profile'};
 const hello=[];let ready=false;
 p.root.fetch=async(endpoint,options)=>{
  const request=JSON.parse(options.body),h=request.compatibility;hello.push(h);
  let phase='hello';
  if(h&&h.challenge===metadata.challenge){
   if(h.phase==='hello'&&Object.values(h.capabilities).every(x=>x===true))phase='ack';
   if(h.phase==='confirmed'){phase='ready';ready=true;}
  }
  const r=await original(endpoint,options),v=await r.json();
  return {ok:true,json:async()=>({...v,enabled:phase==='ready',compatibility:{...metadata,phase,state:ready?'RUNTIME_VERIFIED':'CONTRACT_COMPATIBLE'}})};
 };
 return {metadata,hello,ready:()=>ready};
}
(async()=>{
 let saved;
 let p=await page(false,install,{endpoint:false,register:false,beforeInstall(root){saved=root.cef;delete root.cef;}});
 p.runTimers(50);p.runTimers(100);await flush();
 p.root.cef=saved;p.runTimers(200);p.registerIncoming();
 const h=handshake(p);p.api.endpoint(url('b'),h.metadata);await p.exchange();await p.exchange();
 eq(h.ready(),true,'Late CEF is discovered and the real handshake completes');
 eq(Object.values(h.hello[0].capabilities).every(Boolean),true);
 const wrappers=[p.root.cef.on,p.root.cef.emit,p.root.cef.set_focus];
 for(let i=0;i<20;i++){eq(install(p.root),p.api);p.api.reconnect();await flush();}
 eq([p.root.cef.on,p.root.cef.emit,p.root.cef.set_focus],wrappers,'Retry never stacks wrappers');
 const observed=p.observed.length;p.callbacks['chat:messages'](1,'Synthetic incoming.');await p.exchange();
 eq(p.callbacks.rendered.length,1);eq(p.observed.length-observed,1,'One incoming observation after repeated initialization');
 const receiver={};eq(p.root.cef.emit.call(receiver,'unrelated',1,2,3),receiver);eq(p.sent.at(-1),['unrelated',1,2,3]);
 p.api.stop();cases.push('late CEF, handshake and no duplicate handlers');

 // Missing CEF eventually stops probing. Neither ordinary editing nor lease
 // heartbeats restart it; a lifecycle retry is explicitly bounded again.
 let reads=0;
 p=await page(false,install,{endpoint:false,register:false,beforeInstall(root){Object.defineProperty(root,'cef',{configurable:true,get(){reads++;return undefined;}});}});
 for(let i=0;i<20;i++){p.runTimers(5000);await flush();}
 const stoppedReads=reads,editing={...p.stats},network=p.requests.length;
 for(let i=0;i<10000;i++)for(const name of ['input','selectionchange','mousemove','dblclick'])p.fire(name);
 for(let i=0;i<100;i++){p.time(750);await p.heartbeat();}
 eq(reads,stoppedReads,'No unbounded CEF-object probing');eq(reads<=16,true);
 eq(p.requests.length,network);for(const k of ['textReads','textWrites','styleReads','rectReads'])eq(p.stats[k],editing[k]);
 eq([...p.timers.values()].filter(t=>!t.interval).length,0,'No perpetual discovery timers');
 p.api.stop();cases.push('bounded missing CEF; 40000 editing events without discovery/DOM/IPC');

 // A partially initialized object is left intact. Existing pre-hook incoming
 // subscriptions must not be falsely presented as a verified capability.
 let focus;
 p=await page(false,install,{endpoint:false,beforeInstall(root){focus=root.cef.set_focus;delete root.cef.set_focus;}});
 const on=p.root.cef.on;p.runTimers(50);eq(p.root.cef.on,on);
 p.root.cef.set_focus=focus;p.runTimers(100);
 const partial=handshake(p,'c');p.api.endpoint(url('c'),partial.metadata);await p.exchange();
 eq(partial.hello[0].capabilities.incoming,false);eq(partial.ready(),false,'Do not invent missing incoming evidence');
 p.callbacks['chat:messages'](2,'Original renderer.');eq(p.callbacks.rendered.length,1);
 p.registerIncoming();await p.exchange();await p.exchange();eq(partial.ready(),true);
 p.api.stop();cases.push('partial CEF and honest incoming-capability verification');

 const times=[];
 p=await page(false,install,{endpoint:false,beforeInstall(root){root.document.head.appendChild=el=>{times.push(root.performance.now());el.onerror();};}});
 for(let i=0;i<2400;i++){p.time(750);await p.heartbeat();}
 eq(times.length,7,'Persistent missing endpoint has a finite seven-attempt burst');
 const minimum=[2500,5000,10000,20000,30000,60000];
 for(let i=1;i<times.length;i++)eq(times[i]-times[i-1]>=minimum[i-1],true,'Increasing endpoint backoff');
 const dormant=times.length;p.root.document.visibilityState='hidden';p.fire('visibilitychange');eq(times.length,dormant);
 p.root.document.visibilityState='visible';p.windowEvent('focus');eq(times.length,dormant+1,'Returning to the page rearms discovery');
 for(let i=0;i<100;i++)p.windowEvent('focus');eq(times.length,dormant+1,'Repeated focus cannot reset an active backoff');
 p.api.stop();cases.push('30-minute missing endpoint, exponential backoff and lifecycle recovery');

 // Failed HTTP is also backed off; it cannot keep fetching an obsolete port
 // at 750ms forever. A new authenticated endpoint starts a fresh handshake.
 p=await page(false,install,{offline:true});
 for(let i=0;i<2400;i++){p.time(750);await p.heartbeat();}
 eq(p.requests.length<=16,true,'Bounded failed HTTP traffic');eq(p.stats.endpointLoads<=8,true);
 const requests=p.requests.length,loads=p.stats.endpointLoads;
 for(let i=0;i<100;i++){p.time(750);await p.heartbeat();}
 eq(p.requests.length,requests);eq(p.stats.endpointLoads,loads,'Dormant means no further I/O');
 p.offline(false);p.api.endpoint(url('d'));await p.exchange();
 p.type('Recovered.');await p.enter();eq(p.sent.at(-1)[1],'[Русский акцент]: Recovered.');
 const healthy=p.stats.endpointLoads;
 for(let i=0;i<30;i++){p.time(750);await p.heartbeat();}
 eq(p.stats.endpointLoads,healthy,'Healthy leases do not reload endpoint scripts');
 // Same-endpoint temporary outage recovers within backoff, without duplicates.
 p.offline(true);await p.exchange();const failed=p.requests.length;
 for(let i=0;i<30;i++)await p.exchange();eq(p.requests.length,failed,'No retry storm');
 p.offline(false);p.time(750);await p.exchange();p.type('/me оглянулся.');await p.enter();eq(p.sent.at(-1)[1],'/me оглянулся.');
 p.api.stop();cases.push('30-minute IPC outage, changed endpoint and temporary-failure recovery');

 p=await page();const response=p.root.fetch,challenge='f'.repeat(48);
 p.root.fetch=async(endpoint,options)=>{const r=await response(endpoint,options),v=await r.json();return {ok:true,json:async()=>({...v,enabled:false,compatibility:{protocol:2,challenge,phase:'hello',state:'INCOMPATIBLE'}})};};
 p.api.endpoint(url('f'),{protocol:2,challenge,fingerprint:'fixture'});await p.exchange();
 for(let i=0;i<2400;i++){p.time(750);await p.heartbeat();}
 eq(p.requests.length<=17,true,'Failed handshake also backs off and becomes dormant');
 eq(p.warnings.at(-1),'[PA26 CEF] exchange_failed: handshake_failed');
 p.type('Original chat.');await p.enter();eq(p.sent.at(-1)[1],'Original chat.','Rejected handshake leaves the original HUD usable');
 p.api.stop();cases.push('rejected runtime handshake has bounded traffic and native chat fallback');

 p=await page();const waitingResponse=p.root.fetch,waitingChallenge='9'.repeat(48);
 p.root.fetch=async(endpoint,options)=>{const r=await waitingResponse(endpoint,options),v=await r.json();return {ok:true,json:async()=>({...v,enabled:false,compatibility:{protocol:2,challenge:waitingChallenge,phase:'hello',state:'CONTRACT_COMPATIBLE'}})};};
 p.api.endpoint(url('9'),{protocol:2,challenge:waitingChallenge,fingerprint:'fixture'});await p.exchange();
 p.time(13000);await p.exchange();eq(p.warnings.at(-1),'[PA26 CEF] exchange_failed: handshake_failed','An endless provisional reply times out');
 const pendingCount=p.requests.length;await p.exchange();eq(p.requests.length,pendingCount,'A timed-out handshake respects backoff');
 p.type('Unconfirmed.');await p.enter();eq(p.sent.at(-1)[1],'Unconfirmed.');p.api.stop();
 cases.push('provisional handshake timeout and unchanged original submission');

 // Every script has a timeout; old callbacks cannot clear a newer request.
 const scripts=[];
 p=await page(false,install,{endpoint:false,beforeInstall(root){root.document.head.appendChild=el=>scripts.push(el);}});
 const late=scripts[0].onload;p.runTimers(2000);eq(scripts[0].onload,null);eq(scripts[0].isConnected,false);
 p.time(500);await p.heartbeat();eq(scripts.length,2);late();
 await p.heartbeat();eq(scripts.length,2,'Late completion is idempotent');
 p.api.stop();eq(scripts[1].onload,null);eq([...p.timers.values()].filter(t=>!t.interval).length,0);
 p.runTimers(30000);p.windowEvent('focus');p.fire('DOMContentLoaded');eq(scripts.length,2,'Stop prevents delayed revival');
 cases.push('stalled script, late callback and stop cleanup');

 p=await page(false,install,{endpoint:false,beforeInstall(root){root.document.head.appendChild=()=>{throw Error('synthetic append denied');};}});
 eq(p.stats.endpointLoads,0);p.api.stop();cases.push('append failure safely cleaned up');

 // An obsolete in-flight failure must not poison the new endpoint's state.
 p=await page();const original=p.root.fetch;let rejectOld,first=true;
 p.root.fetch=(endpoint,options)=>{if(first){first=false;return new Promise((resolve,reject)=>{rejectOld=reject;});}return original(endpoint,options);};
 const old=p.api.exchange();p.api.endpoint(url('e'));rejectOld(Error('old endpoint closed'));
 await old;await flush();await p.exchange();eq(p.warnings.length,0,'Stale error is ignored');
 p.type('New session.');await p.enter();eq(p.sent.at(-1)[1],'[Русский акцент]: New session.');p.api.stop();
 cases.push('in-flight endpoint replacement');

 const adapter=path.resolve(__dirname,'../cef/assets/hud/pa26-chat.js');
 const report={status:'passed',checks,cases,adapter_sha256:crypto.createHash('sha256').update(fs.readFileSync(adapter)).digest('hex'),
  simulated_outage_minutes:30,editing_events:40000,editing_ipc:0,game_started:false,actual_game_latency:'NOT RUN'};
 fs.writeFileSync(path.join(__dirname,'CEF_RECOVERY0450.json'),JSON.stringify(report,null,2)+'\n');console.log(report);
})().catch(e=>{console.error(e);process.exitCode=1;});
