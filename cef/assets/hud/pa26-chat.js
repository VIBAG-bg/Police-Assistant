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
  function prefix() {
    const c = config();
    return c && c.enabled && c.accentEnabled && typeof c.accent === 'string' ? c.accent : '';
  }
  function textPolicy() {
    const c = config(), p = c && c.enabled && c.chatText;
    return p && p.version === 1 && p.keyboardMap && typeof p.keyboardMap === 'object' ? p : null;
  }
  function dotCommand(text, p) {
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
    const panel=doc.getElementById('chatInput');
    return !!(panel && !panel.hidden && panel.isConnected!==false && panel.classList.contains('active'));
  }
  function inputChanged() { state.visibleCache = new WeakMap(); state.inputDirty = true; exchange(); }
  function guardDigit(event) {
    if (!(/^[0-9]$/u.test(event.key || '') || /^(Digit|Numpad)[0-9]$/u.test(event.code || '') ||
        event.keyCode >= 48 && event.keyCode <= 57 || event.keyCode >= 96 && event.keyCode <= 105)) return;
    const c = config();
    if (state.stopped || c && (!c.enabled || c.weaponGuard === false) || state.inputGuardDisabled || !panelOpen() || event.target !== field()) return;
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
      state.observedPanel = panel;
      if (panel && typeof root.MutationObserver === 'function') {
        state.inputObserver = new root.MutationObserver(inputChanged);
        state.inputObserver.observe(panel, {attributes: true, attributeFilter: ['class', 'style', 'hidden']});
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
    return {chat: active(), dialog, busy: active() || dialog || typing || state.cefFocused};
  }
  function updateLayoutBadge() {
    const c = config(), el = field();
    const code = c && c.enabled && c.layoutIndicator === true && c.keyboardLayout;
    if (state.stopped || !active() || !visible(el) || typeof code !== 'string' || !/^[A-Z]{2,3}$/u.test(code)) {
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
    // Advisory only: never modify the user's text, selection or scroll position.
    syncFieldLimit();updateLayoutBadge();
    const el=field();if (!el || state.composing || !active() || state.stopped) return;
    const result=submitted(el.value);
    notice(state.recoveryNotice || result.error || (result.parts && result.parts.length>1 ?
      'После Enter: '+result.parts.length+' части, целые слова и ... на стыках.' : ''));
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
    if (!cef || typeof cef.on !== 'function' || typeof cef.emit !== 'function') return;
    const originalOn = cef.on, originalEmit = cef.emit;
    if (typeof cef.set_focus === 'function') {
      const originalFocus = cef.set_focus;
      cef.set_focus = function (focus, ...args) {
        state.cefFocused = focus === true || focus === 1;
        const result = originalFocus.call(this, focus, ...args); exchange(); return result;
      };
    }
    cef.on = function (name, callback, ...rest) {
      if (name === 'chat:messages' && typeof callback === 'function') {
        const original = callback;
        callback = function (color, text, ...args) {
          if (typeof text === 'string') {
            enqueue('message', text, color); exchange();
            if (filtered(text)) return;
          }
          return original.call(this, color, text, ...args);
        };
      }
      return originalOn.call(this, name, callback, ...rest);
    };
    cef.emit = function (name, text, ...args) {
      if (name !== 'HandleHudSendMessage') return originalEmit.call(this,name,text,...args);
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
  }
  function hookSubmit() {
    if (state.hooked || typeof root.sendMessageToChat !== 'function') return;
    const original = root.sendMessageToChat;
    root.sendMessageToChat = function (text, ...args) {
      if (typeof text !== 'string' || !active()) return original.call(this, text, ...args);
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
    state.hooked = true;
  }
  async function exchange() {
    if (!state.url || state.pending || state.stopped) return;
    state.inputDirty = false;
    state.pending = true;
    const abort = new root.AbortController();
    const timeout = root.setTimeout(() => abort.abort(), 1500);
    try {
      const url = state.url;
      const response = await root.fetch(url, {method: 'POST', cache: 'no-store', signal: abort.signal,
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({schema: 1, page, ...inputState(), events: state.queue.slice(0, 24),
          diagnostics: !state.diagnostics ? undefined : {field: !!field(), sendHook: state.hooked,
            accentConfigured: !!prefix(), applied: state.applied, submitted: state.submitted, rejected: state.rejected}})});
      if (!response.ok) throw Error('http_' + response.status);
      const value = await response.json();
      if (state.stopped || url !== state.url) return;
      if (!value || value.schema !== 1 || !Number.isSafeInteger(value.ack) || typeof value.enabled !== 'boolean') throw Error('bad_response');
      state.queue = state.queue.filter(event => event.id > value.ack);
      state.config = value; state.until = clock() + 2000; state.failures = 0; state.lastError = ''; state.diagnostics = value.diagnostics !== false;
      state.inputGuardDisabled = !value.enabled || value.weaponGuard === false;
      state.lastChatText = textPolicy();
      const receipt=value.manualResult,pending=state.manualPending;
      if (pending && receipt && receipt.key === pending.key) {
        if (receipt.status === 'completed') { state.manualPending=null;notice(''); }
        else if (receipt.status === 'cancelled' || receipt.status === 'rejected') { state.manualPending=null;recoverManual(receipt.raw || pending.raw,receipt.message); }
      } else if (pending && value.session !== pending.session) {
        state.manualPending=null;recoverManual(pending.raw,'Подключение изменилось. Проверьте чат перед повтором сохранённого текста.',false);
      }
      if (state.manualPending && clock()-state.manualPending.at>60000) { const raw=state.manualPending.raw;state.manualPending=null;recoverManual(raw,'Подтверждение PA не получено. Текст сохранён; проверьте чат перед повтором.',false); }
      syncFieldLimit();updateLayoutBadge();
    } catch (error) {
      state.failures++;
      const code = error && /^(http_\d{3}|bad_response)$/u.test(error.message) ? error.message : 'network';
      if (state.lastError !== code && state.diagnostics) {
        state.lastError = code;
        if (root.console && typeof root.console.warn === 'function') root.console.warn('[PA26 CEF] exchange_failed: ' + code);
      }
      if (state.failures >= 3) { state.config = null; state.until = 0; state.queue = []; }
    } finally { root.clearTimeout(timeout); state.pending = false; if (state.inputDirty && !state.stopped) root.setTimeout(exchange, 0); }
  }
  let endpointLoading = false;
  function loadEndpoint() {
    if (endpointLoading || state.stopped || state.url && config() && state.failures===0) return;
    endpointLoading = true;
    const script = doc.createElement('script');
    script.src = 'pa26-chat-endpoint.js?pa26=' + root.Date.now();
    const done = () => { endpointLoading = false; script.remove(); };
    script.onload = done; script.onerror = done;
    (doc.head || doc.documentElement).appendChild(script);
  }
  const api = root.PA26Chat = {
    endpoint(value) {
      if (state.stopped) return;
      if (typeof value !== 'string' || !/^http:\/\/127\.0\.0\.1:\d{1,5}\/[a-f0-9]{48}\/exchange$/u.test(value)) return;
      const port = Number(value.split(':')[2].split('/')[0]);
      if (port < 1 || port > 65535) return;
      if (value !== state.url) { state.url = value; state.config = null; state.queue = []; state.until = 0; updateLayoutBadge(); }
      exchange();
    },
    // Exposed for bounded, offline tests; no page-wide network or game API is exposed.
    wireSize, prepare, exchange, inputState, updateLayoutBadge, manualSubmission, submitted, manualBusy:()=>!!state.manualPending,
    stop() { if (state.manualPending) recoverManual(state.manualPending.raw,'PA остановлен. Проверьте уже переданные части перед повтором.',false);const input=field();if (input && state.originalMaxLength !== undefined) input.maxLength=state.originalMaxLength;state.stopped = true;if (state.inputObserver) state.inputObserver.disconnect();state.config = null; state.lastChatText = null; state.until = 0; updateLayoutBadge(); }
  };
  hookCef();
  // Text, selection and caret are owned by the HUD. Analyze only on submission.
  doc.addEventListener('compositionstart', event => { if (event.target === field()) state.composing = true; }, true);
  doc.addEventListener('compositionend', event => { if (event.target === field()) state.composing = false; }, true);
  doc.addEventListener('keydown', event => {
    if (event.key === 'F6' || event.key === 'Escape' || (event.key === 't' || event.key === 'T') && !panelOpen()) {
      inputChanged(); root.setTimeout(() => { hookInput(); inputChanged(); }, 0);
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
  doc.addEventListener('focusin', () => { hookInput();state.visibleCache=new WeakMap();syncFieldLimit();exchange(); }, true);
  doc.addEventListener('focusout', () => root.setTimeout(exchange, 0), true);
  doc.addEventListener('DOMContentLoaded', () => { hookInput(); hookSubmit(); loadEndpoint(); });
  root.setInterval(() => { hookInput(); hookSubmit(); exchange(); updateLayoutBadge(); if (!active() && (!field() || !field().value.startsWith(state.owned))) state.owned = ''; }, 250);
  root.setInterval(loadEndpoint, 2500);
  hookInput();
  if (doc.readyState !== 'loading') { hookSubmit(); loadEndpoint(); }
  return api;
});
