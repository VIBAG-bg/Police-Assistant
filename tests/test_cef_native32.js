/* Real x86 LuaJIT + LuaSocket, the shared runtime verifier and real loopback
   HTTP. Only reviewed chat routines run in isolated V8 with test DOM/CEF. */
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
const crypto=require('node:crypto'),assert=require('node:assert/strict');
const release=path.resolve(__dirname,'..'),workspace=path.resolve(__dirname,'../../..');
const game=process.env.PA_QA_GAME || 'C:/Users/35987/AppData/Local/Exsellent Launcher/game';
const registry=JSON.parse(fs.readFileSync(path.join(release,'CEF_CONTRACT.json'),'utf8'));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const hudMain=path.join(game,'cef/assets/hud/main.js'),hudSha=sha(hudMain);
assert([
 'c458636ad5201c00aaf1e21e80bbf7fa74670734fcd0f66c812d495c893bd410',
 'd7526b3e76b4d9492407e77728be4ac8383b535600e62a3885fd1c785a4d29d2',
 'f6122cb757c72c38419708c490803912d039e945958225fdaa1be056e2a708a0',
].includes(hudSha),'Use a reviewed HUD fixture for executable tests');
const box=path.join(release,'tests/update-sandbox/cef-runtime-probe',crypto.randomUUID());fs.mkdirSync(box,{recursive:true});
const slash=p=>p.replaceAll('\\','/');const q=s=>JSON.stringify(slash(s));
const adapter=path.join(release,'cef/assets/hud/pa26-chat.js');
const tag='<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script>';
const originalHtml=fs.readFileSync(path.join(game,'cef/assets/hud/index.html'),'utf8').replace(tag,'');
assert(Buffer.byteLength(originalHtml)>32768,'Probe must use the real large HUD');
fs.writeFileSync(path.join(box,'index.html'),originalHtml);fs.copyFileSync(adapter,path.join(box,'pa26-chat.js'));
const control={enabled:true,accentEnabled:true,diagnostics:true,layoutIndicator:true,keyboardLayout:'RU',accent:'[Русский акцент]:',generation:1};
const setControl=values=>{Object.assign(control,values);fs.writeFileSync(path.join(box,'control.json'),JSON.stringify(control));};setControl({});
const lua=`local game=${q(game+'/')}
package.path=${q(path.join(release,'moonloader/lib/?.lua'))}..';'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local socket=require'socket';local json=require'cjson';local m=require'pa26_chat_bridge';local fs=require'pa26_config'.fs;local assets=require'pa26_cef_assets'
local base=${q(box+'/')};local state={};local function readControl()local raw=fs.read(base..'control.json');if raw then local ok,t=pcall(json.decode,raw);if ok then state=t end end end
local env={path=base,fs=fs,assetFs=assets.fs,json=json,token=function()return m.entropy(require'ffi')end,session=function()return'probe-session'end,
 settings=function()readControl();state.filters=state.filterPrefixes or{};return state end,layout=function()return state.keyboardLayout end,
 log=function(text)print(text);io.stdout:flush()end,message=function()local p=base..'incoming-count.json';local old=fs.read(p);local n=old and tonumber(old)or 0;assert(fs.write(p,tostring(n+1)))end,command=function()end}
local manualLib=require 'pa26_manual_chat';local converter=require('encoding').CP1251;local manualSent={};local b;local probeNow=0
env.manual=function(text,key)return manualQueue:offer(text,key)end
env.manualResult=function(key)return key and manualQueue.seen[key]or manualQueue.result end
local verifier=require('pa26_cef_compat').runtime(base..'MoonLoader',json,{cacheRoot=base:sub(1,-2),hudRoot=game..'cef/assets/hud'})
local checking=socket.gettime()
local review
repeat
    review=verifier:check(math.floor((socket.gettime()-checking)*1000))
    if not verifier.done then socket.sleep(.025)end
until verifier.done or socket.gettime()-checking>25
assert(verifier.done and review.allowed,json.encode(review))
assert(fs.write(base..'verified.json',json.encode({report=review,initialization_ms=(socket.gettime()-checking)*1000})))
env.compatibility=function(now)return verifier:check(now)end
local originalSettings=env.settings
env.settings=function()local result=originalSettings();if state.manualEnabled then result.manual_chat={enabled=true,max_parts=3,interval_ms=1200};result.rp_text=require('pa26_rp_settings').defaults();result.nickname='Officer_Name'end;return result end
manualQueue=manualLib.new({codec={encode=function(v)return converter:encode(v,'UTF-8')end,decode=function(v)return converter:decode(v,'UTF-8')end},
    context=function()local busy=b and b:busy(probeNow)or false;return {session='probe-session',alive=true,focused=true,paused=false,blocked=busy,chatActive=busy,ownWindow=false,dialogActive=false}end,
    now=function()return probeNow end,epoch=function()return state.generation end,interval=function()return 1200 end,busy=function()return false end,
    settings=function()return {enabled=true,max_parts=3,interval_ms=1200},require('pa26_rp_settings').defaults(),state.accentEnabled and state.accent or'',{},'Officer_Name'end,
    send=function(wire)assert(#wire<=127);manualSent[#manualSent+1]=converter:decode(wire,'UTF-8');assert(fs.write(base..'manual-sent.json',json.encode(manualSent)));return true end})
local function newBridge()
    local bridge=m.new(env)
    bridge.commands.pa26probe=function(args)
        assert(args=='fixture')
        local p=base..'local-count.json';local stored=fs.read(p);local count=tonumber(stored)or 0
        assert(fs.write(p,tostring(count+1)))
    end
    assert(bridge:start(),bridge.reason)
    return bridge
end
local generation=1;local forced=false;b=newBridge();local started=socket.gettime()
print('NATIVE32_READY');io.stdout:flush()
while not fs.exists(base..'stop')and socket.gettime()-started<90 do
 readControl();if state.generation~=generation then generation=state.generation;b:close();b=newBridge()end
 if state.forceClose and not forced then forced=true;b.server:close()end
 probeNow=math.floor((socket.gettime()-started)*1000);b:tick(probeNow);b:dispatch(probeNow);manualQueue:tick();socket.sleep(0.003)
end
b:close();verifier:close();print('NATIVE32_CLOSED');io.stdout:flush()
`;
const script=path.join(box,'bridge.lua');fs.writeFileSync(script,lua);
const child=cp.spawn('C:/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe',
 ['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'support/run_game_lua32.ps1'),'-Script',script],
 {windowsHide:true,cwd:workspace,stdio:['ignore','pipe','pipe']});
let output='',error='',exited=false;child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>error+=d);child.on('exit',()=>exited=true);
let checks=0;const eq=(a,b,m)=>{checks++;assert.deepEqual(a,b,m);};const ok=(v,m)=>{checks++;assert(v,m);};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,message,attempts=180){for(let i=0;i<attempts;i++){if(fn())return;if(exited)throw Error('Native probe exited: '+error);await wait(30);}throw Error(message);}
const timers=new Set(),intervals=new Set(),listeners={},sent=[],network=[],consoleCodes=[],incomingCallbacks={},incomingStored=[],incomingRendered=[];
const registrations=[],focusCalls=[];
let endpoint,offset=0,context,requestNumber=0,responseNumber=0,runtimeState,casesOpen=false;
async function refreshAdapter(){const after=requestNumber;await until(()=>responseNumber>after,'No fresh adapter metadata reply');}
const field={value:'',selectionStart:0,selectionEnd:0,tagName:'INPUT',
 focus(){context.document.activeElement=field;fire('focusin');},
 blur(){context.document.activeElement=null;fire('focusout');},
 setSelectionRange(a,b){this.selectionStart=a;this.selectionEnd=b;}};
