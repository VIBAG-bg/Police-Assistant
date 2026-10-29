local common=require 'pa26_procedure_window';local wanted=require 'pa26_wanted_ui';local M={}
function M.draw(s,ui,data,cb)
 s.currentNoticeScope='procedures';s.preferenceContext=false;s.currentUi=ui
 s.markPage=s:choice('Пеленгация##mark-page',s.markPage or'form',{{'form','Пеленгация'},{'rules','Правила'},{'settings','Настройки и RP'}},ui)
 if s.markPage=='settings'then common.settings(s,ui,cb,'mark');return end
 if s.markPage=='rules'then
  ui.text('Регламент 6.9–6.17: известный по IC телефон и источник, включённое устройство, RP перед /setmark. ID не является номером телефона.')
  ui.text('OOC-звёзды допускаются только для технической пеленгации; сразу после её завершения их нужно снять. Для /pt и Alcatraz они запрещены. После собственной смерти в той же ситуации выдавать их нельзя; ранение и реанимация смертью не считаются.')
  ui.text('При существующем IC-розыске: только RP + /setmark. Технический /su и /clear в этой ветке не используются.')
  if s:button('Открыть полный действующий регламент##mark-source',ui)then s.markRuleSource=true end
  if s.markRuleSource then for _,line in ipairs(cb.trackingRules())do ui.text(line)end end
  return
 end
 local reminders=data.caseForms and data.caseForms.reminders or{}
 if #reminders>0 then
  ui.text('Незавершённых проверок технических звёзд: '..#reminders..'. Снятие и результат требуют отдельной проверки.')
  if s:button('Проверить выдачу / метку / снять OOC-звёзды##mark-review',ui)then s.markReview=not s.markReview end
 end
 if s.markReview then
  wanted.review(s,ui,data,cb)
  if s:button('Новая пеленгация##mark-review-back',ui)then s.markReview=false end;return
 end
 if not s.lib.procedures.enabled or not s.lib.procedures.mark_enabled then ui.text('Формы выключены. Включение доступно в «Настройки и RP»; сохранённый выбор не заменяется.')end
 local f=s.caseForm
 if not f or f.kind~='mark'then common.target(s,ui,cb,'setmark');return end
 if not common.header(s,ui,f,cb)then common.target(s,ui,cb,'setmark');return end
 if f.stage=='identity'then
  common.field(s,f,'Известный IC-номер телефона','phone_number',512)
  local preset,changed=s:choice('Источник IC-номера##mark-phone-source',s.markPhonePreset or'none',
   {{'none','Выбрать источник'},{'База данных КПК / справочник','КПК / справочник'},{'Материалы дела / допрос','Материалы дела'},{'Вызов 9-1-1','Вызов 9-1-1'},{'Личный контакт / визитка','Контакт / визитка'}},ui)
  s.markPhonePreset=preset
  if changed and preset~='none'then f.phone_source=preset;s.cache['procedure:mark:'..f.id..':phone_source']=nil end
  common.field(s,f,'Уточнить источник номера','phone_source',1024,true)
  common.question(s,f,ui,'Номер известен персонажу по RP?','phone_known')
  common.question(s,f,ui,'Телефон сейчас включён?','phone_active')
  if s:button('Далее · исходный розыск##mark-next-phone',ui)then
   if f.phone_known~='yes'or f.phone_active~='yes'or not f.phone_number:match('%S')or not f.phone_source:match('%S')then common.error(s,'Подтвердите IC-номер, источник и включение телефона.')else f.stage='basis'end
  end
 elseif f.stage=='basis'then
  common.question(s,f,ui,'Сейчас у человека есть IC-розыск?','prior_ic_stars')
  if f.prior_ic_stars=='yes'then
   f.mode='ic';ui.text('Только RP + /setmark. Существующие IC-звёзды не изменяются.')
  elseif f.prior_ic_stars=='no'then
   f.mode='ooc';ui.text('Технические OOC-звёзды нужны только для /setmark. После результата — RP и снятие; использование для /pt и Alcatraz запрещено.')
   f.reason_id=s:choice('Технический пункт /su##mark-technical',f.reason_id~=''and f.reason_id or'08.01',{{'08.01','08.01 · 2 звезды'},{'08.02','08.02 · 1 звезда'}},ui)
   f.life_ack=common.check(s,ui,'Основание относится к текущей жизни; не использую сведения до смерти##mark-life',f.life_ack)
   f.ooc_ack=common.check(s,ui,'Понимаю техническую цель и сниму OOC-звёзды после пеленгации##mark-ooc',f.ooc_ack)
   ui.text('Регламент допускает любой игровой пункт для технической цели. Другие пункты можно выбрать в обычном помощнике OOC-розыска.')
  else ui.text('Проверьте исходный розыск. «Не знаю» не разрешает ни выдачу технических звёзд, ни снятие розыска.')end
  if s:button('Подготовить RP и команду##mark-preview',ui)then
   if f.prior_ic_stars=='yes'then f.basis='RP-пеленгация по известному IC-телефону';f.stage='preview'
   elseif f.prior_ic_stars=='no'then
    local p,why=cb.trackingOffer(f);if p then s.caseConfirm=p else common.error(s,why)end
   else common.error(s,'Сначала проверьте исходный IC-розыск.')end
  end
  if s:button('Назад · IC-телефон##mark-back-phone',ui)then f.stage='identity'end
 else
  common.preview(s,ui,f,cb)
  if s:button('Назад · исходный розыск##mark-back-mode',ui)then f.stage='basis'end
 end
end
return M
