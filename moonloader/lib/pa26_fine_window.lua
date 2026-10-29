local common=require 'pa26_procedure_window';local sanctions=require 'pa26_sanctions';local M={}
function M.draw(s,ui,data,cb)
 s.currentNoticeScope='procedures';s.preferenceContext=false;s.currentUi=ui
 s.finePage=s:choice('Штраф##fine-page',s.finePage or'form',{{'form','Оформление'},{'catalog','Справочник АК'},{'settings','Настройки и RP'}},ui)
 local f=s.caseForm;local cfg=s.lib.procedures
 if s.fineSource then
  if s:button('Назад##fine-source-back',ui)then s.fineSource=nil end
  local r=cb.sanctions().byId[s.fineSource];if r then ui.text(r.text);ui.text('Источник: '..r.source.url..' · редакция из базы знаний')end;return
 end
 if s.finePage=='settings'then common.settings(s,ui,cb,'fine');return end
 if s.finePage=='catalog'then common.catalog(s,ui,cb,f and f.kind=='fine'and f or nil);return end
 if not cfg.enabled or not cfg.fine_enabled then
  ui.text('Помощник штрафа выключен. Включите формы в «Настройки и RP». Сохранённый выбор не меняется автоматически.')
 end
 if not f or f.kind~='fine'then common.target(s,ui,cb,'ticket');return end
 if not common.header(s,ui,f,cb)then common.target(s,ui,cb,'ticket');return end
 if f.fromStopReason then ui.text('Основание подставлено из этой остановки. Ручные правки остаются вашими.')end
 ui.text('Личность → Статья и сумма → Предпросмотр')
 if f.stage=='identity'then
  if cfg.fine_unmasked then common.question(s,f,ui,'Лицо скрыто маской?','mask')end
  common.question(s,f,ui,'Паспорт этого человека проверен?','passport_seen')
  if f.passport_seen=='yes'then
   if f.ic_name==''then f.ic_name=f.target.name:gsub('_',' ')end
   common.field(s,f,'Имя из проверенного документа','ic_name')
  elseif f.passport_seen=='no'then
   if not cfg.fine_unmasked then common.question(s,f,ui,'На человеке маска?','mask')end
   if f.mask=='yes'then common.question(s,f,ui,'Личность установлена до маски и человек не терялся из виду?','face_before')end
   common.field(s,f,'Известные IC-приметы','appearance',2048,true)
  end
  if s:button('Далее · основание##fine-next-identity',ui)then local ok,why=cb.caseNext(f);if not ok then common.error(s,why)end end
 elseif f.stage=='basis'then
  if s:button('Выбрать статью из базы знаний##fine-open-catalog',ui)then s.finePage='catalog'end
  common.sanction(s,ui,cb,f)
  local branch=cb.sanctions():branch(f.sanction_id,f.sanction_branch)
  if branch and cfg.pm_rate>0 then
   ui.text('Личная памятка: 1 ПМ = '..cfg.pm_rate..' $. Это расчёт, а не серверный тариф.')
   for _,r in ipairs({{'min','Минимум'},{'mid','Середина'},{'max','Максимум'}})do
    local amount=sanctions.money(branch,cfg.pm_rate,r[1])
    if amount and s:button(r[2]..' · '..amount..' $##fine-money-'..r[1],ui)then f.amount=amount;s.cache['procedure:fine:'..f.id..':amount']=nil end
   end
  else ui.text('Сумма вводится вручную. Курс ПМ можно задать в настройках; по умолчанию расчёт отключён.')end
  common.field(s,f,'Сумма штрафа, $','amount',64)
  common.field(s,f,'Причина для серверной команды','basis',1024,true)
  if s:button('Проверить текст##fine-preview',ui)then local ok,why=cb.caseNext(f);if not ok then common.error(s,why)end end
  if s:button('Назад · личность##fine-back-identity',ui)then f.stage='identity'end
 else
  common.preview(s,ui,f,cb)
  if s:button('Изменить статью и сумму##fine-back-basis',ui)then f.stage='basis'end
 end
end
return M