function element(){
 const classes=new Set();
 return {appendChild(){},classList:{contains:name=>classes.has(name),add:name=>classes.add(name),remove:name=>classes.delete(name)}};
}
const panel=element(),container=element(),dialog=element();
const messageList={scrollTop:0,scrollHeight:52,scrollTo(options){this.scrollTop=options.top;}};
field.parentElement=panel;
const source=fs.readFileSync(hudMain,'utf8');
function fn(name){const start=source.indexOf('function '+name+'(');assert(start>=0);let depth=0,quote='',escaped=false;
 for(let i=source.indexOf('{',start);i<source.length;i++){const c=source[i];if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote='';continue;}
  if(c==="'"||c==='"'||c==='`'){quote=c;continue;}if(c==='{')depth++;if(c==='}'&&--depth===0)return source.slice(start,i+1);}throw Error('Incomplete HUD function');}
function loadEndpoint(){const p=path.join(box,'pa26-chat-endpoint.js');if(fs.existsSync(p))vm.runInContext(fs.readFileSync(p,'utf8'),context,{timeout:1000});}
function fire(name,event={}){event.target ||= field;event.preventDefault=()=>event.prevented=true;event.stopImmediatePropagation=()=>event.stopped=true;
 for(const cb of listeners[name]||[]){cb(event);if(event.stopped)break;}return event;}
