-- Manual server actions: capture once, ask, then use the ordinary guarded executor.
-- No sends from render callbacks, no simulated server dialogs, no argument rewriting.
local core=require 'pa26_core'
local M={};local Controller={};Controller.__index=Controller
local excluded={su=true,wanted=true,r=true,rn=true,f=true,fn=true,d=true,df=true,m=true,n=true,b=true,me=true,do_=true,try=true,todo=true}
local targets={cuff=true,uncuff=true,push=true,hold=true,unhold=true,frisk=true,unmask=true,ticket=true,takelic=true,arrest=true,pt=true,unpt=true}
M.targetHeads=targets
local standard={
 cuff='/me снял наручники с пояса и зафиксировал их на запястьях задержанного.\n/do Фиксация наручников проверена.',
 uncuff='/me вставил ключ в замок, расстегнул наручники и убрал их в подсумок.',
 frisk='/me надел перчатки и последовательно проверил одежду и карманы задержанного.',
 unmask='/me аккуратно снял маску с лица задержанного и убрал её в пакет для имущества.',
 push='/me открыл дверь служебного автомобиля и, придерживая задержанного, усадил его внутрь.',
 hold='/me взял задержанного под локоть и подготовился сопроводить его за собой.',
 unhold='/me остановился и отпустил руку сопровождаемого.',
 arrest='/me оформил материалы задержания и передал их вместе с задержанным дежурному.',
 ticket='/me заполнил постановление о штрафе, сверил внесённые сведения и подготовил его к выдаче.',
 clear='/me открыл служебную базу и оформил запрос на прекращение розыска.',
 pt='/me активировал служебный терминал и передал диспетчеру сведения о начале преследования.',
 unpt='/me передал диспетчеру сведения о завершении преследования и закрыл запись в терминале.',
 setmark='/me ввёл известный по RP номер телефона в служебный терминал и запросил пеленгацию.\n/do На терминале отображается запрос на определение местоположения по сигналу телефона.',
 ud='/me достал служебное удостоверение, раскрыл его и продемонстрировал собеседнику.',
 takelic='/me оформил изъятие водительского удостоверения и внёс сведения в служебную запись.',
 take='/me надел перчатки, подготовил пакеты для изъятого имущества и приступил к оформлению протокола.'}
