/* Real production adapter handlers in the existing fake DOM. No game latency claim. */
'use strict';
const {page}=require('./test_cef_chat.js');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {performance}=require('node:perf_hooks');
const candidate=require('../cef/assets/hud/pa26-chat.js');
const baseline=process.argv[2]&&require(path.resolve(process.argv[2],'cef/assets/hud/pa26-chat.js'));
function stats(samples){samples.sort((a,b)=>a-b);return {samples:samples.length,median_ms:samples[Math.floor(samples.length/2)],p95_ms:samples[Math.floor(samples.length*.95)],worst_handler_ms:samples.at(-1)};}
(async()=>{
 const output={environment:'Node V8 + existing fake DOM; real adapter callbacks',game_started:false,
  actual_input_latency_measured:false,actual_fps_measured:false,chat_contents_recorded:false,rows:{}};
 for(const [name,adapter]of [['PA_OFF',null],['v0.45.0',baseline],['v0.45.1',candidate]]){
  if(name==='v0.45.0'&&!baseline)continue;
  const p=await page(false,adapter);
  if(adapter){
   const fetch=p.root.fetch,challenge='e'.repeat(48);
   p.root.fetch=async(url,options)=>{const request=JSON.parse(options.body),reply=await fetch(url,options),value=await reply.json();
    return {ok:true,json:async()=>({...value,compatibility:{protocol:2,challenge,phase:request.compatibility?.phase==='confirmed'?'ready':'ack',state:'RUNTIME_VERIFIED'}})};};
   p.api.endpoint('http://127.0.0.1:39003/'+challenge+'/exchange',{protocol:2,challenge,fingerprint:'benchmark'});
   await p.exchange();await p.exchange();
  }

  for(let i=0;i<550;i++)p.callbacks['chat:messages'](i,'Fixture line '+i,'INFO');
  if(adapter)await p.exchange();
  p.type('Русский English '.repeat(80));
  const before={...p.stats},requests=p.requests.length,results={};
  const cases={russian:()=>p.fire('input'),english:()=>p.fire('input'),backspace:()=>p.fire('keydown',{key:'Backspace'}),
   word_selection:()=>p.fire('selectionchange'),drag_selection:()=>{p.fire('mousemove');p.fire('selectionchange');},double_click:()=>p.fire('dblclick'),
   ctrl_a:()=>p.fire('keydown',{key:'a',ctrlKey:true}),ctrl_c:()=>p.fire('keydown',{key:'c',ctrlKey:true}),ctrl_v:()=>p.fire('keydown',{key:'v',ctrlKey:true}),
   long_message:()=>p.fire('input'),unrelated_cef:()=>p.root.cef.emit('UnrelatedUiEvent',13)};
  for(const [test,run]of Object.entries(cases)){
   for(let i=0;i<1000;i++)run();
   const samples=[];for(let i=0;i<12000;i++){const t=performance.now();run();samples.push(performance.now()-t);}
   results[test]=stats(samples);
  }
  await new Promise(setImmediate);
  const delta=Object.fromEntries(Object.keys(p.stats).map(k=>[k,p.stats[k]-before[k]]));
  assert.equal(delta.textReads,0);assert.equal(delta.textWrites,0);assert.equal(delta.styleReads,0);assert.equal(delta.rectReads,0);
  assert.equal(p.requests.length,requests,'Editing must not trigger PA IPC');
  output.rows[name]={handlers:results,editing_dom_work:delta,editing_ipc:0,history_lines:550};p.api.stop();
 }
 fs.writeFileSync(path.join(__dirname,'CEF_PERFORMANCE0451.json'),JSON.stringify(output,null,2)+'\n');
 console.log(JSON.stringify(output));
})().catch(e=>{console.error(e);process.exitCode=1;});
