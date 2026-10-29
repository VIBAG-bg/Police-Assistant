-- Per-situation draft; persistent defaults and the accepted executor plan stay separate.
local model=require 'pa26_bindings';local grounds=require 'pa26_operational';local prefs=require 'pa26_copilot_settings'
local common=require 'pa26_procedure_window';local M={}
function M.draw(s,ui,data,cb)
 local f=s.groundForm;if not f then ui.text('Выберите действие причины остановки или задержания.');return end
 s.currentUi=ui;s.currentNoticeScope='vehicle';s.preferenceContext=false
 s.groundPage=s:choice('Основание##ground-page',s.groundPage or'form',{{'form','Выбрать и озвучить'},{'settings','Настройки и RP'}},ui)
 if s.groundPage=='settings'then
  s.preferenceContext=true;s.settingTextChanged=false
  local lib=s.vehicleDraft or model.copy(s.lib.vehicle);local d=lib.copilot
  for _,r in ipairs(prefs.booleans)do if r[1]:match('^ground_')then d[r[1]]=common.check(s,ui,r[2]..'##ground-default-'..r[1],d[r[1]])end end
  d.ground_channel=s:choice('Канал речи##ground-channel',d.ground_channel or'/s',{{'','Обычный чат'},{'/s','Речь /s'}},ui)
  for _,r in ipairs(prefs.templates)do if({intro=true,badge=true,explain_stop=true,documents=true,explain_detention=true,miranda=true,rights_extra=true})[r[1]]then
   d.templates[r[1]]=s:field(r[2]..'##ground-template-'..r[1],'ground-template:'..r[1],d.templates[r[1]],8192,true,80)
   local value,why=cb.copilotPreview(r[1],d);ui.text('Предпросмотр: '..tostring(value or why))
  end end
  ui.text('Переменные: {rank}, {my_name}, {station}, {driver_id}, {driver_name}, {stop_ground}, {detention_ground}, {ground_article}. Род: {gender:мужской|женский}. Каналы речи и интервалы используют настройки Copilot.')
  s.vehicleDraft=lib;s:autoSettings('vehicle',{'vehicle'},lib,'vehicleDraft');s:autosaveHint(ui,'vehicle')
  ui.text('Изменение постоянных настроек отменяет прежний предпросмотр. Откройте выбор причины заново.');return
 end
 local t=f.request.groundTarget;ui.text(t.name..' [ID: '..t.id..']')
 local v=data.copilot and data.copilot.values or{};if f.request.groundCar then ui.text((v.vehicle_color or'')..' '..(v.model or'')..' · только текущий случай')else ui.text('Выбранный человек · только текущая ситуация')end
 if not cb.groundValid(f.request)then ui.text('Случай изменился. Повторите выбор причины для текущего человека; старое ДА не будет использовано.');return end
 local kind=f.request.kind;local cfg=f.cfg
 cfg.ground_intro=common.check(s,ui,'Сначала представиться и показать жетон##ground-intro',cfg.ground_intro)
 if cfg.ground_intro then cfg.ground_ud=common.check(s,ui,'Также показать удостоверение командой /ud##ground-ud',cfg.ground_ud)end
 if kind=='detention'then
  cfg.ground_miranda=common.check(s,ui,'Зачитать полную Миранду и разъяснение прав##ground-miranda',cfg.ground_miranda)
  if not cfg.ground_miranda then ui.text('Исключайте повтор только если права уже разъяснены в этой сцене. Этот выбор не отменяет обязанность разъяснить права.')end
 end
 s.groundSearch=s:field('Найти причину или статью##ground-search','ground:search',s.groundSearch or'',512)
 local q=model.casefold(s.groundSearch):gsub('ё','е');local rows={}
 for _,r in ipairs(grounds.rows(kind))do
  if r.id~='none'and(q==''or model.casefold(r.title..' '..(r.article or'')):gsub('ё','е'):find(q,1,true))then rows[#rows+1]=r end
 end
 if s.groundSearchSignature~=q..kind then s.groundListPage=1;s.groundSearchSignature=q..kind end
 local pages=math.max(1,math.ceil(#rows/4));s.groundListPage=math.min(pages,s.groundListPage or 1)
 for n=(s.groundListPage-1)*4+1,math.min(#rows,s.groundListPage*4)do local r=rows[n]
  if s:button((cfg[kind..'_ground']==r.id and'Выбрано · 'or'')..r.title..' · '..(r.article or'')..'##ground-select-'..r.id,ui)then
   cfg[kind..'_ground']=r.id;if kind=='stop'then cfg.stop_branch='none'end
  end
 end
 ui.text('Страница '..s.groundListPage..' / '..pages)
 if s:button('Предыдущие##ground-list-back',ui)then s.groundListPage=math.max(1,s.groundListPage-1)end
 if s:button('Следующие##ground-list-next',ui)then s.groundListPage=math.min(pages,s.groundListPage+1)end
 local row=grounds.find(kind,cfg[kind..'_ground']);if not row or row.id=='none'then return end
 if row.branches then
  local choices={{'none','Уточните условия'}};for _,b in ipairs(row.branches)do choices[#choices+1]=b end
  cfg[kind..'_branch']=s:choice('Условия статьи##ground-branch',cfg[kind..'_branch']or'none',choices,ui)
 end
 if row.id=='custom'then cfg[kind..'_custom']=s:field('Своё фактическое основание##ground-custom','ground:custom:'..kind,cfg[kind..'_custom'],4001,true,80)end
 local ground,why=grounds.ground(kind,cfg[kind..'_ground'],cfg[kind..'_branch'],cfg[kind..'_custom'])
 if not ground then ui.text(why);return end
 if ground.note then ui.text(ground.note)end
 local ak=kind=='stop'and ground.article:match('^АК ст%. (%d+)$');local article=ak and cb.sanctions().byId['AK:'..ak]
 if article then
  local index=1;for i,b in ipairs(row.branches or{})do if b[1]==cfg.stop_branch then index=i;break end end
  local sanction=article.branches[index]
  if sanction then
   ground.sanction_id=article.id;ground.sanction_branch=index;ground.sanction_hash=article.hash
   ui.text('Справка: '..sanction.condition..' · '..sanction.alternative)
  end
  if s:button('Прочитать статью целиком##ground-source',ui)then s.groundSource=not s.groundSource end
  if s.groundSource then ui.text(article.text)end
 end
 ui.text('Основание проверки документов: ЗоП 21, 7 п. 3; Мануал т. 4, 230 «Проверка документов». Выбор статьи сам по себе не доказывает нарушение.')
 local preview,err=cb.groundPreview(f)
 if not preview then ui.text(err);return end
 if s:button('Показать / скрыть точные реплики##ground-preview-toggle',ui)then s.groundPreviewOpen=not s.groundPreviewOpen end
 if s.groundPreviewOpen then for _,line in ipairs(preview.lines)do ui.text(line)end end
 local function offer(handoff)
  local p,e=cb.groundOffer(f,ground,handoff);if p then s.vehicleConfirm=p else s:notify(e,'vehicle',false)end
 end
 if s:button(kind=='stop'and'Озвучить причину и запросить документы · ДА/НЕТ##ground-send'or'Озвучить основание и права · ДА/НЕТ##ground-send',ui)then offer()end
 if kind=='stop'and article and #article.branches>0 and s:button('Озвучить и подготовить штраф##ground-next-fine',ui)then offer('fine')end
 if kind=='detention'and s:button('Озвучить и открыть помощник /su##ground-next-wanted',ui)then offer('wanted')end
 ui.text('Сначала предпросмотр и ваше ДА. Следующая форма появится только после завершения RP; сама штраф или розыск не выдаёт.')
end
return M