function M.specs()
 local out={};for _,row in ipairs(require('pa26_server_commands').commands)do
  local head=row[1]:sub(2);if not excluded[head]then out[#out+1]={head=head,title=row[2],target=targets[head]==true}end
 end;return out
end
function M.defaults()
 local out={enabled=true,rules={}}
 for _,s in ipairs(M.specs())do out.rules[s.head]={enabled=true,prefer_bind=true,
  rp=standard[s.head]or('/me открыл служебный терминал и подготовил действие: '..s.title:lower()..'.')}end
 return out
end
local function validHead(head)return type(head)=='string'and #head<=32 and head:match('^[a-z][a-z0-9_]*$')and not head:match('^pa26')and not excluded[head]and head~='do'end
function M.validate(raw)
 local out=M.defaults();if raw==nil then return out end
 if type(raw)~='table'or type(raw.enabled)~='boolean'or type(raw.rules)~='table'then return nil,'Неверные настройки ручных команд.'end
 out.enabled=raw.enabled;local count=0
 for head,r in pairs(raw.rules)do
  count=count+1
  if count>64 or not validHead(head)or type(r)~='table'or type(r.enabled)~='boolean'or type(r.prefer_bind)~='boolean'or
   type(r.rp)~='string'or #r.rp>4096 or not core.validUtf8(r.rp)or r.rp:find('[%z\1-\8\11\12\14-\31]')then return nil,'Проверьте ручную команду и её RP-шаблон.'end
  local n=0;for line in(r.rp..'\n'):gmatch('(.-)\n')do if line:find('%S')then
   n=n+1;if not line:match('^/me%s+')and not line:match('^/do%s+')and not line:match('^/try%s+')and not line:match('^/todo%s+[^*]+%*[^*]+$')then return nil,'Шаблон ручной команды: только /me, /do, /try и /todo, до 8 строк.'end
  end end
  if n<1 or n>8 then return nil,'Шаблон ручной команды: от 1 до 8 RP-строк.'end
  for token in r.rp:gmatch('{([^{}]+)}')do
   if not token:match('^gender:[^|]*|.*$')and not token:match('^param[1-8]$')and token~='params'and not require('pa26_bindings').variableNames[token]then
    return nil,'Неизвестная переменная ручного RP: {'..token..'}.'
   end
  end
  out.rules[head]={enabled=r.enabled,prefer_bind=r.prefer_bind,rp=r.rp}
 end
 count=0;for _ in pairs(out.rules)do count=count+1 end;if count>64 then return nil,'Не больше 64 ручных команд.'end
 return out
end
function M.rule(lib,head)
 local cfg=lib.settings.manual_actions or M.defaults()
 return cfg.enabled and cfg.rules[head]and cfg.rules[head].enabled and cfg.rules[head]or nil
end
function M.source(lib,head)
 local binder=require 'pa26_binder';local model=require 'pa26_bindings'
 for _,b in ipairs(lib.bindings)do if b.enabled then
  local steps=binder.parse(b.script);local last=steps and steps[#steps]
  if last and last.kind=='message'and last.template:match('^/([A-Za-z0-9_]+)')==head and #steps>1 then
   local safe=true
   for i=1,#steps-1 do local s=steps[i]
    if s.kind~='wait'and(s.kind~='message'or not(s.template:match('^/me%s+')or s.template:match('^/do%s+')or s.template:match('^/try%s+')or s.template:match('^/todo%s+')))then safe=false end
   end
   if safe then local copy=model.copy(b);table.remove(steps);copy.script=binder.toScript(steps);copy.stat='none';return copy end
  end
 end end
end
function M.preview(template)
 return template:gsub('{gender:([^{}|]*)|([^{}]*)}',function(m)return m end):gsub('{([^{}]+)}',function(k)
  if k=='param1'or k=='select_id'then return'37'elseif k=='params'then return'37 пример'elseif k:match('^param%d$')then return'пример'end
  return(k:find('name')or k:find('nick'))and'Иван Петров'or'пример'
 end)
end
function M.plan(lib,head,raw,args,ctx,source,codec,rpSettings)
 local model=require 'pa26_bindings';local binder=require 'pa26_binder'
 local rule=M.rule(lib,head);if not rule then return nil,'Обработка этой команды отключена.'end
 local b=source or model.newBinding(1);if not source then b.name='Ручная /'..head;b.script=rule.rp end
 b.stat='none';b.parameters=b.parameters or{}
 for i,p in ipairs(b.parameters)do args[p.name]=args['param'..i]or''end
 local plan,why=binder.compile(b,ctx,args,codec,math.random,{rpSettings=rpSettings})
 if not plan then return nil,why end
 local wire,wireError=core.encodeWire(raw,codec)
 if not wire then return nil,wireError end
 if #plan.steps>=64 then return nil,'Слишком много шагов перед серверной командой.'end
 plan.steps[#plan.steps+1]={kind='message',text=raw,wire=wire};plan.lines[#plan.lines+1]=raw;plan.has_command=true
 return plan
end
function M.new(env)return setmetatable({env=env,serial=0},Controller)end
function Controller:offer(raw,previouslyCaptured)
 local head,args;if type(raw)=='string'then head,args=raw:match('^/([A-Za-z][A-Za-z0-9_]*)%s*(.-)%s*$')end
 head=head and head:lower();if not head or not validHead(head)then return false end
 local active=M.rule(self.env.library(),head)
 if not active and not previouslyCaptured then return false end
 if self.pending or self.env.busy()then self.env.notice('Предыдущее действие PA ещё не завершено. Новая команда не отправлена.');return true end
 if #raw>1024 or not core.validUtf8(raw)or raw:find('%c')then self.env.notice('Неверный текст команды; отправки не было.');return true end
 local wire=core.encodeWire(raw,self.env.codec)
 if not wire then self.env.notice('Команда длиннее лимита или содержит неподдерживаемые символы; она не отправлена.');return true end
 local s=self.env.state();self.serial=self.serial+1
 self.pending={token=self.serial,raw=raw,head=head,args=args,at=self.env.now(),session=s.session,epoch=self.env.epoch(),demo=s.demo,
  revision=self.env.revision(),account=self.env.account(head,args),ped=s.ped,localId=s.localId,nick=s.nick,passThrough=not active}
 return true
end
function Controller:fresh(p)
 local s=self.env.state();local age=core.elapsed(self.env.now(),p.at)
 return age and age<=(p.approvedAt and 600000 or 60000)and p.session~=nil and s.session==p.session and s.demo==p.demo and s.alive==true and s.focused==true and s.paused==false and
  self.env.epoch()==p.epoch and s.ped==p.ped and s.localId==p.localId and s.nick==p.nick and self.env.revision()==p.revision and self.env.accountValid(p.account)
end
function Controller:decide(token,yes)
 local p=self.pending
 if not p or not p.displayed or p.token~=token or type(yes)~='boolean'then return nil,'Подтверждение устарело.'end
 if p.answer~=nil then return nil,'Решение уже принято.'end
 p.answer=yes;return true
end
function Controller:cancel()self.pending=nil;self.approved=nil end
function Controller:validPlan(plan)
 local p=self.approved;return p and plan.manualCommand and plan.manualCommand.token==p.token and self:fresh(p)or false
end
function Controller:tick()
 local p=self.pending;if not p then return end
 if not self:fresh(p)then self.pending=nil;self.env.close(p.token);self.env.notice('Ручная команда отменена: игрок, настройки или игровая сцена изменились.');return end
 if p.displayed and p.answer==nil and not self.env.showing(p.token)then self.pending=nil;return end
 local s=self.env.state();if s.blocked or s.typing and not s.ownWindow then return end
 if p.passThrough and p.answer==nil then local _,_,noPlan=self.env.prepare(p);p.noPlan=noPlan;p.answer=false end
 if p.answer~=nil then
  self.pending=nil
  local plan=p.answer and p.plan or p.noPlan
  if not plan then self.env.notice(p.error or'Не удалось подготовить RP. Команда не отправлена.');return end
  plan.manualCommand={token=p.token};plan.automatic={kind='manual_command'};p.approvedAt=self.env.now();self.approved=p
  local ok,why=self.env.start(plan);if not ok then self.approved=nil;self.env.notice(why)end;return
 end
 if p.displayed or s.ownWindow or self.env.busy()then return end
 p.plan,p.error,p.noPlan=self.env.prepare(p)
 p.lines={p.raw,'ДА — выполнить показанный RP, затем ровно эту команду. НЕТ — отправить только команду. Esc — отменить всё.',
  p.demo and'ДЕМО: отправок в игру нет.'or'Результат команды определяет сервер. Подтверждение RP не устанавливает IC-личность или известный по RP телефон.'}
 if p.plan then for i=1,#p.plan.lines-1 do p.lines[#p.lines+1]=p.plan.lines[i]end
 else p.lines[#p.lines+1]='RP пока недоступен: '..tostring(p.error)end
 p.displayed=true;self.env.show(p)
end
function M.draw(studio,ui)
 local model=require 'pa26_bindings';local cfg=studio.manualActionsDraft or model.copy(studio.lib.settings.manual_actions or M.defaults())
 studio:settingsHeading(ui,'Ручные серверные команды')
 cfg.enabled=studio:check('Предлагать RP при ручном вводе команды##manual-actions-enabled',cfg.enabled)
 ui.text('ДА — RP и исходная команда; НЕТ — только исходная команда; Esc — отмена. Бинды PA повторно не перехватываются. /su и /wanted используют свой помощник, чат и рация не затрагиваются.')
 local choices={};for head in pairs(cfg.rules)do choices[#choices+1]={head,'/'..head}end;table.sort(choices,function(a,b)return a[1]<b[1]end)
 studio.manualActionHead=studio:choice('Команда##manual-actions-head',studio.manualActionHead or'cuff',choices,ui)
 local head=studio.manualActionHead;local rule=cfg.rules[head]
 if rule then
  rule.enabled=studio:check('Обрабатывать эту команду##manual-action-enabled',rule.enabled)
  rule.prefer_bind=studio:check('Сначала брать RP из подходящего включённого бинда##manual-action-bind',rule.prefer_bind)
  rule.rp=studio:field('RP-шаблон · резерв при отсутствии подходящего бинда##manual-action-rp','manual-action-rp:'..head,rule.rp,8192,true,110)
  local source=rule.prefer_bind and M.source(studio.lib,head)
  ui.text('Источник: '..(source and('бинд «'..source.name..'»; его серверный хвост заменяется введённой командой.')or'RP-шаблон выше.'))
  ui.text('От 1 до 8 строк /me, /do, /try или /todo. Переменные биндов: {param1}…{param8}, {params}, {my_name}, {select_id}, {select_name}. Последние требуют доступного игрока из введённого ID. Лишние серверные команды не исполняются.')
  ui.text('Пример для /'..head..' 37: '..M.preview(source and source.script or rule.rp))
 end
 studio.manualNewHead=studio:field('Другая серверная команда · без /##manual-action-new','manual-action-new',studio.manualNewHead or'',128)
 if studio:button('Добавить команду##manual-action-add',ui)then
  local name=studio.manualNewHead:lower():match('^%s*(.-)%s*$')
  if not validHead(name)then studio:notify('Укажите имя без /, пробелов и параметров. Чат, /su и /wanted используют отдельные обработчики.','commands',false)
  elseif cfg.rules[name]then studio:notify('Эта команда уже есть.','commands',false)
  else cfg.rules[name]={enabled=true,prefer_bind=true,rp='/me подготовил выполнение служебного действия.'};studio.manualActionHead=name end
 end
 studio.manualActionsDraft=cfg;studio:autoSettings('manual_actions',{'settings','manual_actions'},cfg,'manualActionsDraft')
end
return M