function type(text){if(!context.isChatInputActive())context.showChatInput();field.value=text;field.selectionStart=field.selectionEnd=text.length;fire('input');}
// Native CEF key delivery and rendering are outside this harness.
async function submit(text){type(text);const e=fire('keydown',{key:'Enter'});if(!e.prevented){context.sendMessageToChat(field.value);context.hideChatInput(true);}await wait(90);return e;}
(async()=>{
 await until(()=>output.includes('NATIVE32_READY'),'Native bridge did not start',900);
 const verification=JSON.parse(fs.readFileSync(path.join(box,'verified.json'),'utf8'));
 const functionalFingerprint=verification.report.fingerprint;
 eq(verification.report.state,'CONTRACT_COMPATIBLE');
 eq(verification.report.sha256,hudSha);
 const verifiedState=verification.report.known?'KNOWN_VERIFIED':'RUNTIME_VERIFIED';
 ok([...registry.contract_profiles,...registry.known_versions].some(profile=>profile.fingerprint===functionalFingerprint));
 eq(fs.readFileSync(path.join(box,'index.html'),'utf8').replace(tag,''),originalHtml,'only the PA tag may change');
 eq(fs.readFileSync(path.join(box,'index.html.pa26-before-repair'),'utf8'),originalHtml,'real x86 backup is exact');
 eq(fs.readFileSync(path.join(box,'index.html'),'utf8').split(tag).length-1,1);
 ok(!fs.existsSync(path.join(box,'index.html.pa26-tmp')),'atomic replacement leaves no pending file');
 context=vm.createContext(Object.create(null),{codeGeneration:{strings:false,wasm:false}});
 Object.assign(context,{__testField:field,AbortController,performance:{now:()=>performance.now()+offset},
  __testPanel:panel,__testContainer:container,__testDialog:dialog,__testList:messageList,
  setTimeout(cb,ms){const h=setTimeout(cb,ms);timers.add(h);return h;},clearTimeout(h){clearTimeout(h);timers.delete(h);},
  setInterval(cb,ms){const h=setInterval(cb,ms);intervals.add(h);return h;},
  console:{warn:s=>consoleCodes.push(s)},
  document:{readyState:'loading',activeElement:null,getElementById(id){return {chatInputField:field,chatInput:panel,Dialog:dialog,chatMsgList:messageList}[id]??null;},
   querySelector(selector){return selector==='#casesUI:not([hidden])'&&casesOpen?{}:null;},
   addEventListener(name,cb){(listeners[name]||=[]).push(cb);},createElement(){return{style:{},setAttribute(){},remove(){}};},
   head:{appendChild(el){loadEndpoint();if(el.onload)el.onload();}}},
  saveMessageToStorage:(...a)=>incomingStored.push(a),renderChatMessage:(...a)=>incomingRendered.push(a),
  cef:{on(name,callback){registrations.push(name);incomingCallbacks[name]=callback;},set_focus(focused){focusCalls.push(focused);},emit(...args){sent.push(args);}},
  fetch:async(url,options)=>{const sequence=++requestNumber;endpoint=url;let r;try {r=await fetch(url,{...options,headers:{...options.headers,Origin:'sampcef://assets'}});}catch(e){consoleCodes.push('native_fetch:'+e.name+':'+(e.cause?.code||'none'));throw e;}
    network.push({status:r.status,cors:r.headers.get('access-control-allow-origin')});return {ok:r.ok,status:r.status,json:async()=>{
      const value=await r.json();responseNumber=sequence;runtimeState=value.compatibility?.state;return value;}};}});
 // Execute only reviewed chat routines and the isolated string decoder.
 const alias=/^const (_0x[0-9a-f]+)=(_0x[0-9a-f]+);/.exec(source);assert(alias,'Unknown HUD bootstrap');
 const decoder=fn(alias[2]),table=/const _0x[0-9a-f]+=(_0x[0-9a-f]+)\(\)/.exec(decoder);assert(table,'Unknown HUD string table');
 const prefixEnd=source.indexOf('const hudContainer=');assert(prefixEnd>0&&prefixEnd<10000);
 const bootstrap=source.slice(0,prefixEnd);assert(!/document\.|fetch\(|cef\./.test(bootstrap));
 vm.runInContext('window=globalThis;'+fn(table[1])+';'+decoder+';'+bootstrap,context,{timeout:1000});
 vm.runInContext(fs.readFileSync(adapter,'utf8'),context,{timeout:1000});
 const unrelatedDialogs=['isCarDealershipActive','isBlackjackGameActive','isDialogDailyTasksInterfaceActive',
   'isDiceGameActive','isGasStationInterfaceActive','isPerformanceInterfaceActive','isSlotMachineActive',
   'isPromocodeActive','isDeathScreen','isShowActive','isFactionRating','isAuthActive','isAdminToolsActive',
   'isTuningActive','isHouseSpawnSelectorActive'];
 const chatFunctions=['showCursor','hideCursor','showChat','hideChat','showChatInput','hideChatInput',
   'isChatInputActive','isDialogActive','sendMessageToChat','addChatMessage'];
 const incomingRegistration=[...source.matchAll(/typeof cef!==(_0x[0-9a-f]+)\(0x[0-9a-f]+\)&&\(cef\['on'\]\(\1\(0x[0-9a-f]+\),addChatMessage\),cef\['on'\]\(\1\(0x[0-9a-f]+\),addAdvertisement\)\);/g)];
 eq(incomingRegistration.length,1,'Find the actual HUD incoming event registration');
 vm.runInContext(`
 const chatInputField=__testField,chatInputElement=__testPanel,chatContainer=__testContainer,
       chatMsgList=__testList,dialogElement=__testDialog,MAX_INPUT_HISTORY_LENGTH=100;
 let chatInputHistory=[],historyIndex=0,inputBuffer='',chatFadeTimer;
 function saveInputMessageToStorage(){} function resetChatFadeTimer(){} function addAdvertisement(){}
 ${unrelatedDialogs.map(name=>`function ${name}(){return false;}`).join('\n')}
 ${chatFunctions.map(fn).join('\n')}
 ${incomingRegistration[0][0]}`,context,{timeout:1000});
 eq(registrations,['chat:messages','chat:addAdvertisement']);
 fire('DOMContentLoaded');await until(()=>network.length>0,'No real HTTP exchange');await context.PA26Chat.exchange();
 await until(()=>context.PA26Chat.submitted('Ready').text===control.accent+' Ready','Runtime handshake did not confirm');
 eq(runtimeState,verifiedState);
 eq(network[0].status,200);eq(network[0].cors,'sampcef://assets');
 for(let i=0;i<3;i++){
   context.showChatInput();
   eq(context.isChatInputActive(),true);eq(context.document.activeElement,field);eq(focusCalls.at(-1),true);
   context.hideChatInput();
   eq(context.isChatInputActive(),false);eq(context.document.activeElement,null);eq(focusCalls.at(-1),false);
 }
 context.hideChat();eq(container.classList.contains('hidden'),true);
 context.showChat();eq(container.classList.contains('hidden'),false);
 context.showChatInput();dialog.classList.add('active');
 eq(context.isDialogActive(),true);context.hideChatInput();eq(focusCalls.at(-1),true,'Game dialog retains CEF focus');
 dialog.classList.remove('active');context.hideCursor();eq(focusCalls.at(-1),false);
 if(hudSha.startsWith('f6122')){
   context.showChatInput();casesOpen=true;context.hideChatInput();
   eq(focusCalls.at(-1),true,'The new cases window keeps its original CEF focus');
   casesOpen=false;context.hideCursor();eq(focusCalls.at(-1),false);
 }
 incomingCallbacks['chat:messages'](17,'Fixture incoming.','INFO','Officer_Demo');await refreshAdapter();
 eq(incomingStored.at(-1),[17,'Fixture incoming.','INFO','Officer_Demo']);eq(incomingRendered.at(-1),incomingStored.at(-1));
 setControl({filterPrefixes:['BLOCK:']});await refreshAdapter();const renderedBefore=incomingRendered.length;
 incomingCallbacks['chat:messages'](18,'BLOCK: synthetic filter.','INFO','Officer_Demo');await refreshAdapter();
 eq(incomingRendered.length,renderedBefore,'Real incoming callback is filtered without altering the HUD function');
 await until(()=>fs.existsSync(path.join(box,'incoming-count.json'))&&Number(fs.readFileSync(path.join(box,'incoming-count.json'),'utf8'))>=2,'Incoming messages not observed by native bridge');
 setControl({filterPrefixes:[]});await refreshAdapter();incomingCallbacks['chat:messages'](19,'After filter.');await refreshAdapter();
 eq(incomingRendered.at(-1),[19,'After filter.',null,null],'Optional incoming metadata retains original defaults');

 const languagePages=new Set();
 async function languagePacket(chat=true){
  const challenge=endpoint.match(/\/([a-f0-9]{48})\/exchange$/u)[1];
  async function call(phase){return(await fetch(endpoint,{method:'POST',headers:{Origin:'sampcef://assets','Content-Type':'application/json'},
   body:JSON.stringify({schema:1,page:'language-probe',chat,dialog:false,busy:chat,events:[],compatibility:{protocol:2,challenge,phase,
    fingerprint:functionalFingerprint,capabilities:{dom:true,send:true,emit:true,incoming:true,focus:true}}})})).json();}
  if(!languagePages.has(challenge)){await call('hello');languagePages.add(challenge);}
  return call('confirmed');
 }
 for(const code of ['RU','EN','BG','UK','FIL']){setControl({keyboardLayout:code});eq((await languagePacket()).keyboardLayout,code);}
 setControl({layoutIndicator:false});eq((await languagePacket()).layoutIndicator,false);eq((await languagePacket()).keyboardLayout,undefined);
 setControl({layoutIndicator:true});eq((await languagePacket(false)).keyboardLayout,undefined);
 setControl({keyboardLayout:'<invalid>'});eq((await languagePacket()).keyboardLayout,undefined);
 setControl({keyboardLayout:'RU'});
 const chatRules=(await languagePacket()).chatText;eq(chatRules.version,1);eq(chatRules.dotCommands,true);eq(chatRules.skipBrackets,true);eq(chatRules.keyboardMap['к'],'r');eq(chatRules.keyboardMap['Ы'],'S');
 for(const [raw,expected]of [['.к Запрашиваю помощь.','/r Запрашиваю помощь.'],['.ыефеы','/stats'],['.unknown123 Параметры.','/unknown123 Параметры.'],[') Привет.',') Привет.'],['(Привет','(Привет']]){
   type(raw);eq(field.value,raw);await submit(raw);eq(sent.at(-1)[1],expected);
 }
 setControl({accentEnabled:false});await refreshAdapter();await submit('.ыефеы');eq(sent.at(-1)[1],'/stats');
 setControl({chat_dot_commands:false});await refreshAdapter();await submit('.ыефеы');eq(sent.at(-1)[1],'.ыефеы');
 setControl({chat_dot_commands:true,accentEnabled:true});await refreshAdapter();
 type('Привет.');eq(field.value,'Привет.','the draft stays native until submission');await submit('Привет.');eq(sent.at(-1),['HandleHudSendMessage',control.accent+' Привет.']);
 // Reproduce a launcher removing the tag/endpoint while the adapter page exists.
 fs.writeFileSync(path.join(box,'index.html'),originalHtml);fs.unlinkSync(path.join(box,'pa26-chat-endpoint.js'));
 await until(()=>fs.readFileSync(path.join(box,'index.html'),'utf8').includes(tag)&&fs.existsSync(path.join(box,'pa26-chat-endpoint.js')),'Automatic asset repair did not run');
 loadEndpoint();await context.PA26Chat.exchange();await submit('.к После восстановления.');eq(sent.at(-1)[1],'/r После восстановления.');
 eq(fs.readFileSync(path.join(box,'index.html'),'utf8').replace(tag,''),originalHtml);
 const beforeFault=fs.readFileSync(path.join(box,'pa26-chat-endpoint.js'),'utf8');setControl({forceClose:true});
 await until(()=>fs.readFileSync(path.join(box,'pa26-chat-endpoint.js'),'utf8')!==beforeFault,'Failed listener did not restart');
 loadEndpoint();await until(()=>context.PA26Chat.submitted('Проверка связи.').text===control.accent+' Проверка связи.','No active chat config after listener restart');
 type('Проверка связи.');eq(field.value,'Проверка связи.','reconnection never rewrites the draft');
 await submit('После обрыва.');eq(sent.at(-1)[1],control.accent+' После обрыва.');
 ok(output.includes('socket_accept'),'real socket failure must be diagnosed');
 for(const text of ['/me оглянулся.','/do Дверь открыта.','/r Доклад.','/b Текст.']){await submit(text);eq(sent.at(-1)[1],text);}
 setControl({local_tag:'[SIGMA]:',manual_radio_prefix:true});await refreshAdapter();
 const radioRules=(await languagePacket()).chatText.radioPrefix;eq(radioRules.enabled,true);eq(radioRules.localTag,'[SIGMA]:');
 for(const[raw,expected]of [['/r Доклад.','/r [SIGMA]: Доклад.'],['.к Доклад.','/r [SIGMA]: Доклад.'],
  ['/r [SIGMA]: Доклад.','/r [SIGMA]: Доклад.'],['/rn Текст.','/rn Текст.'],['/r','/r']]){
  await submit(raw);eq(sent.at(-1)[1],expected);
 }
 setControl({manual_radio_prefix:false});await refreshAdapter();await submit('/r Выключено.');eq(sent.at(-1)[1],'/r Выключено.');
 setControl({manual_radio_prefix:true,local_tag:''});await refreshAdapter();await submit('/r Пусто.');eq(sent.at(-1)[1],'/r Пусто.');
 const count=sent.length;await submit('/pa26unknown');eq(sent.length,count,'unknown PA commands stay local');
 await submit('/pa26probe fixture');eq(sent.length,count,'registered PA commands stay local');
 const localCount=path.join(box,'local-count.json');
 await until(()=>fs.existsSync(localCount),'Registered PA command was not dispatched through the real bridge');
 await refreshAdapter();eq(fs.readFileSync(localCount,'utf8'),'1','The local command is dispatched once');
 setControl({accentEnabled:false});await refreshAdapter();await submit('Без акцента.');eq(sent.at(-1)[1],'Без акцента.');
 setControl({accentEnabled:true});await refreshAdapter();
 const capacity=127-control.accent.length-1;await submit('Я'.repeat(capacity));eq(sent.at(-1)[1].length,127);
 const before=sent.length;eq((await submit('Я'.repeat(capacity+1))).prevented,true);eq(sent.length,before);
 const preflight=await fetch(endpoint,{method:'OPTIONS',headers:{Origin:'sampcef://assets','Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'content-type','Access-Control-Request-Private-Network':'true'}});
 eq(preflight.status,204);eq(preflight.headers.get('access-control-allow-private-network'),'true');
 eq((await fetch(endpoint,{method:'OPTIONS',headers:{Origin:'null'}})).status,204);
 eq((await fetch(endpoint,{method:'POST',headers:{Origin:'https://unrelated.example','Content-Type':'application/json'},body:'{}'})).status,403);
 eq((await fetch(endpoint.replace(/\/[a-f0-9]{48}\//u,'/invalid/'),{method:'POST',headers:{Origin:'sampcef://assets','Content-Type':'application/json'},body:'{}'})).status,403);
 eq((await fetch(endpoint,{method:'POST',headers:{Origin:'sampcef://assets','Content-Type':'application/json'},body:'{}'})).status,400);
 const old=fs.readFileSync(path.join(box,'pa26-chat-endpoint.js'),'utf8');setControl({generation:2});
 await until(()=>fs.readFileSync(path.join(box,'pa26-chat-endpoint.js'),'utf8')!==old,'Native bridge did not restart');
 loadEndpoint();await refreshAdapter();await submit('После перезапуска.');eq(sent.at(-1)[1],control.accent+' После перезапуска.');
 setControl({manualEnabled:true});await refreshAdapter();
 const longManual='синяя куртка и чёрные брюки '.repeat(8).trim();
 const manualLines=()=> {try{return JSON.parse(fs.readFileSync(path.join(box,'manual-sent.json'),'utf8'));}catch(_){return [];}};
 for(const head of ['','/me ','/do ','/try ','/r ','/rn ','/f ','/fn ','/d ','/df ','/n ','/todo ']) {
  const originalCount=sent.length,oldCount=manualLines().length;
  const raw=head+longManual+(head==='/todo ' ? '*обращаясь к диспетчеру' : '');
  const prepared=context.PA26Chat.submitted(raw);eq(prepared.parts.length,3);
  await submit(raw);eq(sent.length,originalCount,'Real HUD emit is intercepted for an owned manual submission');
  await until(()=>manualLines().length===oldCount+prepared.parts.length,'Native queue did not send all manual parts');
  eq(manualLines().slice(oldCount),Array.from(prepared.parts),'Real x86 Lua and browser split exactly the same text');
  await until(()=>!context.PA26Chat.manualBusy(),'Completion receipt was not received');
 }
 const badTodo=manualLines().length;const todoReject=await submit('/todo текст*'+'я'.repeat(61));eq(todoReject.prevented,true);eq(manualLines().length,badTodo);
 const unchanged=manualLines().length;const tooLong='слово '.repeat(100);const rejected=await submit(tooLong);eq(rejected.prevented,true);eq(manualLines().length,unchanged);
 setControl({manualEnabled:false});await refreshAdapter();
 type('Не потерять.');fs.writeFileSync(path.join(box,'stop'),'stop');await until(()=>exited,'Native helper did not close');offset+=2500;
 for(let i=0;i<3;i++)await context.PA26Chat.exchange();context.PA26Chat.prepare();eq(field.value,'Не потерять.');
 ok(output.includes('port_type=string'));ok(output.includes('browser_exchange'));ok(output.includes('browser_ready'));ok(!output.includes(control.accent),'native diagnostics must not contain the prefix');
 eq(registrations,['chat:messages','chat:addAdvertisement'],'Reconnection never registers duplicates');
 const result={status:'passed',checks,real_x86_luajit:true,real_installed_luasocket:true,real_loopback_http:true,
  runtime_verifier:verification,runtime_handshake:verifiedState,real_hud_send_function_in_isolated_v8:true,real_hud_incoming_registration:true,real_hud_focus_functions:true,
  chat_field_is_test_double:true,layout_packet_values_are_test_doubles:true,gta_launched:false,actual_game_server_contacted:false,manual_multiline_native_ipc:true,
  manual_sha256:sha(path.join(release,'moonloader/lib/pa26_manual_chat.lua')),rp_sha256:sha(path.join(release,'moonloader/lib/pa26_rp_text.lua')),adapter_sha256:sha(adapter),bridge_sha256:sha(path.join(release,'moonloader/lib/pa26_chat_bridge.lua')),chat_text_sha256:sha(path.join(release,'moonloader/lib/pa26_chat_text.lua')),test_sha256:sha(__filename),
  assets_sha256:sha(path.join(release,'moonloader/lib/pa26_cef_assets.lua')),real_large_hud_bytes:Buffer.byteLength(originalHtml),real_atomic_replace:true,
  hud_main_sha256:hudSha,cef_client_sha256:sha(path.join(game,'cef/cef-client.dll')),
  host_sha256:sha(path.join(__dirname,'support/run_game_lua32.ps1')),
  lua51_sha256:sha(path.join(game,'lua51.dll')),socket_core_sha256:sha(path.join(game,'MoonLoader/lib/socket/core.dll'))};
 fs.writeFileSync(path.join(__dirname,'CEF_NATIVE32_RESULTS.json'),JSON.stringify(result,null,2)+'\n');
 console.log('Native x86 IPC + real HUD function: '+checks+' checks passed; GTA not launched.');
})().catch(e=>{console.error(e.message);console.error('Native diagnostics:',output.trim(),error.trim(),consoleCodes.join('; '));process.exitCode=1;}).finally(async()=>{
 if(context?.PA26Chat)context.PA26Chat.stop();for(const h of intervals)clearInterval(h);for(const h of timers)clearTimeout(h);
 fs.writeFileSync(path.join(box,'stop'),'stop');if(!exited){for(let i=0;i<60&&!exited;i++)await wait(50);if(!exited)child.kill();}
});
