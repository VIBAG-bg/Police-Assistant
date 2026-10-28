-- Shared GUI for statutory grounds and procedural timers. Main handles intents.
local data=require 'pa26_operational'
local M={}
function M.ground(s,ui,cfg,kind,callbacks)
 local key=kind..'_ground';local previous=cfg[key]
 cfg[key]=s:choice((kind=='stop'and'Причина остановки'or'Основание задержания')..'##ground-'..kind,cfg[key],data.choices(kind),ui)
 if previous~=cfg[key]and kind=='stop'then cfg.stop_branch='none'end
 local r=data.find(kind,cfg[key]);if not r then return end
 if r.branches then
  local choices={{'none','Выберите ветвь'}};for _,b in ipairs(r.branches)do choices[#choices+1]=b end
  cfg.stop_branch=s:choice('Ветвь статьи##stop-branch',cfg.stop_branch,choices,ui)
 end
 if r.id=='custom'then cfg[kind..'_custom']=s:field('Своё основание##ground-custom-'..kind,'ground:custom:'..kind,cfg[kind..'_custom'],4001,true,80)end
 if r.article then ui.text(r.article)end;if r.note then ui.text(r.note)end
 local g,err=data.ground(kind,cfg[key],cfg[kind..'_branch'],cfg[kind..'_custom'])
 ui.text(g and('Предпросмотр основания: '..g.title..' · '..g.article)or err)
 if g and callbacks and callbacks.groundHandoff then
  if s:button((kind=='stop'and'Передать в форму штрафа'or'Открыть помощник /su с этим основанием')..'##ground-handoff-'..kind,ui)then
   local ok,why=callbacks.groundHandoff(g,kind=='stop'and'fine'or'wanted');if not ok then s:notify(why,'vehicle',false)end
  end
 end
end
function M.timers(s,ui,data,callbacks)
 local t=data.detentionTimers or{};s:settingsHeading(ui,'Адвокат и звонок')
 ui.text('Мануал т. 4, 210: ответ адвоката — 5 мин; прибытие после ответа — 10 мин; звонок — до 3 мин. Длительности меняются в настройках и явно помечаются как личные. Таймер не подтверждает результат на сервере.')
 local function action(id,label)
  if callbacks.detentionAction and s:button(label..'##rights-'..id,ui)then callbacks.detentionAction(id)end
 end
 if not t.id then action('begin','Начать процедуру для выбранного человека');return end
 ui.text(t.target.name..' [ID '..t.target.id..'] · процедура '..t.id)
 ui.text(t.title..(t.remaining and string.format(' · %d:%02d',math.floor(t.remaining/60),t.remaining%60)or'')..(t.official==false and' · личная длительность'or''))
 if t.frozen then ui.text('По Мануалу процессуальный час заморожен до приезда адвоката. Общий 60-минутный срок PA не создаёт.')end
 if not t.lawyer_requested and(t.stage=='ready'or t.stage=='phone_done')then action('lawyer_request','Адвокат вызван · начать ожидание ответа')end
 if t.stage=='lawyer_response'then action('lawyer_answered','Адвокат ответил · ждать прибытие')end
 if t.stage=='lawyer_arrival'then action('lawyer_arrived','Адвокат прибыл')end
 if t.stage=='lawyer_response'or t.stage=='lawyer_arrival'then action('lawyer_unavailable','Получен ответ: нет доступных адвокатов / не сможет прибыть')end
 if not t.phone_used and not require('pa26_detention_timers').stages[t.stage]then action('phone_start','Звонок начат · запустить таймер')end
 if t.stage=='phone_call'then action('phone_finished','Звонок завершён досрочно / прекращён по фактическому основанию')end
 if t.expired then
  ui.text('Срок истёк. Перед продолжением проверьте, что ответа / прибытия действительно нет или звонок закончен.')
  action(t.stage=='phone_call'and'phone_timeout_verified'or'lawyer_timeout_verified','Проверил результат в игре · отметить этап')
 end
 if callbacks.openAssist and s:button('Открыть фиксацию /time + F8 · с предпросмотром##rights-evidence',ui)then callbacks.openAssist('evidence')end
 action('finish','Завершить эту процедуру')
end
return M
