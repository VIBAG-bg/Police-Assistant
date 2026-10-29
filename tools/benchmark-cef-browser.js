/* Isolated Chromium measurement. No game, launcher code or live server. */
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),adapter=path.resolve(process.argv[2]||path.join(root,'cef/assets/hud/pa26-chat.js'));
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Users/35987/AppData/Local/ms-playwright/chromium-1067/chrome-win/chrome.exe'});
 const rows=[];
 try{for(const enabled of [false,true]){
  const page=await browser.newPage();await page.setContent('<style>body{font:16px sans-serif}.active{display:flex}input{width:600px}</style><div id="chatInput" class="active"><input id="chatInputField" maxlength="127"><button id="SendMsgButton">Send</button></div>');
  await page.evaluate(()=>{
   const originalNow=performance.now.bind(performance);window.measureNow=originalNow;
   window.stats={style_reads:0,rect_reads:0,fetches:0,value_writes:0,caret_writes:0};
   const g=window.getComputedStyle;window.getComputedStyle=function(...args){stats.style_reads++;return g(...args)};
   const r=Element.prototype.getClientRects;Element.prototype.getClientRects=function(...args){stats.rect_reads++;return r.apply(this,args)};
   const s=HTMLInputElement.prototype.setSelectionRange;HTMLInputElement.prototype.setSelectionRange=function(...args){stats.caret_writes++;return s.apply(this,args)};
   window.cef={emit(){},on(){},set_focus(){}};window.isDialogActive=()=>false;window.sendMessageToChat=t=>cef.emit('HandleHudSendMessage',t);
   window.fetch=async(_url,options)=>{stats.fetches++;const req=JSON.parse(options.body);return{ok:true,json:async()=>({schema:1,ack:req.events.at(-1)?.id||0,session:'benchmark',enabled:true,accentEnabled:true,accent:'[Русский акцент]:',layoutIndicator:true,keyboardLayout:'RU',filters:[],localCommands:[],chatText:{version:1,keyboardMap:{},manual:{enabled:true,maxParts:3,marker:'...',bodyLimit:90,intervalMs:1500}}})}};
  });
  if(enabled){await page.addScriptTag({path:adapter});await page.evaluate(()=>PA26Chat.endpoint('http://127.0.0.1:39001/'+'a'.repeat(48)+'/exchange'))}
  await page.locator('#chatInputField').focus();await page.waitForTimeout(200);
  const result=await page.evaluate(async()=>{
   const input=document.getElementById('chatInputField'),samples=[];const initial={...stats};
   const chars='набор тЕкста ijk t 123 ←→';
   for(let i=0;i<100;i++){
    const key=chars[i%chars.length],t=measureNow();
    input.dispatchEvent(new KeyboardEvent('keydown',{key,code:/[0-9]/.test(key)?'Digit'+key:'KeyA',bubbles:true}));
    input.value+=key;input.dispatchEvent(new InputEvent('input',{data:key,inputType:'insertText',bubbles:true}));
    input.dispatchEvent(new KeyboardEvent('keyup',{key,bubbles:true}));
    samples.push(measureNow()-t);await new Promise(r=>setTimeout(r,1));
   }
   input.setSelectionRange(4,18);const before=input.value;await new Promise(r=>setTimeout(r,180));
   samples.sort((a,b)=>a-b);return{events:100,p50_ms:samples[50],p95_ms:samples[95],max_ms:samples[99],
    operations:Object.fromEntries(Object.keys(stats).map(k=>[k,stats[k]-initial[k]])),
    selection_preserved:input.selectionStart===4&&input.selectionEnd===18,text_preserved:input.value===before};
  });rows.push({adapter:enabled,...result});await page.close();
 }}finally{await browser.close()}
 const report={status:'measured',browser:'isolated Chromium 112',adapter_sha256:crypto.createHash('sha256').update(fs.readFileSync(adapter)).digest('hex'),rows,game_started:false,live_cef_measured:false};
 const target=process.argv[3]||path.join(root,'tests/CEF_BROWSER_BENCHMARK.json');fs.writeFileSync(target,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exitCode=1});
