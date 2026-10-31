/* Offline tests: a fake CEF page, no GTA, external network or copied launcher JS. */
'use strict';
const assert = require('node:assert/strict');
const install = require('../cef/assets/hud/pa26-chat.js');
let checks = 0;
function eq(a,b,message) { checks++; assert.deepEqual(a,b,message); }
const prefix = '[Русский акцент]:';
// Small test fixture only. Production receives the complete map from Lua.
const chatText = {version:1,skipBrackets:true,dotCommands:true,keyboardMap:{к:'r',К:'R',ы:'s',Ы:'S',е:'t',Е:'T',ф:'a',Ф:'A'}};
const endpoint = 'http://127.0.0.1:39001/' + 'a'.repeat(48) + '/exchange';
const flush = () => new Promise(resolve => setImmediate(resolve));
async function page(delayed=false) {
  const stats={textReads:0,textWrites:0,styleReads:0,rectReads:0,endpointLoads:0};
  const observers=[], fieldListeners={};
  let now = 0, sequence = 0;
  const listeners = {}, callbacks = {}, sent = [], observed = [], requests = [], timers = new Map(),warnings=[];
  const panel = {classList: {contains: () => panel.open},open: true,children: [],
    appendChild(el) {this.insertBefore(el,null);},
    insertBefore(el,next) {const index=this.children.indexOf(next);this.children.splice(index<0?this.children.length:index,0,el);el.parentElement=this;el.isConnected=true;elements[el.id]=el;}};
  const elements = {};
  const input = elements.chatInputField = {id:'chatInputField',value: '', selectionStart: 0, selectionEnd: 0, tagName: 'INPUT',
    getClientRects() {stats.rectReads++;return this.collapsed ? [] : [{}];},
    addEventListener(name,cb) {(fieldListeners[name] ||= []).push(cb);},
    selectionDirection: 'none', caretWrites: 0, parentElement: panel,
    setSelectionRange(start,end,direction) {this.caretWrites++;this.selectionStart=start;this.selectionEnd=end;this.selectionDirection=direction;}};
  let inputValue='';Object.defineProperty(input,'value',{get(){stats.textReads++;return inputValue;},set(value){stats.textWrites++;inputValue=value;}});
  elements.chatInput = panel;
  const send={id:'SendMsgButton',parentElement:panel};panel.children.push(input,send);
  Object.defineProperty(input,'nextSibling',{get(){return panel.children[panel.children.indexOf(this)+1]||null;}});
  const document = {readyState: 'loading', activeElement: input,
    getElementById(id) {return elements[id] || null;},
    createElement(tag) {return {tagName:tag.toUpperCase(),style: {}, attributes:{},
      setAttribute(k,v) {this.attributes[k]=v;},remove() {
        if(this.parentElement){const index=this.parentElement.children.indexOf(this);if(index>=0)this.parentElement.children.splice(index,1);}
        if(elements[this.id]===this)delete elements[this.id];this.isConnected=false;this.parentElement=null;
      }};},
    addEventListener(name,cb,capture) {cb.capture=!!capture;(listeners[name] ||= []).push(cb);},
    head: {appendChild(el) {stats.endpointLoads++;if (el.onload) el.onload();}}};
  const root = {document, performance: {now: () => now}, Date: {now: () => now},Math: {random: () => 0.1234},
    getComputedStyle(el) {stats.styleReads++;return {display: 'flex',visibility: 'visible',opacity: String(el.opacity ?? (el === panel && !panel.open ? 0 : 1))};},
    console: {warn(value) {warnings.push(value);}},
    MutationObserver:class {constructor(cb){this.cb=cb;observers.push(this);}observe(target,options){this.target=target;this.options=options;this.live=true;}disconnect(){this.live=false;}},
    AbortController, setTimeout(cb,ms) {timers.set(++sequence,{cb,ms,at:now+ms});return sequence;},clearTimeout(id) {timers.delete(id);},
    setInterval(cb,ms) {timers.set(++sequence,{cb,ms,interval: true});return sequence;},
    cef: {on(name,cb) {callbacks[name] = cb;},emit(...args) {sent.push(args);return this;},set_focus() {}},
    isDialogActive: () => false};
  let config = {schema:1,session:'one',enabled:true,accentEnabled:true,accent:prefix,filters:[],localCommands:['pa26','pa26demo'],chatText};
  let failure = false,responseStatus=200,malformed=false,hang=false;
  root.fetch = async (url, options) => {
    requests.push({url,options});if(failure)throw Error('offline');
    if(hang)return new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(Error('timeout')),{once:true}));
    const request=JSON.parse(options.body);observed.push(...request.events);
    return {ok:responseStatus===200,status:responseStatus,json:async()=>malformed?{schema:0}:({...config,ack:request.events.at(-1)?.id || 0})};
  };
  const api = install(root);
  root.cef.on('chat:messages', (...args) => callbacks.rendered.push(args));callbacks.rendered=[];
  root.sendMessageToChat = text => {if(delayed)root.setTimeout(()=>root.cef.emit('HandleHudSendMessage',text),50);else root.cef.emit('HandleHudSendMessage',text);panel.open=false;};
  function fire(name,event={}) {
    event.target ||= input; event.key ||= '';
    event.preventDefault=()=>event.prevented=true;event.stopImmediatePropagation=()=>event.stopped=true;event.stopPropagation=()=>event.bubbleStopped=true;
    for(const cb of (listeners[name]||[]).filter(cb=>cb.capture)) {cb(event);if(event.stopped)break;}
    if(!event.stopped && event.target===input)for(const cb of fieldListeners[name]||[]) {cb(event);if(event.stopped)break;}
    if(!event.stopped && !event.bubbleStopped)for(const cb of (listeners[name]||[]).filter(cb=>!cb.capture)) {cb(event);if(event.stopped)break;}
    return event;
  }
  fire('DOMContentLoaded');api.endpoint(endpoint);await flush();
  return {root,api,input,panel,sent,observed,requests,callbacks,fire,timers,warnings,elements,observers,stats,
    mutate(){for(const o of observers)if(o.live)o.cb([{type:'attributes'}]);},
    type(text,cursor=text.length) {panel.open=true;input.value=text;input.selectionStart=input.selectionEnd=cursor;fire('input');},
    async config(value) {config={...config,...value};await api.exchange();await flush();},
    async exchange() {await api.exchange();await flush();},
    async enter() {const e=fire('keydown',{key:'Enter'});if(!e.prevented)root.sendMessageToChat(input.value);await flush();return e;},
    time(ms) {now+=ms;}, runTimers(ms) {now+=ms;for(const[id,timer]of [...timers])if(!timer.interval&&timer.at<=now){timers.delete(id);timer.cb();}}, offline(value) {failure=value;},
    status(value){responseStatus=value;},malformed(value){malformed=value;},hang(value){hang=value;}};
}
(async () => {
  let p=await page();p.type('Привет');eq(p.input.value,'Привет');eq(p.input.selectionStart,p.input.value.length);
  const caret=p.input.caretWrites;p.api.prepare();eq(p.input.caretWrites,caret,'stable input must not reset the caret');
  await p.enter();eq(p.sent,[['HandleHudSendMessage',prefix+' Привет']]);
  for(const text of ['/me оглянулся.','/do Дверь открыта.',' /r Доклад.','/b Привет','!r Доклад.']) {
    p.type(text);eq(p.input.value,text);await p.enter();eq(p.sent.at(-1)[1],text);
  }
  p.type('Текст');p.type(prefix+' /me действие.');eq(p.input.value,prefix+' /me действие.');
  p.type('Один');await p.config({accent:'[Акцент]:'});eq(p.input.value,'Один');
  await p.config({accentEnabled:false});eq(p.input.value,'Один');await p.enter();eq(p.sent.at(-1)[1],'Один');
  await p.config({accentEnabled:true,accent:prefix});p.type(prefix+' Уже есть.');eq(p.input.value,prefix+' Уже есть.');
  p.type('');eq(p.input.value,'');p.type('   ');eq(p.input.value,'   ');
  p=await page();p.type('Привет',2);eq(p.input.selectionStart,2);eq(p.input.selectionEnd,p.input.selectionStart);
  const capacity=127-prefix.length-1;
  p.type('Я'.repeat(capacity));eq(p.api.wireSize(p.api.submitted(p.input.value).text),127);eq((await p.enter()).prevented,undefined);
  p.type('Я'.repeat(capacity+1));const before=p.sent.length;eq((await p.enter()).prevented,true);eq(p.sent.length,before);eq(p.input.value,'Я'.repeat(capacity+1));
  p.type('Привет 🙂');eq((await p.enter()).prevented,true);eq(p.sent.length,before);
  p.type('/me '+ 'Я'.repeat(160));eq((await p.enter()).prevented,undefined,'commands keep the original chat behavior');
  eq(p.api.wireSize('ЁёЇїҐґЄєІі€№—–'),14);eq(p.api.wireSize('\n'),null);eq(p.api.wireSize('中'),null);
  p=await page();p.fire('compositionstart');p.type('При');eq(p.input.value,'При');p.fire('compositionend');eq(p.input.value,'При');
  const count=p.requests.length;p.api.endpoint('http://example.com/a');p.api.endpoint('http://127.0.0.1:65536/'+'b'.repeat(48)+'/exchange');await flush();eq(p.requests.length,count);
  p.type('/pa26demo');const sentBefore=p.sent.length;await p.enter();await p.exchange();eq(p.sent.length,sentBefore,'local PA command must never reach the game server');
  eq(p.observed.some(e=>e.kind==='local'&&e.text==='/pa26demo'),true);
  for(const alias of ['add','cuff','ADD']) {
    await p.config({localCommands:['pa26demo','add','cuff']});p.type('/'+alias+' 37');const beforeAlias=p.sent.length;
    await p.enter();await p.exchange();eq(p.sent.length,beforeAlias,'configured short names are held locally on first submit');
    eq(p.observed.some(e=>e.kind==='local'&&e.text==='/'+alias+' 37'),true);
  }
  p.type('/tazer');await p.enter();await p.exchange();eq(p.sent.at(-1),['HandleHudSendMessage','/tazer']);eq(p.observed.some(e=>e.kind==='command'&&e.text==='/tazer'),true);
  // Another script's direct CEF emit has no manual-submit ticket and stays unchanged.
  p.root.cef.emit('HandleHudSendMessage','Автоматическая реплика.');eq(p.sent.at(-1)[1],'Автоматическая реплика.');
  await p.config({filters:['Объявление:']});p.callbacks['chat:messages'](12,'Объявление: текст','INFO');await p.exchange();eq(p.callbacks.rendered.length,0);eq(p.observed.some(e=>e.kind==='message'),true);
  p.callbacks['chat:messages'](13,'John_Smith достал паспорт и показал его Victor_Auditore','ME');await p.exchange();eq(p.callbacks.rendered.length,1);
  await p.config({enabled:false});p.type('Без адаптера');eq(p.input.value,'Без адаптера');p.callbacks['chat:messages'](1,'Объявление: снова');eq(p.callbacks.rendered.length,2);
  p=await page();p.type('Сохрани текст');p.offline(true);p.time(2100);
  await p.enter();eq(p.sent.at(-1)[1],'Сохрани текст','expired PA session must remove its owned prefix before sending');
  p=await page();p.type('Не потерять');await p.config({accentEnabled:false});p.api.stop();eq(p.input.value,'Не потерять');
  // The real HUD emits 50 ms after closing input: rapid submits keep separate tickets.
  p=await page(true);p.type('/pa26demo');await p.enter();p.type('/r Доклад.');await p.enter();await p.config({session:'two'});
  p.runTimers(60);await flush();await p.exchange();eq(p.sent,[['HandleHudSendMessage','/r Доклад.']]);
  eq(p.observed.some(e=>e.kind==='local'&&e.session==='one'),true,'queued actions keep their original connection generation');
  eq(p.observed.some(e=>e.kind==='command'&&e.text==='/r Доклад.'&&e.session==='one'),true);
  p=await page(true);p.type('/pa26demo');await p.enter();p.time(2100);p.runTimers(1);await flush();eq(p.sent.length,0,'an expired PA command must never leak to the server');
  p=await page();p.panel.open=false;eq(p.api.inputState().busy,false,'hidden chat input can retain DOM focus without blocking F9');
  p.panel.opacity=0.5;eq(p.api.inputState().busy,false,'closing animation must not keep a hidden chat active');
  p.panel.open=true;p.panel.opacity=0;eq(p.api.inputState().chat,true,'opening animation still owns chat input');
  p.panel.open=false;delete p.panel.opacity;
  p.root.cef.set_focus(true);eq(p.api.inputState().busy,true);p.root.cef.set_focus(false);eq(p.api.inputState().busy,false);
  p.panel.open=true;eq(p.api.inputState().chat,true);p.panel.open=false;p.input.hidden=true;eq(p.api.inputState().busy,false);
  const other={tagName:'INPUT',parentElement:{opacity:0}};p.root.document.activeElement=other;
  eq(p.api.inputState().busy,false,'transparent ancestor must not leave a hidden form blocking F9');
  other.parentElement.opacity=1;p.fire('focusin',{target:other});eq(p.api.inputState().busy,true,'visible focused form keeps priority');
  // Diagnostic metadata contains no entered text, prefix or secret URL.
  p=await page();p.type('Служебная проверка.');await p.enter();await p.exchange();
  const diagnostic=JSON.parse(p.requests.at(-1).options.body).diagnostics;
  eq(diagnostic.field,true);eq(diagnostic.sendHook,true);eq(diagnostic.accentConfigured,true);
  eq(diagnostic.applied>=1,true);eq(diagnostic.submitted>=1,true);
  eq(JSON.stringify(diagnostic).includes(prefix),false);eq(JSON.stringify(diagnostic).includes('Служебная'),false);
  // Explicit off remains off after connection loss and expiring configuration.
  await p.config({diagnostics:false});await p.exchange();eq(JSON.parse(p.requests.at(-1).options.body).diagnostics,undefined);
  p.offline(true);for(let i=0;i<5;i++)await p.exchange();eq(p.warnings.length,0);
  // Failed exchanges are reported once per reason, without URL or player text.
  p=await page();p.status(403);await p.exchange();await p.exchange();eq(p.warnings,['[PA26 CEF] exchange_failed: http_403']);
  p.status(200);p.malformed(true);await p.exchange();eq(p.warnings.at(-1),'[PA26 CEF] exchange_failed: bad_response');
  p.malformed(false);await p.exchange();p.type('Снова работает.');eq(p.input.value,'Снова работает.');
  // The abort timeout clears a pending exchange so a later request can recover.
  p=await page();p.hang(true);const waiting=p.exchange();p.runTimers(1600);await waiting;eq(p.warnings.at(-1),'[PA26 CEF] exchange_failed: network');
  p.hang(false);await p.exchange();p.type('После таймаута.');eq(p.input.value,'После таймаута.');
  // Burst input remains bounded; rendering of ordinary incoming chat continues.
  p=await page();for(let i=0;i<100;i++)p.callbacks['chat:messages'](1,'Строка '+i);
  await flush();for(let i=0;i<6;i++)await p.exchange();eq(p.callbacks.rendered.length,100);
  eq(p.requests.every(r=>JSON.parse(r.options.body).events.length<=24),true);eq(new Set(p.observed.map(e=>e.id)).size<=65,true);
  // A closed input with retained focus and stale native state cannot steal F9.
  p=await page();p.panel.open=false;p.input.disabled=true;eq(p.api.inputState().busy,false);
  p.input.disabled=false;p.input.isConnected=false;eq(p.api.inputState().busy,false);
  eq(p.requests.every(r=>r.url.startsWith('http://127.0.0.1:')&&r.options.method==='POST'),true);
  // Input-language badge uses trusted bridge metadata; no extra input handlers.
  p=await page();p.type('/me оглянулся.',4);
  const value=p.input.value,selection=p.input.selectionStart,writes=p.input.caretWrites;
  const controls=()=>p.panel.children.filter(el=>el.id!=='pa26-chat-notice');
  await p.config({layoutIndicator:true,keyboardLayout:'RU'});
  let badge=p.elements['pa26-chat-layout'];eq(badge.textContent,'RU');eq(badge.tagName,'SPAN');
  eq(controls().map(el=>el.id),['chatInputField','pa26-chat-layout','SendMsgButton']);
  eq(badge.style.pointerEvents,'none');eq(badge.style.flex,'0 0 auto');eq(badge.attributes['aria-label'],'Язык ввода: RU');
  eq(badge.style.color,'var(--white, #fff)','the HUD parent does not supply a readable inherited text color');
  eq(p.input.value,value);eq(p.input.selectionStart,selection);eq(p.input.caretWrites,writes);
  await p.config({keyboardLayout:'EN'});eq(p.elements['pa26-chat-layout'],badge);eq(badge.textContent,'EN');
  eq(controls().length,3,'switching languages must not duplicate the badge');
  for(const code of ['BG','UK','JA','FIL']){await p.config({keyboardLayout:code});eq(badge.textContent,code);}
  await p.config({layoutIndicator:false});eq(p.elements['pa26-chat-layout'],undefined);eq(controls().length,2);
  await p.config({layoutIndicator:true,keyboardLayout:'RU',accentEnabled:false});eq(p.elements['pa26-chat-layout'].textContent,'RU','layout is independent from RP accent');
  p.panel.open=false;p.api.updateLayoutBadge();eq(p.elements['pa26-chat-layout'],undefined);
  p.panel.open=true;p.api.updateLayoutBadge();eq(p.elements['pa26-chat-layout'].textContent,'RU');
  p.input.collapsed=true;p.mutate();p.api.updateLayoutBadge();eq(p.elements['pa26-chat-layout'],undefined);p.input.collapsed=false;p.mutate();
  for(const code of [null,undefined,'','ru','R','RUSSIAN','РУ','RU\n','<img>',123]){
    await p.config({keyboardLayout:code});eq(p.elements['pa26-chat-layout'],undefined,'invalid or missing language stays hidden');
  }
  await p.config({keyboardLayout:'RU'});p.offline(true);p.time(2100);
  for(const timer of p.timers.values())if(timer.interval&&timer.ms===750)timer.cb();
  eq(p.elements['pa26-chat-layout'],undefined,'stale badge disappears even while a request is pending');await flush();
  p.offline(false);await p.exchange();eq(p.elements['pa26-chat-layout'].textContent,'RU','connection recovers');
  await p.config({enabled:false});eq(p.elements['pa26-chat-layout'],undefined);
  await p.config({enabled:true});eq(p.elements['pa26-chat-layout'].textContent,'RU');
  // HUD input replacement reattaches just one badge to the new parent.
  const otherPanel={...p.panel,children:[],insertBefore:p.panel.insertBefore};
  p.input.parentElement=otherPanel;otherPanel.children.push(p.input);p.api.updateLayoutBadge();
  badge=p.elements['pa26-chat-layout'];eq(badge.parentElement,otherPanel);eq(p.panel.children.filter(el=>el.id==='pa26-chat-layout').length,0);
  p.api.stop();eq(p.elements['pa26-chat-layout'],undefined);await p.exchange();eq(p.elements['pa26-chat-layout'],undefined);
  // An in-flight exchange cannot resurrect an indicator after stop().
  p=await page();let finish;
  p.root.fetch=()=>new Promise(resolve=>finish=resolve);const pending=p.exchange();p.api.stop();
  finish({ok:true,json:async()=>({schema:1,ack:0,enabled:true,layoutIndicator:true,keyboardLayout:'RU'})});await pending;
  eq(p.elements['pa26-chat-layout'],undefined);eq(p.input.value,'');
  // Manual dot commands: edit freely, convert only on submit, preserve arguments.
  for(const [raw,expected] of [['.к Запрашиваю помощь.','/r Запрашиваю помощь.'],['.ыефеы','/stats'],
      ['.К  Текст.  ','/R  Текст.  '],['.ЫЕФЕЫ','/STATS'],['.unknown123 _текст_ /r .к','/unknown123 _текст_ /r .к']]) {
    p=await page();p.type(raw);eq(p.input.value,raw);const n=p.sent.length;await p.enter();eq(p.sent.length,n+1);eq(p.sent.at(-1)[1],expected);
  }
  p=await page();p.type('.ы');eq(p.input.value,'.ы');p.type('.ыефеы');eq(p.input.value,'.ыефеы');
  p.root.sendMessageToChat(p.input.value);eq(p.sent.at(-1)[1],'/stats','send icon follows the same conversion');
  for(const text of ['.','..','...','.5','.123','. Привет','.foo.com','.r/37','.r,','.r-1','._r','.r🙂']) {
    p=await page();p.type(text);eq(p.input.value,text);await p.enter();eq(p.sent.at(-1)[1],text);
  }
  p=await page();for(const text of [' .ыефеы','Привет.','Текст .к']) {p.type(text);await p.enter();eq(p.sent.at(-1)[1],prefix+' '+text);}
  p.type('．ыефеы');const unicodeCount=p.sent.length;eq((await p.enter()).prevented,true);eq(p.sent.length,unicodeCount);
  p=await page();for(const text of ['(Привет',') Привет','   ) Привет','\t( Привет']) {
    p.type(text);eq(p.input.value,text);await p.enter();eq(p.sent.at(-1)[1],text);
  }
  p.type('Привет (текст).');await p.enter();eq(p.sent.at(-1)[1],prefix+' Привет (текст).');
  await p.config({chatText:{...chatText,skipBrackets:false}});p.type(') Привет.');await p.enter();eq(p.sent.at(-1)[1],prefix+' ) Привет.');
  await p.config({accentEnabled:false});p.type('.ыефеы');await p.enter();eq(p.sent.at(-1)[1],'/stats');
  await p.config({chatText:{...chatText,dotCommands:false}});p.type('.ыефеы');await p.enter();eq(p.sent.at(-1)[1],'.ыефеы');
  await p.config({enabled:false,chatText});p.type('.ыефеы');await p.enter();eq(p.sent.at(-1)[1],'.ыефеы');
  p=await page();p.type('.r '+'Я'.repeat(124));await p.enter();eq(p.api.wireSize(p.sent.at(-1)[1]),127);
  const dotCount=p.sent.length;p.type('.r '+'Я'.repeat(125));eq((await p.enter()).prevented,true);eq(p.sent.length,dotCount);
  p.type('.r Привет 🙂');p.root.sendMessageToChat(p.input.value);eq(p.sent.length,dotCount);
  p.type('.r\n/su 37');eq((await p.enter()).prevented,true);eq(p.sent.length,dotCount);
  p=await page();p.type('.ыефеы');p.time(2100);eq((await p.enter()).prevented,true);eq(p.sent.length,0);eq(p.input.value,'.ыефеы');
  await p.exchange();await p.enter();eq(p.sent.at(-1)[1],'/stats');
  p=await page();p.fire('compositionstart');p.type('.ыефеы');await p.enter();eq(p.sent.length,0);eq(p.input.value,'.ыефеы');
  p.fire('compositionend');await p.enter();eq(p.sent.at(-1)[1],'/stats');
  p=await page(true);p.type('.ыефеы');await p.enter();p.runTimers(60);await flush();eq(p.sent,[['HandleHudSendMessage','/stats']]);
  p=await page();p.type('.pa26unknown');await p.enter();eq(p.sent.length,0,'unknown converted PA command cannot leak to server');
  p.type('.pa26demo');await p.enter();await p.exchange();eq(p.observed.some(e=>e.kind==='local'&&e.text==='/pa26demo'),true);
  p=await page();p.panel.open=false;p.root.sendMessageToChat('.к Автоматически.');eq(p.sent.at(-1)[1],'.к Автоматически.');
  p.root.cef.emit('HandleHudSendMessage','.ыефеы');eq(p.sent.at(-1)[1],'.ыефеы');
  p=await page();await p.config({chatText:{version:99,dotCommands:true,keyboardMap:chatText.keyboardMap}});
  p.type('.ыефеы');await p.enter();eq(p.sent.at(-1)[1],prefix+' .ыефеы','unknown protocol keeps compatibility without guessing rules');
  // Manual /r is independent of accent/dot conversion and never edits bind sends.
  const radioPolicy={...chatText,radioPrefix:{enabled:true,localTag:'[SIGMA]:'}};
  p=await page();await p.config({chatText:radioPolicy});
  for(const [raw,expected]of [['/r Доклад.','/r [SIGMA]: Доклад.'],['/R Текст.','/R [SIGMA]: Текст.'],
    ['  /r   Текст.  ','  /r   [SIGMA]: Текст.  '],['/r [SIGMA]: Текст.','/r [SIGMA]: Текст.'],
    ['/r [SIGMA]:Текст.','/r [SIGMA]:Текст.'],['.к Текст.','/r [SIGMA]: Текст.'],
    ['/rn Текст.','/rn Текст.'],['/r','/r'],['/r   ','/r   '],['/radio Текст.','/radio Текст.'],
    ['/f Текст.','/f Текст.'],['/d Текст.','/d Текст.']]){
    p.type(raw);eq(p.input.value,raw,'radio prefix is added at submission');await p.enter();eq(p.sent.at(-1)[1],expected);
  }
  await p.config({accentEnabled:false,chatText:{...radioPolicy,dotCommands:false}});
  p.type('/r Без акцента.');await p.enter();eq(p.sent.at(-1)[1],'/r [SIGMA]: Без акцента.');
  await p.config({chatText:{...radioPolicy,radioPrefix:{enabled:false,localTag:'[SIGMA]:'}}});
  p.type('/r Выключено.');await p.enter();eq(p.sent.at(-1)[1],'/r Выключено.');
  await p.config({chatText:{...radioPolicy,radioPrefix:{enabled:true,localTag:''}}});
  p.type('/r Пусто.');await p.enter();eq(p.sent.at(-1)[1],'/r Пусто.');
  await p.config({chatText:radioPolicy});p.panel.open=false;
  p.root.sendMessageToChat('/r Автоматическая строка.');eq(p.sent.at(-1)[1],'/r Автоматическая строка.');
  p.panel.open=true;p.root.cef.emit('HandleHudSendMessage','/r Прямой emit.');eq(p.sent.at(-1)[1],'/r Прямой emit.');
  const radioCapacity=127-'/r [SIGMA]: '.length;
  p.type('/r '+'Я'.repeat(radioCapacity));await p.enter();eq(p.api.wireSize(p.sent.at(-1)[1]),127);
  let radioCount=p.sent.length;p.type('/r '+'Я'.repeat(radioCapacity+1));eq((await p.enter()).prevented,true);eq(p.sent.length,radioCount);eq(p.input.value,'/r '+'Я'.repeat(radioCapacity+1));
  p.type('/r Привет 🙂');eq((await p.enter()).prevented,true);eq(p.sent.length,radioCount);
  p.type('/r Текст\n/help');eq((await p.enter()).prevented,true);eq(p.sent.length,radioCount);
  p.type('/r Сохранить.');p.time(2100);eq((await p.enter()).prevented,true);eq(p.sent.length,radioCount);eq(p.input.value,'/r Сохранить.');
  await p.exchange();await p.enter();eq(p.sent.at(-1)[1],'/r [SIGMA]: Сохранить.');
  for(const tag of ['SIGMA','[Сигма]:','%s[%1]:','S:','[1]:']){
    await p.config({chatText:{...radioPolicy,radioPrefix:{enabled:true,localTag:tag}}});
    p.type('/r Текст.');await p.enter();eq(p.sent.at(-1)[1],'/r '+tag+' Текст.');
    p.type('/r '+tag+' Текст.');await p.enter();eq(p.sent.at(-1)[1],'/r '+tag+' Текст.');
  }
  p=await page(true);await p.config({chatText:radioPolicy});p.type('/r Снимок.');await p.enter();
  await p.config({chatText:{...radioPolicy,radioPrefix:{enabled:true,localTag:'[NEW]:'}}});
  p.runTimers(60);await flush();eq(p.sent.at(-1)[1],'/r [SIGMA]: Снимок.','delayed emit retains the submitted prefix');

  // Heavy typing/editing: no CEF/native-style caret rewrites or repeated layout walks.
  p=await page();p.input.scrollLeft=340;
  const initialCaret=p.input.caretWrites;
  const requestsBeforeTyping=p.requests.length;
  const beforeTyping={...p.stats};
  for(let i=0;i<300;i++){p.type('Длинный текст '+i,3);p.fire('keydown',{key:'t'});p.fire('keyup',{key:'t'});}
  eq(p.stats.textReads,beforeTyping.textReads,'typing does not read or parse the draft');
  eq(p.stats.textWrites-beforeTyping.textWrites,300,'only the simulated user writes the draft');
  eq(p.stats.styleReads,beforeTyping.styleReads,'typing does not force CSS reads');
  eq(p.stats.rectReads,beforeTyping.rectReads,'typing does not force layout');
  p.fire('compositionstart');p.fire('compositionend');eq(p.stats.textReads,beforeTyping.textReads);
  eq(p.input.caretWrites,initialCaret);eq(p.input.selectionStart,3);eq(p.input.scrollLeft,340);
  eq([...p.timers.values()].filter(t=>!t.interval&&t.ms===150).length,0,'no live text-processing timers');
  eq(p.requests.length,requestsBeforeTyping,'typing is independent of loopback requests');
  const endpointTimer=[...p.timers.values()].find(t=>t.interval&&t.ms===750),loads=p.stats.endpointLoads;
  endpointTimer.cb();eq(p.stats.endpointLoads,loads,'healthy connections do not reload endpoint scripts');
  p.offline(true);await p.exchange();p.time(3000);endpointTimer.cb();eq(p.stats.endpointLoads,loads+1,'a failed connection can discover a replacement endpoint');p.offline(false);await p.exchange();
  p.type('Привет',2);p.runTimers(150);await flush();
  eq(p.input.value,'Привет');eq(p.input.selectionStart,2);
  p.type('Очень длинное слово '.repeat(20),5);const held=p.input.value;await p.enter();
  eq(p.input.value,held,'failed submit retains the raw complete draft');eq(p.input.selectionStart,5);
  // The whole manual submission is preflighted before any original HUD emit.
  const manual={enabled:true,maxParts:3,threshold:90,marker:'...',displayLimit:115,margin:6,meExtra:1,doExtra:3,nicknameLength:12,rpEnabled:true,speechEnabled:true};
  const words='синяя куртка и чёрные брюки '.repeat(5).trim();
  for (const channel of ['','/me','/do','/try','/TRY','/r','/rn','/f','/fn','/d','/df','/l','/ln','/bkn','/n']) {
    p=await page();await p.config({chatText:{...chatText,manual}});
    const raw=channel ? channel+' '+words : words;p.type(raw);
    const prepared=p.api.submitted(raw);eq(prepared.parts.length>=2 && prepared.parts.length<=3,true);
    for (let i=0;i<prepared.parts.length;i++) {
      const part=prepared.parts[i];eq(p.api.wireSize(part)<=127,true);
      if(channel)eq(part.startsWith(channel.toLowerCase()+' '),true);
      if(i>0)eq(part.includes(prefix),false);
      if(i<prepared.parts.length-1)eq(part.split(' ').at(-1),'...');
    }
    const count=p.sent.length;await p.enter();await p.exchange();eq(p.sent.length,count,'manual parts use authenticated IPC, not the intercepted HUD emit');
    const packet=p.observed.find(e=>e.kind==='manual');eq(packet.text,raw);const request=p.requests.map(q=>JSON.parse(q.options.body)).find(q=>q.events.some(e=>e.kind==='manual'));
    const key=request.page+':'+packet.id;
    p.type('Новый текст');eq((await p.enter()).prevented,true);eq(p.input.value,'Новый текст');
    await p.config({manualResult:{key,status:'completed',raw:'',sent:prepared.parts.length,total:prepared.parts.length}});
    p.type('Готово');await p.enter();eq(p.sent.at(-1)[1],prefix+' Готово');
  }
  p=await page();await p.config({chatText:{...chatText,manual}});p.input.maxLength=127;p.mutate();await flush();p.type(words);eq(p.input.maxLength,8192,'HUD-open metadata refresh restores the limit without handling input events');
  await p.enter();await p.exchange();const manualPacket=p.observed.find(e=>e.kind==='manual');
  const manualRequest=p.requests.map(q=>JSON.parse(q.options.body)).find(q=>q.events.some(e=>e.kind==='manual'));
  const manualKey=manualRequest.page+':'+manualPacket.id;p.input.value='';
  await p.config({manualResult:{key:manualKey,status:'cancelled',raw:'Остаток сообщения',message:'Остановлено. Передано 1/3.',sent:1,total:3}});
  eq(p.input.value,'Остаток сообщения');eq(p.sent.length,0);p.api.stop();eq(p.input.maxLength,127);
  p=await page();await p.config({chatText:{...chatText,manual}});
  for (const raw of ['слово '.repeat(100),'/me '+'я'.repeat(300),'Привет 🙂','/do один\n/su 37 8 1']) {
    p.type(raw);const before=p.sent.length;eq((await p.enter()).prevented,true);eq(p.sent.length,before);eq(p.observed.some(e=>e.kind==='manual'),false);
  }
  const todoAction='я'.repeat(60),todoSpeech='примета '.repeat(14).trim();
  const todo=p.api.submitted('/todo '+todoSpeech+'*'+todoAction);
  eq(todo.parts.length>=2 && todo.parts.length<=3,true);
  for(let i=0;i<todo.parts.length;i++) {
    const [speech,action]=todo.parts[i].slice(6).split('*');eq(action,todoAction);eq(p.api.wireSize(todo.parts[i])<=127,true);
    if(i>0)eq(speech.startsWith('... '),true);if(i<todo.parts.length-1)eq(speech.endsWith(' ...'),true);
  }
  for(const raw of ['/todo текст*'+'я'.repeat(61),'/todo текст*одно*два','/todo *действие','/todo текст*'])eq(typeof p.api.submitted(raw).error,'string');
  p.type('/todo текст*'+'я'.repeat(61));const beforeTodo=p.sent.length;eq((await p.enter()).prevented,true);eq(p.sent.length,beforeTodo);eq(p.input.value,'/todo текст*'+'я'.repeat(61));
  eq(p.api.submitted('/su 37 8 1').manual,undefined);eq(p.api.submitted('/r Доклад.').manual,null);
  p=await page();await p.config({chatText:{...chatText,manual}});p.type(words);await p.enter();await p.exchange();
  const recoveredPacket=p.observed.find(e=>e.kind==='manual'),recoveredRequest=p.requests.map(q=>JSON.parse(q.options.body)).find(q=>q.events.some(e=>e.kind==='manual'));
  p.type('Другой черновик');const preserved=p.input.value;
  await p.config({manualResult:{key:recoveredRequest.page+':'+recoveredPacket.id,status:'rejected',raw:words,message:'Очередь занята.'}});
  eq(p.input.value,preserved,'recovering a rejected message cannot overwrite newly typed text');eq(!!p.elements['pa26-chat-restore'],true);
  p.elements['pa26-chat-restore'].onclick();eq(p.input.value,preserved);p.input.value='';p.elements['pa26-chat-restore'].onclick();eq(p.input.value,words);

  p=await page();await p.config({chatText:{...chatText,manual}});p.type(words);p.offline(true);p.time(2500);
  const staleBefore=p.sent.length;eq((await p.enter()).prevented,true);eq(p.sent.length,staleBefore);eq(p.input.value,words,'a lost bridge cannot send or truncate a previously prepared long message');
  p=await page();await p.config({chatText:{...chatText,manual}});p.type('/do '+words);p.offline(true);p.time(2500);
  eq((await p.enter()).prevented,true);eq(p.sent.length,0);eq(p.input.value,'/do '+words);
  // Input mutations publish immediately, including the final state if an
  // earlier request is still pending. Typed digits stay in the input element.
  p=await page();eq(p.observers.length,1);eq(p.observers[0].target,p.panel);
  eq(p.observers[0].options,{attributes:true,attributeOldValue:true,attributeFilter:['class','style','hidden']});
  let observedInput=false;p.root.document.addEventListener('keydown',()=>{observedInput=true;},false);
  p.type('Номер 123');
  for(const key of ['0','1','9'])for(const type of ['keydown','keyup']) {
    observedInput=false;const event=p.fire(type,{key,code:'Digit'+key});eq(event.bubbleStopped,true);eq(event.prevented,undefined);eq(observedInput,false);
  }
  for(const code of ['Numpad0','Numpad9'])eq(p.fire('keydown',{key:'Unidentified',code}).bubbleStopped,true);
  eq(p.fire('keydown',{key:'a'}).bubbleStopped,undefined);eq(p.fire('keydown',{key:'1',target:{tagName:'INPUT'}}).bubbleStopped,undefined);
  await p.config({weaponGuard:false});observedInput=false;eq(p.fire('keydown',{key:'1'}).bubbleStopped,undefined);eq(observedInput,true);
  p.time(2200);eq(p.fire('keydown',{key:'1'}).bubbleStopped,undefined,'Explicit OFF survives an expired bridge reply');
  await p.config({weaponGuard:true});p.panel.open=false;eq(p.fire('keydown',{key:'1'}).bubbleStopped,undefined);p.mutate();await flush();
  let beforeMutation=p.requests.length;p.panel.open=true;p.mutate();await flush();eq(p.requests.length,beforeMutation+1);
  eq(JSON.parse(p.requests.at(-1).options.body).chat,true);
  beforeMutation=p.requests.length;p.panel.open=false;p.mutate();await flush();eq(p.requests.length,beforeMutation+1);eq(JSON.parse(p.requests.at(-1).options.body).chat,false);
  beforeMutation=p.requests.length;p.fire('keydown',{key:'F6'});p.panel.open=true;p.runTimers(0);await flush();p.runTimers(0);await flush();
  eq(p.requests.length>beforeMutation,true);eq(JSON.parse(p.requests.at(-1).options.body).chat,true);
  p.api.stop();eq(p.observers[0].live,false);eq(p.fire('keydown',{key:'2'}).bubbleStopped,undefined);
  // A single-line submission does not await the heartbeat response or a round trip.
  p=await page();p.type('Короткое сообщение.');let finishReply;
  p.root.fetch=()=>new Promise(resolve=>finishReply=resolve);const hanging=p.exchange();
  const emitted=p.sent.length;p.root.sendMessageToChat(p.input.value);
  eq(p.sent.length,emitted+1,'native single-line emit happens while HTTP remains pending');
  eq(p.sent.at(-1)[1],prefix+' Короткое сообщение.');
  finishReply({ok:true,json:async()=>({schema:1,ack:0,enabled:true,session:'one'})});await hanging;
  // Non-chat CEF calls are a transparent pass-through, including arity/this.
  p=await page();const receiver={test:true};const start={...p.stats},requests=p.requests.length;
  eq(p.root.cef.emit.call(receiver),receiver);eq(p.sent.at(-1),[]);
  eq(p.root.cef.emit.call(receiver,'OtherEvent'),receiver);eq(p.sent.at(-1),['OtherEvent']);
  const payload={get draft(){throw Error('unrelated payload must not be inspected');}};
  eq(p.root.cef.emit.call(receiver,'OtherEvent',payload,undefined,5),receiver);eq(p.sent.at(-1)[1],payload);eq(p.sent.at(-1).length,4);
  await flush();eq(p.requests.length,requests);eq(p.stats.textReads,start.textReads);eq(p.stats.styleReads,start.styleReads);
  p.root.cef.set_focus(true);await flush();const stableFocus=p.requests.length;
  for(let i=0;i<2000;i++)p.root.cef.set_focus(true);await flush();eq(p.requests.length,stableFocus,'Repeated focus state must not cause IPC work');
  p=await page();const heartbeat=[...p.timers.values()].find(t=>t.interval&&t.ms===750);const stable={...p.stats};
  for(let i=0;i<20;i++){p.time(750);heartbeat.cb();await flush();}
  eq(p.stats.textReads,stable.textReads,'Stable leases never read the draft');eq(p.stats.styleReads,stable.styleReads,'Stable leases never force style');eq(p.stats.rectReads,stable.rectReads,'Stable leases never force geometry');
  const unchanged={...p.stats},unchangedRequests=p.requests.length;
  p.panel.getAttribute=()=> 'active';
  for(let i=0;i<10000;i++)p.observers[0].cb([{type:'attributes',target:p.panel,attributeName:'class',oldValue:'active'}]);
  await flush();eq(p.requests.length,unchangedRequests,'Redundant HUD attribute writes cannot wake IPC');eq(p.stats.styleReads,unchanged.styleReads);eq(p.stats.rectReads,unchanged.rectReads);eq(p.stats.textReads,unchanged.textReads);
  p.mutate();await flush();eq(p.requests.length,unchangedRequests,'A visibility refresh with identical ownership does not publish again');
  const beforePrepare={...p.stats};p.type('слово '.repeat(60));const reads=p.stats.textReads;
  for(let i=0;i<100;i++)p.api.prepare();eq(p.stats.textReads,reads,'Legacy preview entry point cannot analyze editing text');
  // Compact metadata cannot override cached safety settings or invent a policy.
  await p.config({policyRevision:4,weaponGuard:false});await p.config({policyUnchanged:true,policyRevision:4,keyboardLayout:false});
  eq(p.fire('keydown',{key:'1'}).bubbleStopped,undefined);eq(p.elements['pa26-chat-layout'],undefined);
  await p.config({policyUnchanged:true,policyRevision:5});eq(p.warnings.at(-1),'[PA26 CEF] exchange_failed: bad_response');
  const fs=require('node:fs'),crypto=require('node:crypto');
  fs.writeFileSync(require('node:path').join(__dirname,'CEF_BROWSER_RESULTS.json'),JSON.stringify({status:'passed',checks,
    adapter_sha256:crypto.createHash('sha256').update(fs.readFileSync(require('node:path').join(__dirname,'../cef/assets/hud/pa26-chat.js'))).digest('hex'),
    test_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),game_launched:false},null,2)+'\n');
  console.log('CEF browser adapter: '+checks+' checks passed');
})().catch(error => {console.error(error);process.exitCode=1;});
