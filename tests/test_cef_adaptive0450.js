'use strict';
const {page}=require('./test_cef_chat.js'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const install=require('../cef/assets/hud/pa26-chat.js');let checks=0;
const eq=(a,b,m)=>{checks++;assert.deepEqual(a,b,m);};
(async()=>{
 const p=await page();const c={protocol:2,challenge:'b'.repeat(48),fingerprint:'profile'};
 const originalFetch=p.root.fetch;let received=0,ready=false;
 p.root.fetch=async(url,options)=>{
  const request=JSON.parse(options.body);received++;
  const h=request.compatibility;
  let phase='hello';if(h&&h.challenge===c.challenge&&h.protocol===2){
   if(h.phase==='hello'&&Object.values(h.capabilities).every(v=>v===true))phase='ack';
   if(h.phase==='confirmed'){phase='ready';ready=true;}
  }
  const response=await originalFetch(url,options),value=await response.json();
  return {ok:true,json:async()=>({...value,enabled:phase==='ready',compatibility:{protocol:2,challenge:c.challenge,phase,state:ready?'RUNTIME_VERIFIED':'CONTRACT_COMPATIBLE'}})};
 };
 p.api.endpoint('http://127.0.0.1:39002/'+c.challenge+'/exchange',c);
 await p.exchange();await p.exchange();eq(ready,true);eq(received>=2,true);
 eq(install(p.root),p.api,'Repeated adapter installation is idempotent');
 for(const [raw,result]of [['руддщ','руддщ'],['ghbdtn','ghbdtn'],['John_Smith: привет, hello!','John_Smith: привет, hello!'],['/me проверил John_Smith.','/me проверил John_Smith.'],['/r Тест.','/r Тест.']]){
  await p.config({accentEnabled:false});p.type(raw);await p.enter();eq(p.sent.at(-1)[1],result,'Ordinary text/name/layout is never guessed');
 }
 const before={...p.stats},network=p.requests.length;
 for(let i=0;i<10000;i++)for(const event of ['input','selectionchange','mousemove','dblclick'])p.fire(event);
 eq(p.requests.length,network);for(const name of ['textReads','textWrites','styleReads','rectReads'])eq(p.stats[name],before[name],name+' editing overhead');
 const originalOn=p.root.cef.on;let receiver;const target={};p.root.cef.on('other',function(){receiver=this;return 7;});eq(p.callbacks.other.call(target),7);eq(receiver,target);eq(p.root.cef.on,originalOn);
 // Initializing a new endpoint restores the native field limit while awaiting
 // confirmation; an existing long draft must remain intact.
 p.input.maxLength=128;
 await p.config({chatText:{version:1,keyboardMap:{},manual:{enabled:true}}});eq(p.input.maxLength,8192);
 p.type('Я'.repeat(300));
 // Invalid/missing handshake: original HUD submission and rendering survive.
 p.api.endpoint('http://127.0.0.1:39003/'+'c'.repeat(48)+'/exchange',{...c,challenge:'c'.repeat(48)});
 eq(p.input.maxLength,128);eq(p.input.value,'Я'.repeat(300),'Recovery never discards the draft');
 p.root.fetch=async()=>({ok:true,json:async()=>({schema:1,ack:0,enabled:true})});await p.exchange();
 p.type('Без подтверждения.');await p.enter();eq(p.sent.at(-1)[1],'Без подтверждения.');
 p.callbacks['chat:messages'](1,'Оригинальный входящий текст.');eq(p.callbacks.rendered.at(-1)[1],'Оригинальный входящий текст.');
 p.api.stop();
 const report={status:'passed',checks,editing_events:40000,editing_ipc:0,game_started:false,actual_latency_measured:false};
 fs.writeFileSync(path.join(__dirname,'CEF_ADAPTIVE_JS0450.json'),JSON.stringify(report,null,2)+'\n');console.log(report);
})().catch(e=>{console.error(e);process.exitCode=1;});
