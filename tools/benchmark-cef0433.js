/* Real Chromium editing/selection/paint timings, isolated chat-shaped DOM.
 * A loopback test server supplies metadata; this is NOT GTA/CEF acceptance.
 * Reports contain aggregate timings/counters and hashes, never chat contents. */
'use strict';
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),old=path.resolve(root,'../Police-Assistant-2026-v0.43.2-dev/cef/assets/hud/pa26-chat.js');
const current=path.join(root,'cef/assets/hud/pa26-chat.js');
const duration=Number(process.argv[2]||15000),rows=[];
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const policy={version:1,skipBrackets:true,dotCommands:true,keyboardMap:{к:'r'},radioPrefix:{enabled:true,localTag:'[TEST]'},manual:{enabled:true,maxParts:3,threshold:90,marker:'...',displayLimit:115,margin:6,nicknameLength:16,meExtra:1,doExtra:3,rpEnabled:true,speechEnabled:true,todoActionLimit:60}};
const server=http.createServer((req,res)=>{
 if(req.method==='POST'){
  let data='';req.on('data',d=>data+=d);req.on('end',()=>{
   const q=JSON.parse(data),ack=q.events.at(-1)?.id||0;
   const value={schema:1,ack,enabled:true,session:'benchmark',policyRevision:1,keyboardLayout:'RU'};
   if(q.policyRevision===1)value.policyUnchanged=true;
   else Object.assign(value,{accentEnabled:true,accent:'[Русский акцент]:',layoutIndicator:true,weaponGuard:true,diagnostics:false,filters:[],localCommands:['pa26'],chatText:policy});
   res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(value));
  });return;
 }
 res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});res.end('<style>body{font:16px Arial;background:#232830;color:white}.history{height:600px;overflow:hidden}.message{padding:1px}#chatInput{display:none;position:fixed;bottom:30px;left:15px;right:15px;gap:8px}#chatInput.active{display:flex}input{width:850px;font:18px Arial;padding:10px}</style><div class="history" id="history"></div><div id="chatInput" class="active"><input id="chatInputField" maxlength="8192"><button id="SendMsgButton">Send</button></div>');
});
function percentile(values,p){if(!values.length)return null;const a=[...values].sort((a,b)=>a-b);return a[Math.min(a.length-1,Math.floor(a.length*p))];}
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({headless:true,executablePath:'C:/Users/35987/AppData/Local/ms-playwright/chromium-1067/chrome-win/chrome.exe'});
 try{for(const [mode,file,ms] of [['disabled',null,15000],['0.43.2',old,15000],['0.43.3',current,duration]]){
  const context=await browser.newContext({viewport:{width:1152,height:864},permissions:['clipboard-read','clipboard-write']});const page=await context.newPage();
  await page.goto(url);
  await page.evaluate(()=>{
   const h=document.getElementById('history');for(let i=0;i<1500;i++){const el=document.createElement('div');el.className='message';el.textContent='Строка журнала для измерения '+i;h.appendChild(el);}
   window.cef={emit(){window.emitted=(window.emitted||0)+1;return 7;},on(){},set_focus(){}};window.isDialogActive=()=>false;
   window.sendMessageToChat=t=>{const result=cef.emit('HandleHudSendMessage',t);document.getElementById('chatInput').classList.remove('active');return result;};
   window.ops={styles:0,rects:0,requests:0,valueReads:0};
   const style=window.getComputedStyle,rect=Element.prototype.getClientRects,fetch=window.fetch,desc=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
   window.getComputedStyle=function(...a){ops.styles++;return style(...a)};Element.prototype.getClientRects=function(...a){ops.rects++;return rect.apply(this,a)};
   window.fetch=function(...a){ops.requests++;return fetch(...a)};
   Object.defineProperty(HTMLInputElement.prototype,'value',{...desc,get(){ops.valueReads++;return desc.get.call(this)}});
   window.samples={frames:[],inputPaint:[],longTasks:[],inputs:0};let last;
   const frame=t=>{if(last!==undefined&&samples.frames.length<65000)samples.frames.push(t-last);last=t;window.raf=requestAnimationFrame(frame)};window.raf=requestAnimationFrame(frame);
   document.addEventListener('input',()=>{samples.inputs++;const at=performance.now();requestAnimationFrame(()=>{if(samples.inputPaint.length<50000)samples.inputPaint.push(performance.now()-at)})});
   if(window.PerformanceObserver){window.observer=new PerformanceObserver(list=>{for(const e of list.getEntries())if(samples.longTasks.length<5000)samples.longTasks.push(e.duration)});try{observer.observe({entryTypes:['longtask']})}catch{}}
  });
  const loadedSource=file && fs.readFileSync(file),loadedHash=loadedSource && crypto.createHash('sha256').update(loadedSource).digest('hex');
  if(file){await page.addScriptTag({content:loadedSource.toString('utf8')});await page.evaluate(endpoint=>PA26Chat.endpoint(endpoint),url+'/'+'a'.repeat(48)+'/exchange');}
  await page.locator('#chatInputField').focus();await page.waitForTimeout(1200);
  // Warm-up excluded. All paths use the same measured browser interactions.
  await page.evaluate(()=>{samples={frames:[],inputPaint:[],longTasks:[],inputs:0};window.startOps={...ops};window.emitted=0});
  const started=performance.now();let lastProgress=started,cycles=0,selectionChecks=0,submissionChecks=0;
  while(performance.now()-started<ms){
   const input=page.locator('#chatInputField');
   await page.evaluate(()=>document.getElementById('chatInput').classList.add('active'));await input.focus();
   await page.keyboard.press('Control+A');await page.keyboard.insertText('Короткое русское сообщение, затем English words for selection.');
   await page.keyboard.type(' fast English 12345');
   for(let i=0;i<10;i++)await page.keyboard.press('Backspace');
   await page.keyboard.press('Control+A');await page.keyboard.press('Control+C');await page.keyboard.press('ArrowRight');await page.keyboard.press('Control+V');
   const text=await input.inputValue();
   const box=await input.boundingBox();await page.mouse.move(box.x+25,box.y+20);await page.mouse.down();await page.mouse.move(box.x+400,box.y+20,{steps:20});await page.mouse.up();
   const selected=await input.evaluate(el=>el.selectionEnd>el.selectionStart);assert(selected,'Mouse drag selection must work');selectionChecks++;
   await page.mouse.dblclick(box.x+100,box.y+20);assert(await input.evaluate(el=>el.selectionEnd>el.selectionStart));selectionChecks++;
   assert.equal(await input.inputValue(),text,'Selection must preserve text');
   await page.keyboard.press('Control+A');await page.keyboard.insertText('длинное сообщение '.repeat(27));
   await page.keyboard.press('Home');await page.keyboard.down('Shift');await page.keyboard.press('ArrowRight');await page.keyboard.up('Shift');
   await page.waitForTimeout(820);assert((await input.inputValue()).length>400,'Long draft must remain editable');
   for(const body of ['/me осмотрел салон.','/do Окно открыто.','/r Доклад.','Обычная реплика.']){
    await page.evaluate(()=>document.getElementById('chatInput').classList.add('active'));await input.focus();await page.keyboard.press('Control+A');await page.keyboard.insertText(body);
    const before=await page.evaluate(()=>emitted);await page.keyboard.press('Enter');
    // Standalone fixture mirrors the HUD Enter caller; submission stays synchronous.
    await page.evaluate(()=>sendMessageToChat(document.getElementById('chatInputField').value));
    assert.equal(await page.evaluate(()=>emitted),before+1,'A submission must emit exactly once');submissionChecks++;
   }
   await page.evaluate(()=>document.getElementById('chatInput').classList.add('active'));await input.focus();cycles++;
   if(performance.now()-lastProgress>=60000){console.log(JSON.stringify({progress:mode,elapsed_ms:performance.now()-started,cycles}));lastProgress=performance.now();}
  }
  const raw=await page.evaluate(()=>({samples,operations:Object.fromEntries(Object.keys(ops).map(k=>[k,ops[k]-startOps[k]]))}));
  const row={mode,adapter_sha256:loadedHash,elapsed_ms:performance.now()-started,cycles,selection_checks:selectionChecks,exactly_once_checks:submissionChecks,operations:raw.operations,
   inputs:raw.samples.inputs,frames:raw.samples.frames.length,input_to_next_frame_ms:{p50:percentile(raw.samples.inputPaint,.5),p95:percentile(raw.samples.inputPaint,.95),max:Math.max(0,...raw.samples.inputPaint)},
   frame_ms:{p50:percentile(raw.samples.frames,.5),p95:percentile(raw.samples.frames,.95),p99:percentile(raw.samples.frames,.99),max:Math.max(0,...raw.samples.frames),over33:raw.samples.frames.filter(x=>x>33).length,over100:raw.samples.frames.filter(x=>x>100).length},long_tasks:raw.samples.longTasks.length};
  rows.push(row);console.log(JSON.stringify(row));await context.close();
 }}finally{await browser.close();await new Promise(r=>server.close(r));}
 const report={status:'measured',browser:'Chromium 112',os:process.platform,viewport:'1152x864',real_browser_input:true,history_rows:1500,loopback_metadata_test_server:true,live_gta_measured:false,
  limitations:'Chat-shaped fixture, not launcher CEF or a running GTA. Input-to-frame is a renderer proxy, not physical display latency. Sequential paths and host scheduling may affect timings.',rows};
 fs.writeFileSync(path.join(root,'tests/BROWSER_PERFORMANCE0433.json'),JSON.stringify(report,null,2)+'\n');
})().catch(error=>{console.error(error.stack);server.close();process.exitCode=1});
