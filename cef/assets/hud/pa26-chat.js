/* Police Assistant: optional Exsellent HUD adapter. No server packets are created here. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory;
  else factory(root);
})(typeof window !== 'undefined' ? window : globalThis, function install(root) {
  'use strict';
  if (root.PA26Chat) return root.PA26Chat;
  const doc = root.document;
  const clock = () => root.performance.now();
  const state = {url: null, config: null, until: 0, queue: [], next: 1, pending: false,
    failures: 0, owned: '', composing: false, submits: [], stopped: false, hooked: false, cefFocused: false,
    applied: 0, submitted: 0, rejected: 0, lastError: '', diagnostics: true, layoutBadge: null, lastChatText: null};
  // Discovery is bounded and never runs from input/selection handlers. A long
  // outage goes dormant until the page becomes active again or explicit retry.
  const cefRetryDelays = [50,100,200,400,800,1600,3200,5000,5000,5000];
  const endpointRetryDelays = [2500,5000,10000,20000,30000,60000];
  let cefRetryTimer = null, cefRetryIndex = 0, endpointRequest = null;
  let endpointAttempts = 0, endpointNext = 0, endpointDormant = false, exchangeNext = 0;
  const page = String(root.Date.now()) + '-' + String(root.Math.random()).slice(2);
  const cpExtra = new Set(Array.from('ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬®Ї°±Ііґµ¶·ё№є»јЅѕї'));
  const command = text => /^\s*[\/!]/u.test(text);
  const empty = text => /^\s*$/u.test(text);
  function wireSize(text) {
    let bytes = 0;
    for (const c of text) {
      const n = c.codePointAt(0);
      if (n < 32 || n === 127 || !(n <= 127 || n >= 0x410 && n <= 0x44f || cpExtra.has(c))) return null;
      bytes++;
    }
    return bytes;
  }
  function config() { return clock() <= state.until ? state.config : null; }
  function runtimeReady() { return !state.compatibility || state.compatibility.ready === true; }
  function compatibilityHello() {
    const c=state.compatibility;if(!c)return undefined;
    if(c.phase==='confirmed'||c.failed)return {protocol:2,challenge:c.challenge,phase:c.phase};
    const el=field(),panel=doc.getElementById('chatInput');
    let parent=el,inside=false;for(let depth=0;parent&&depth<32;depth++,parent=parent.parentElement)if(parent===panel){inside=true;break;}
    const cef=root.cef;
    return {protocol:2,challenge:c.challenge,fingerprint:c.fingerprint,phase:'hello',capabilities:{
      dom:!!(el&&el.tagName==='INPUT'&&!el.disabled&&!el.readOnly&&panel&&inside&&panel.classList&&typeof panel.classList.contains==='function'),
      send:state.hooked&&root.sendMessageToChat===state.wrappedSubmit,
      emit:!!cef&&cef.emit===state.wrappedEmit&&cef.on===state.wrappedOn,
      incoming:(state.incomingRegistrations||0)>0,
      focus:!!cef&&cef.set_focus===state.wrappedFocus&&typeof root.isDialogActive==='function'}};
  }
  function prefix() {
    const c = config();
    return c && c.enabled && c.accentEnabled && typeof c.accent === 'string' ? c.accent : '';
  }
  function textPolicy() {
    const c = config(), p = c && c.enabled && c.chatText;
    return p && p.version === 1 && p.keyboardMap && typeof p.keyboardMap === 'object' ? p : null;
  }
  function dotCommand(text, p) {
    if (p && p.dotCommands === true) {
      const ooc=/^\s*\/b\s+\.и\s+(\S[\s\S]*)$/iu.exec(text);
      if (ooc) return '/n '+ooc[1];
    }
    if (!p || p.dotCommands !== true || !text.startsWith('.') || text.startsWith('..')) return null;
    const match = /^\.([^ \t\r\n]+)([\s\S]*)$/u.exec(text);
    if (!match) return null;
    const name = Array.from(match[1], c => Object.prototype.hasOwnProperty.call(p.keyboardMap, c) ? p.keyboardMap[c] : c).join('');
    if (!/^[A-Za-z][A-Za-z0-9_]*$/u.test(name)) return null;
    return '/' + name + match[2];
  }
  function radioCommand(text, p) {
    const radio = p && p.radioPrefix, tag = radio && radio.localTag;
    if (!radio || radio.enabled !== true || typeof tag !== 'string' || !tag) return null;
    const match = /^( *\/[rR])( +)([\s\S]*)$/u.exec(text);
    if (!match || /^ *$/u.test(match[3])) return null;
    const body = match[3], last = tag.charCodeAt(tag.length - 1);
    const punctuation = last >= 33 && last <= 47 || last >= 58 && last <= 64 || last >= 91 && last <= 96 || last >= 123 && last <= 126;
    const supplied = body.startsWith(tag) && (body === tag || body.charAt(tag.length) === ' ' || punctuation);
    return supplied ? text : match[1] + match[2] + tag + ' ' + body;
  }
  function accented(text) {
    const p = prefix(), rules = textPolicy();
    if (!p || command(text) || empty(text) || rules && (rules.skipBrackets === true && /^\s*[()]/u.test(text) ||
        rules.dotCommands === true && text.startsWith('.'))) return {text};
    const supplied = text.startsWith(p) && (/[\s:;,.!?]$/u.test(p) || /^\s/u.test(text.slice(p.length)));
    const value = supplied ? text : p + ' ' + text;
    const size = wireSize(value);
    if (size === null) return {error: 'В сообщении есть символы, которые игровой чат не поддерживает. Измените их перед отправкой.'};
    if (size > 127) return {error: 'Сократите сообщение: вместе с акцентом должно быть не больше 127 символов. Текст сохранён в поле.'};
    return {text: value};
  }
  function manualSubmission(text, rules) {
    const m = rules && rules.manual;
    if (!m || m.enabled !== true || !Number.isInteger(m.maxParts) || m.maxParts < 1 || m.maxParts > 3 ||
        !Number.isInteger(m.threshold) || m.threshold < 24 || m.threshold > 120 || typeof m.marker !== 'string' || !m.marker || /\s/u.test(m.marker)) return null;
    const converted = dotCommand(text, rules);
    let normalized = converted === null ? text : converted;
    const radio=radioCommand(normalized,rules);if (radio !== null) normalized=radio;
    if (wireSize(normalized) === null) return {error:'В сообщении есть неподдерживаемый символ или перенос строки. Ввод сохранён.'};
    const match = /^(\/[A-Za-z]+)\s+(.+)$/u.exec(normalized);
    let channel = match ? match[1].toLowerCase() : '', body = match ? match[2] : normalized;
    const roleplay=['/me','/do','/try'].includes(channel), todo=channel==='/todo';
    const textChannels=['','/s','/m','/r','/rn','/f','/fn','/d','/df','/l','/ln','/bkn','/n','/b'];
    if (command(normalized) && !roleplay && !todo && !textChannels.includes(channel)) return null;
    if (empty(body)) return null;
    if (!channel) body = accentedWithoutLimit(body).text;
    let suffix='';
    if(todo) {
      const pair=/^([^*]+)\*([^*]+)$/u.exec(body);
      if(!pair || !pair[1].trim() || !pair[2].trim())return {error:'Для /todo нужен текст*действие с одной звёздочкой. Ввод сохранён.'};
      body=pair[1].trim();const action=pair[2].trim();
      const limit=Number.isInteger(m.todoActionLimit) ? m.todoActionLimit : 60;
      if(limit<1 || limit>60 || [...action].length>limit)return {error:'Действие после * в /todo длиннее '+limit+' символов. Сократите действие; отправки не было.'};
      suffix='*'+action;
    }
    const bytes = wireSize(body), markerBytes = wireSize(m.marker);
    if (bytes === null || markerBytes === null) return {error:'Сообщение содержит неподдерживаемый символ. Текст сохранён в поле.'};
    const prefix = channel ? channel + ' ' : '';
    let budget = Math.min(m.threshold,127-prefix.length-wireSize(suffix));
    if (roleplay) budget = Math.min(budget,m.displayLimit-m.margin-m.nicknameLength-(channel === '/me' ? m.meExtra : m.doExtra));
    if (!Number.isFinite(budget) || budget < 1) return {error:'Проверьте настройки переноса PA. Текст сохранён в поле.'};
    const enabled = roleplay || todo ? m.rpEnabled : m.speechEnabled && (!m.channels || m.channels[channel]!==false);
    const parts = [];
    const add = value => {const line=prefix+value+suffix; if (wireSize(line) === null || wireSize(line) > 127 || parts.length >= m.maxParts) return false; parts.push(line); return true;};
    const threshold=todo ? budget : m.threshold;
    if (!enabled || bytes <= threshold) {
      if(todo && !enabled && bytes>budget)return {error:'Перенос RP отключён, /todo не помещается в чат. Ввод сохранён.'};
      if (!add(body)) return {error:'Текст не помещается в чат. Отправки не было; ввод сохранён.'};
    } else {
      if (budget < 2*markerBytes+8) return {error:'После маркеров не хватает места. Сократите действие или маркер в настройках PA.'};
      const words=body.match(/\S+/gu) || [];let index=0;
      while (index < words.length) {
        const lead=parts.length ? m.marker+' ' : '', rest=words.slice(index).join(' ');
        if (wireSize(lead+rest) <= budget) { if (!add(lead+rest)) return {error:'Текст длиннее '+m.maxParts+' частей. Сократите его; отправки не было.'};break; }
        let current='';
        while (index < words.length) {
          const candidate=current ? current+' '+words[index] : words[index];
          if (wireSize(lead+candidate+' '+m.marker) > budget) break;
          current=candidate;index++;
        }
        if (!current) return {error:'Одно слово слишком длинное для переноса. Сократите его; текст не обрезан.'};
        if (!add(lead+current+' '+m.marker)) return {error:'Текст длиннее '+m.maxParts+' частей. Сократите его; отправки не было.'};
      }
    }
    return {text:parts[0],parts,manual:parts.length > 1 ? text : null,converted:converted !== null};
  }
  function accentedWithoutLimit(text) {
    const p=prefix(),rules=textPolicy();
    if (!p || command(text) || empty(text) || rules && (rules.skipBrackets && /^\s*[()]/u.test(text) || rules.dotCommands && text.startsWith('.'))) return {text};
    const supplied=text.startsWith(p) && (/[\s:;,.!?]$/u.test(p) || /^\s/u.test(text.slice(p.length)));
    return {text:supplied ? text : p+' '+text};
  }
  function recoverManual(raw,message,insert=true) {
    state.recoveryNotice=message;
    if (typeof raw !== 'string' || !raw) { notice(message); return; }
    state.manualDraft=raw;
    const el=field();
    if (insert && el && (!el.value || el.value === state.owned)) { el.value=raw;state.owned='';state.manualDraft=null; }
    notice(message);
    if (state.manualDraft && el) {
      let button=doc.getElementById('pa26-chat-restore');
      if (!button) { button=doc.createElement('button');button.id='pa26-chat-restore';button.textContent='Вставить сохранённый остаток';el.parentElement.appendChild(button); }
      button.hidden=false;
      button.onclick=()=> { const input=field();if (input && (!input.value || input.value === state.owned)) { input.value=state.manualDraft;state.manualDraft=null;state.owned='';button.hidden=true;notice('Текст восстановлен. Проверьте его перед отправкой.'); }else notice('Сначала сохраните или очистите текущий ввод. Оба текста сохранены.'); };
    }
  }
  function submitted(text) {
    const rules = textPolicy();
    if (!rules && !config() && state.lastChatText) {
      const previousManual=manualSubmission(text,state.lastChatText);
      if (previousManual && (previousManual.error || previousManual.manual)) return {error:'Связь с PA прервалась. Дождитесь восстановления переноса; весь текст сохранён в поле.'};
    }
    if (!rules && !config() && dotCommand(text, state.lastChatText)) {
      return {error: 'Связь с PA прервалась. Дождитесь восстановления или введите команду с / на английской раскладке. Текст сохранён в поле.'};
    }
    if (!rules && !config() && radioCommand(text, state.lastChatText) !== null) {
      return {error: 'Связь с PA прервалась. Дождитесь восстановления настроек рации. Текст сохранён в поле.'};
    }
    const manual=manualSubmission(text,rules);if (manual) return manual;
    const converted = dotCommand(text, rules), radio = radioCommand(converted === null ? text : converted, rules);
    if (converted === null && radio === null) return accented(text);
    const value = radio === null ? converted : radio;
    const size = wireSize(value);
    if (size === null) return {error: 'В команде есть символы, которые игровой чат не поддерживает. Измените их перед отправкой.'};
    if (size > 127) return {error: 'Сократите команду до 127 символов. Команды не делятся и не обрезаются. Текст сохранён в поле.'};
    return {text: value, converted: converted !== null};
  }
  function field() { return doc.getElementById('chatInputField'); }
  function visible(el, allowTransparent = false) {
    if (!el || el.hidden || el.isConnected === false) return false;
    state.visibleCache ||= new WeakMap();
    const cached = state.visibleCache.get(el), now = clock();
    if (cached && now >= cached.at && now - cached.at < 250 && cached.transparent === allowTransparent) return cached.value;
    const remember = value => { state.visibleCache.set(el,{at:now,transparent:allowTransparent,value}); return value; };
    if (typeof el.getClientRects === 'function' && el.getClientRects().length === 0) return remember(false);
    if (typeof root.getComputedStyle === 'function') {
      for (let node = el; node; node = node.parentElement) {
        const style = root.getComputedStyle(node);
        if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' ||
            !allowTransparent && Number(style.opacity) === 0) return remember(false);
      }
    }
    return remember(true);
  }
  function active() {
    const panel = doc.getElementById('chatInput');
    return !!(panel && !panel.hidden && panel.isConnected !== false && panel.classList.contains('active') && visible(panel, true));
  }
  function panelOpen() {
    const panel=state.observedPanel || doc.getElementById('chatInput');
    return !!(panel && !panel.hidden && panel.isConnected!==false && panel.classList.contains('active'));
  }
  function inputChanged(records) {
    if(Array.isArray(records) && records.length && records.every(record => record.type==='attributes' &&
        record.target && typeof record.target.getAttribute==='function' && record.oldValue===record.target.getAttribute(record.attributeName))) return;
    state.inputDirty = true;
    if (state.inputScheduled || state.stopped) return;
    state.inputScheduled = true;
    // Focus/class changes are coalesced after the HUD finishes its own event.
    // No input, beforeinput, selectionchange or mousemove listener is installed.
    Promise.resolve().then(() => {
      state.inputScheduled = false;
      if (state.stopped) return;
      hookInput(); readInput(); syncFieldLimit(); updateLayoutBadge();
      if(state.inputSequence!==state.publishedInputSequence)exchange();
    });
  }
  function guardDigit(event) {
    if (!(/^[0-9]$/u.test(event.key || '') || /^(Digit|Numpad)[0-9]$/u.test(event.code || '') ||
        event.keyCode >= 48 && event.keyCode <= 57 || event.keyCode >= 96 && event.keyCode <= 105)) return;
    const c = config();
    if (state.stopped || !runtimeReady() || c && (!c.enabled || c.weaponGuard === false) || state.inputGuardDisabled || !panelOpen() || event.target !== state.guardedField) return;
    if (/^[0-9]$/u.test(event.key || '') || /^(Digit|Numpad)[0-9]$/u.test(event.code || '') ||
        event.keyCode >= 48 && event.keyCode <= 57 || event.keyCode >= 96 && event.keyCode <= 105) {
      // Keep the input's default editing and WM_CHAR; stop only HUD bubbling.
      if (typeof event.stopPropagation === 'function') event.stopPropagation();
    }
  }
  function hookInput() {
    if (state.stopped) return;
    const panel = doc.getElementById('chatInput'), el = field();
    if (panel !== state.observedPanel) {
      if (state.inputObserver) state.inputObserver.disconnect();
      if (state.ancestorObserver) state.ancestorObserver.disconnect();
      state.observedPanel = panel;
      if (panel && typeof root.MutationObserver === 'function') {
        state.inputObserver = new root.MutationObserver(inputChanged);
        state.inputObserver.observe(panel, {attributes: true, attributeOldValue:true, attributeFilter: ['class', 'style', 'hidden']});
        if (panel.parentElement) {
          state.ancestorObserver=new root.MutationObserver(inputChanged);
          for(let node=panel.parentElement,depth=0;node && depth<32;node=node.parentElement,depth++)
            state.ancestorObserver.observe(node,{attributes:true,attributeOldValue:true,attributeFilter:['class','style','hidden']});
        }
      }
    }
    const dialog = doc.getElementById('Dialog');
    if (dialog !== state.observedDialog) {
      if (state.dialogObserver) state.dialogObserver.disconnect();
      state.observedDialog = dialog;
      if (dialog && typeof root.MutationObserver === 'function') {
        state.dialogObserver = new root.MutationObserver(inputChanged);
        state.dialogObserver.observe(dialog, {attributes:true, attributeOldValue:true, attributeFilter:['class','style','hidden']});
      }
    }
    if (el && el !== state.guardedField) {
      state.guardedFields ||= new WeakSet();
      if (!state.guardedFields.has(el) && typeof el.addEventListener === 'function') {
        el.addEventListener('keydown', guardDigit, false); el.addEventListener('keyup', guardDigit, false);
        state.guardedFields.add(el);
      } else if (typeof el.addEventListener !== 'function' && !state.fallbackGuardHooked) {
        doc.addEventListener('keydown', guardDigit, false); doc.addEventListener('keyup', guardDigit, false);
        state.fallbackGuardHooked = true;
      }
      state.guardedField = el;
    }
  }
  function inputState() {
    let dialog = false;
    try { dialog = visible(doc.getElementById('Dialog'), true) && typeof root.isDialogActive === 'function' && root.isDialogActive() === true; } catch (_) { dialog = false; }
    const el = doc.activeElement;
    const typing = !!(el !== field() && visible(el) && !el.disabled && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/u.test(el.tagName)));
    const chat = active();
    return {chat, dialog, busy: chat || dialog || typing || state.cefFocused};
  }
  function readInput() {
    if (state.inputDirty || !state.input) {
      state.visibleCache = new WeakMap();
      const previous=state.input,next=inputState();
      if(!previous || previous.chat!==next.chat || previous.busy!==next.busy || previous.dialog!==next.dialog)
        state.inputSequence=(state.inputSequence || 0)+1;
      state.input = next; state.fieldVisible=next.chat && visible(state.guardedField);state.inputDirty = false;
    }
    return state.input;
  }
  function updateLayoutBadge() {
    const c = config(), el = state.guardedField;
    const code = c && c.enabled && c.layoutIndicator === true && c.keyboardLayout;
    const show = !state.stopped && readInput().chat && state.fieldVisible && !!el && typeof code === 'string' && /^[A-Z]{2,3}$/u.test(code);
    const signature = show ? code : '';
    if (state.badgeField === el && state.badgeCode === signature && (!state.layoutBadge || state.layoutBadge.isConnected !== false && state.layoutBadge.parentElement === el.parentElement)) return;
    state.badgeField=el; state.badgeCode=signature;
    if (!show) {
      if (state.layoutBadge) { state.layoutBadge.remove(); state.layoutBadge = null; }
      return;
    }
    const parent = el.parentElement;
    if (!parent || typeof parent.insertBefore !== 'function') return;
    if (state.layoutBadge && (state.layoutBadge.parentElement !== parent || state.layoutBadge.isConnected === false)) {
      state.layoutBadge.remove(); state.layoutBadge = null;
    }
    if (!state.layoutBadge) {
      const badge = doc.createElement('span'); badge.id = 'pa26-chat-layout';
      Object.assign(badge.style, {display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        flex: '0 0 auto', boxSizing: 'border-box', minWidth: '34px', padding: '6px 8px',
        borderRadius: '5px', background: 'rgba(255,255,255,.10)', color: 'var(--white, #fff)',
        fontFamily: 'Montserrat-Bold, sans-serif', fontWeight: '700', fontSize: '13px', lineHeight: '1',
        letterSpacing: '.04em', pointerEvents: 'none', userSelect: 'none'});
      // The existing send icon stays at the right edge. No wrapper, input
      // styles, focus, value, caret or keyboard handlers are changed.
      parent.insertBefore(badge, el.nextSibling); state.layoutBadge = badge;
    }
    if (state.layoutBadge.textContent !== code) {
      state.layoutBadge.textContent = code;
      state.layoutBadge.setAttribute('aria-label', 'Язык ввода: ' + code);
    }
  }
  function notice(message) {
    const el = field(); if (!el) return;
    let hint = doc.getElementById('pa26-chat-notice');
    if (!hint) {
      hint = doc.createElement('div'); hint.id = 'pa26-chat-notice';
      hint.setAttribute('role', 'status');
      Object.assign(hint.style, {font: '600 13px/1.4 sans-serif', color: '#ffd591', padding: '5px 8px', whiteSpace: 'normal'});
      el.parentElement.appendChild(hint);
    }
    if (hint.textContent !== (message || '')) hint.textContent = message || '';
    if (hint.hidden !== !message) hint.hidden = !message;
  }
  function syncFieldLimit() {
    const el=field(), policy=textPolicy(), enabled=policy && policy.manual && policy.manual.enabled;
    if (!el) return;
    if (state.limitField !== el) { state.limitField=el;state.originalMaxLength=undefined; }
    if (enabled && el.maxLength>0 && el.maxLength<8192) {
      if (state.originalMaxLength===undefined) state.originalMaxLength=el.maxLength;
      el.maxLength=8192;
    } else if (!enabled && state.originalMaxLength!==undefined) {
      el.maxLength=state.originalMaxLength;state.originalMaxLength=undefined;
    }
  }
  function prepare() {
    // Compatibility entry point for old diagnostics. Editing is owned by CEF.
    // Validation, splitting and useful error messages run at submission only.
  }
  function enqueue(kind, text, color, session = state.config && state.config.session) {
    if (!config() || !state.config.enabled || typeof text !== 'string' || text.length > 4096) return false;
    if (state.queue.length >= 64) return false;
    state.queue.push({id: state.next++, kind, text, session, color: typeof color === 'number' ? color : 0});
    return true;
  }
  function filtered(text) {
    const c = config();
    if (!c || !c.enabled || !Array.isArray(c.filters)) return false;
    const plain = text.replace(/\{[\da-f]{6}\}/giu, '').trim();
    return c.filters.some(p => typeof p === 'string' && p && plain.startsWith(p));
  }
  function hookCef() {
    const cef = root.cef;
    if (state.stopped || !cef || typeof cef.on !== 'function' || typeof cef.emit !== 'function' || typeof cef.set_focus !== 'function') return false;
    if (state.cefTarget === cef) return cef.on === state.wrappedOn && cef.emit === state.wrappedEmit && cef.set_focus === state.wrappedFocus;
    state.cefTarget = cef;state.incomingRegistrations = 0;
    const originalOn = cef.on, originalEmit = cef.emit;
    if (typeof cef.set_focus === 'function') {
      const originalFocus = cef.set_focus;
      cef.set_focus = function (focus, ...args) {
        const next=focus === true || focus === 1,changed=next!==state.cefFocused;
        state.cefFocused = next;
        const result = originalFocus.call(this, focus, ...args); if(changed)inputChanged();return result;
      };
      state.wrappedFocus=cef.set_focus;
    }
    cef.on = function (name, callback, ...rest) {
      if (name === 'chat:messages' && typeof callback === 'function') {
        state.incomingRegistrations=(state.incomingRegistrations||0)+1;
        const original = callback;
        callback = function (color, text, ...args) {
          if (!state.stopped && state.cefTarget === cef && runtimeReady() && typeof text === 'string') {
            enqueue('message', text, color); exchange();
            if (filtered(text)) return;
          }
          return original.call(this, color, text, ...args);
        };
      }
      return originalOn.call(this, name, callback, ...rest);
    };
    state.wrappedOn=cef.on;
    cef.emit = function () {
      // Preserve even zero/one arguments, receiver and return value verbatim.
      if (arguments[0] !== 'HandleHudSendMessage' || state.cefTarget !== cef || !runtimeReady() || state.stopped) return originalEmit.apply(this, arguments);
      const [name, text, ...args] = arguments;
      state.submits = state.submits.filter(ticket => clock() - ticket.at <= 5000);
      const index = typeof text === 'string' ? state.submits.findIndex(ticket => ticket.text === text ||
        !ticket.manual && command(ticket.text) && command(text) && ticket.text.replace(/^\s*\S+/u,'') === text.replace(/^\s*\S+/u,'')) : -1;
      if (name === 'HandleHudSendMessage' && index >= 0) {
        const ticket = state.submits.splice(index,1)[0];
        const c = config();
        if (ticket.manual) {
          if (!c || !c.enabled || !enqueue('manual',ticket.manual,0,ticket.session)) {
            root.setTimeout(()=>recoverManual(ticket.manual,'Не удалось поставить сообщение в очередь. Ввод сохранён.'),0);return;
          }
          state.manualPending={key:page+':'+(state.next-1),raw:ticket.manual,session:ticket.session,at:clock()};exchange();return;
        }
        const name = /^\/([a-zA-Z][a-zA-Z0-9_]*)\b/u.exec(text);
        if (name && (/^pa26/iu.test(name[1]) || c && Array.isArray(c.localCommands) && c.localCommands.includes(name[1].toLowerCase()))) {
          if (!c || !c.enabled) notice('PA не отвечает или поддержка чата лаунчера отключена. Повторите команду после восстановления связи.');
          else if (!Array.isArray(c.localCommands) || !c.localCommands.includes(name[1].toLowerCase())) notice('В PA нет такой команды. Проверьте её название.');
          else {
            if (!enqueue('local', text, 0, ticket.session)) notice('Команда PA не выполнена: очередь занята. Повторите ввод.');
            exchange(); return;
          }
          return;
        }
        if (c && c.enabled) {
          if (command(text)) { enqueue('command', text, 0, ticket.session); exchange(); }
        }
      }
      return originalEmit.call(this, name, text, ...args);
    };
    state.wrappedEmit=cef.emit;
    return true;
  }
  function discoverCef(restart = false) {
    if (state.stopped) return;
    if (hookCef()) {
      if (cefRetryTimer !== null) root.clearTimeout(cefRetryTimer);
      cefRetryTimer = null;return;
    }
    if (restart && cefRetryTimer === null) cefRetryIndex = 0;
    if (cefRetryTimer !== null || cefRetryIndex >= cefRetryDelays.length) return;
    cefRetryTimer = root.setTimeout(() => {cefRetryTimer=null;discoverCef();},cefRetryDelays[cefRetryIndex++]);
  }
  function restartDiscovery() {
    endpointAttempts=0;endpointNext=0;endpointDormant=false;
  }
  function resumeDiscovery() {
    if (state.stopped || doc.visibilityState === 'hidden') return;
    // Do not reset an active backoff burst on repeated focus events.
    if (endpointDormant) {restartDiscovery();exchangeNext=0;}
    if (cefRetryTimer === null) discoverCef(true);
    loadEndpoint();
  }
  function hookSubmit() {
    if (state.hooked || typeof root.sendMessageToChat !== 'function') return;
    const original = root.sendMessageToChat;
    root.sendMessageToChat = function (text, ...args) {
      if (state.stopped || !runtimeReady() || typeof text !== 'string' || !active()) return original.call(this, text, ...args);
      if (state.composing) return;
      if (state.manualPending) { notice('Предыдущее сообщение ещё отправляется. Новый ввод сохранён.');return; }
      const body = state.owned && text.startsWith(state.owned) ? text.slice(state.owned.length) : text;
      const result = submitted(body);
      if (result.error) { state.rejected = Math.min(1000000, state.rejected + 1); notice(result.error); return; }
      state.submits = state.submits.filter(ticket => clock() - ticket.at <= 5000);
      if (state.submits.length >= 8) { notice('Дождитесь отправки предыдущего сообщения. Текст сохранён в поле.'); return; }
      if (result.manual && state.queue.length>=64) { notice('Очередь PA занята. Ввод сохранён.');return; }
      state.submits.push({at: clock(), text: result.text, manual:result.manual, session: config() && config().session});
      if (result.text !== body) state.applied=Math.min(1000000,state.applied+1);
      state.submitted = Math.min(1000000, state.submitted + 1);
      state.recoveryNotice=null;notice('');
      return original.call(this, result.text, ...args);
    };
    state.wrappedSubmit=root.sendMessageToChat;
    state.hooked = true;
  }
  async function exchange() {
    if (!state.url || state.pending || state.stopped || state.failures && (clock()<exchangeNext || endpointDormant)) return;
    state.pending = true;
    const url = state.url;
    const input=readInput(),inputSequence=state.inputSequence || 0;
    state.publishedInputSequence=inputSequence;
    const abort = new root.AbortController();
    const timeout = root.setTimeout(() => abort.abort(), 1500);
    try {
      const response = await root.fetch(url, {method: 'POST', cache: 'no-store', signal: abort.signal,
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({schema: 1, page, ...input, events: state.queue.slice(0, 24),
          compatibility: compatibilityHello(),
          policyRevision: state.config && state.config.policyRevision,
          diagnostics: !state.diagnostics ? undefined : {field: !!state.guardedField && state.guardedField.isConnected!==false, sendHook: state.hooked,
            accentConfigured: !!prefix(), applied: state.applied, submitted: state.submitted, rejected: state.rejected}})});
      if (!response.ok) throw Error('http_' + response.status);
      const value = await response.json();
      if (state.stopped || url !== state.url) return;
      if (!value || value.schema !== 1 || !Number.isSafeInteger(value.ack) || typeof value.enabled !== 'boolean') throw Error('bad_response');
      if(state.compatibility){
        const c=state.compatibility,reply=value.compatibility;
        if(!reply||reply.protocol!==2||reply.challenge!==c.challenge)throw Error('bad_response');
        if(reply.phase==='ack'){c.phase='confirmed';Promise.resolve().then(()=>exchange());}
        c.ready=reply.phase==='ready'&&(reply.state==='KNOWN_VERIFIED'||reply.state==='RUNTIME_VERIFIED');
        c.state=reply.state;
        if(!c.ready){
          state.config=null;state.until=0;state.inputGuardDisabled=true;
          if(reply.state==='INCOMPATIBLE'||reply.state==='UNAVAILABLE'||clock()-c.startedAt>12000){c.failed=true;throw Error('handshake_failed');}
          return;
        }
      }
      state.queue = state.queue.filter(event => event.id > value.ack);
      if (value.policyUnchanged === true && (!state.config || value.policyRevision !== state.config.policyRevision)) throw Error('bad_response');
      state.config = value.policyUnchanged === true ? {...state.config, ...value} : value;
      state.until = clock() + 2000; state.failures = 0; state.lastError = ''; state.diagnostics = state.config.diagnostics !== false;
      exchangeNext=0;restartDiscovery();
      state.inputGuardDisabled = !value.enabled || state.config.weaponGuard === false;
      state.lastChatText = textPolicy();
      const receipt=value.manualResult,pending=state.manualPending;
      if (pending && receipt && receipt.key === pending.key) {
        if (receipt.status === 'completed') { state.manualPending=null;notice(''); }
        else if (receipt.status === 'cancelled' || receipt.status === 'rejected') { state.manualPending=null;recoverManual(receipt.raw || pending.raw,receipt.message); }
      } else if (pending && value.session !== pending.session) {
        state.manualPending=null;recoverManual(pending.raw,'Подключение изменилось. Проверьте чат перед повтором сохранённого текста.',false);
      }
      if (state.manualPending && clock()-state.manualPending.at>60000) { const raw=state.manualPending.raw;state.manualPending=null;recoverManual(raw,'Подтверждение PA не получено. Текст сохранён; проверьте чат перед повтором.',false); }
      if (value.policyUnchanged !== true) syncFieldLimit();
      updateLayoutBadge();
    } catch (error) {
      if (state.stopped || url !== state.url) return;
      state.failures=Math.min(32,state.failures+1);
      exchangeNext=clock()+Math.min(30000,750*Math.pow(2,state.failures-1));
      if(state.failures===1)restartDiscovery();
      const code = error && /^(http_\d{3}|bad_response|handshake_failed)$/u.test(error.message) ? error.message : 'network';
      if (state.lastError !== code && state.diagnostics) {
        state.lastError = code;
        if (root.console && typeof root.console.warn === 'function') root.console.warn('[PA26 CEF] exchange_failed: ' + code);
      }
      if (state.failures >= 3) { state.config = null; state.until = 0; state.queue = []; }
    } finally {
      root.clearTimeout(timeout); state.pending = false;
      if(!state.stopped){if(state.inputDirty)inputChanged();else if(url!==state.url || (state.inputSequence || 0)!==inputSequence)Promise.resolve().then(exchange);}
    }
  }
  function loadEndpoint() {
    if (endpointRequest || state.stopped || endpointDormant || state.url && state.failures===0 && (config() || state.pending)) return;
    const now = clock();
    if (now < endpointNext) return;
    if (endpointAttempts > endpointRetryDelays.length) {endpointDormant=true;return;}
    endpointNext=now+(endpointRetryDelays[endpointAttempts] || 60000);endpointAttempts++;
    const script = doc.createElement('script');
    script.src = 'pa26-chat-endpoint.js?pa26=' + root.Date.now();
    let finished=false;
    const done = () => {
      if(finished)return;finished=true;root.clearTimeout(timeout);
      script.onload=null;script.onerror=null;script.remove();endpointRequest=null;
    };
    const timeout=root.setTimeout(done,2000);
    endpointRequest={done};
    script.onload = done; script.onerror = done;
    try {(doc.head || doc.documentElement).appendChild(script);}catch (_) {done();}
  }
  const api = root.PA26Chat = {
    endpoint(value, compatibility) {
      if (state.stopped) return;
      if (typeof value !== 'string' || !/^http:\/\/127\.0\.0\.1:\d{1,5}\/[a-f0-9]{48}\/exchange$/u.test(value)) return;
      const port = Number(value.split(':')[2].split('/')[0]);
      if (port < 1 || port > 65535) return;
      if (value !== state.url) {
        discoverCef(true);restartDiscovery();state.failures=0;exchangeNext=0;
        if(state.manualPending){const raw=state.manualPending.raw;state.manualPending=null;recoverManual(raw,'Подключение PA изменилось. Проверьте уже переданные части перед повтором; исходный текст сохранён.',false);}
        state.url = value; state.config = null; state.queue = []; state.until = 0; syncFieldLimit(); updateLayoutBadge();
        state.compatibility=compatibility&&compatibility.protocol===2&&typeof compatibility.challenge==='string'&&/^[a-f0-9]{48}$/u.test(compatibility.challenge)&&typeof compatibility.fingerprint==='string'&&compatibility.fingerprint.length<=120
          ?{...compatibility,phase:'hello',ready:false,startedAt:clock(),state:'CONTRACT_COMPATIBLE'}:null;
      }
      exchange();
    },
    // Exposed for bounded, offline tests; no page-wide network or game API is exposed.
    wireSize, prepare, exchange() { state.inputDirty=true;return exchange(); }, inputState() { state.visibleCache=new WeakMap();return inputState(); }, updateLayoutBadge() { hookInput();state.inputDirty=true;updateLayoutBadge(); }, manualSubmission, submitted, manualBusy:()=>!!state.manualPending,
    reconnect() {if(state.stopped)return;restartDiscovery();exchangeNext=0;discoverCef(true);loadEndpoint();return exchange();},
    stop() { if (state.manualPending) recoverManual(state.manualPending.raw,'PA остановлен. Проверьте уже переданные части перед повтором.',false);const input=field();if (input && state.originalMaxLength !== undefined) input.maxLength=state.originalMaxLength;state.stopped = true;if(cefRetryTimer!==null)root.clearTimeout(cefRetryTimer);cefRetryTimer=null;if(endpointRequest)endpointRequest.done();if (state.inputObserver) state.inputObserver.disconnect();if(state.dialogObserver)state.dialogObserver.disconnect();if(state.ancestorObserver)state.ancestorObserver.disconnect();if(root.clearInterval)root.clearInterval(state.heartbeat);state.config = null; state.lastChatText = null; state.until = 0; updateLayoutBadge(); }
  };
  discoverCef();
  // Text, selection and caret are owned by the HUD. Analyze only on submission.
  doc.addEventListener('compositionstart', event => { if (event.target === field()) state.composing = true; }, true);
  doc.addEventListener('compositionend', event => { if (event.target === field()) state.composing = false; }, true);
  doc.addEventListener('keydown', event => {
    if (state.stopped || !runtimeReady()) return;
    if (event.key === 'F6' || event.key === 'Escape' || (event.key === 't' || event.key === 'T') && !panelOpen()) {
      inputChanged();
    }
    if (event.key !== 'Enter') return;
    hookSubmit();
    if (active() && (event.isComposing || state.composing)) { event.stopImmediatePropagation(); return; }
    if (active() && !event.isComposing && !state.composing) {
      if (state.manualPending) { event.preventDefault();event.stopImmediatePropagation();notice('Предыдущее сообщение ещё отправляется. Новый ввод сохранён.');return; }
      const el = field();
      const body = el && state.owned && el.value.startsWith(state.owned) ? el.value.slice(state.owned.length) : el && el.value;
      const result = el && submitted(body);
      if (result && result.error) { state.rejected = Math.min(1000000, state.rejected + 1); event.preventDefault(); event.stopImmediatePropagation(); notice(result.error); return; }
      if (state.submits.filter(ticket => clock() - ticket.at <= 5000).length >= 8) {
        event.preventDefault(); event.stopImmediatePropagation(); notice('Дождитесь отправки предыдущего сообщения. Текст сохранён в поле.'); return;
      }
    }
  }, true);
  doc.addEventListener('focusin', inputChanged, true);
  doc.addEventListener('focusout', inputChanged, true);
  doc.addEventListener('DOMContentLoaded', () => { discoverCef(); hookInput(); hookSubmit(); loadEndpoint(); });
  doc.addEventListener('visibilitychange', resumeDiscovery);
  if (typeof root.addEventListener === 'function') root.addEventListener('focus', resumeDiscovery);
  state.heartbeat=root.setInterval(() => {
    if (state.stopped) return;
    // Only discovery/reconnection and a small lease heartbeat. No draft reads,
    // style queries, geometry or layout writes while the editor is unchanged.
    if (!state.hooked) hookSubmit();
    if (!state.observedPanel || state.observedPanel.isConnected===false || state.guardedField && state.guardedField.isConnected===false) inputChanged();
    exchange(); updateLayoutBadge();loadEndpoint();
  }, 750);
  hookInput();
  state.inputDirty=true;readInput();
  if (doc.readyState !== 'loading') { hookSubmit(); loadEndpoint(); }
  return api;
});
