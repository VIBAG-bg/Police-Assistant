local model=require 'pa26_bindings';local prefs=require 'pa26_procedure_settings';local sanctions=require 'pa26_sanctions'
local M={}
function M.check(s,ui,label,value)
 local v,changed=s:check('##'..label,value)
 s.imgui.SameLine(0,8);ui.text(label:match('^(.-)##')or label)
 return v,changed
end
function M.error(s,why)s:notify(why or'Проверьте заполненные сведения.','procedures',false)end
function M.field(s,f,label,key,size,multi)
 f[key]=s:field(label..'##procedure-'..key,'procedure:'..f.kind..':'..f.id..':'..key,f[key]or'',size or 1024,multi,multi and 78 or nil)
end
function M.question(s,f,ui,label,key)
 f[key]=s:choice(label..'##procedure-'..key,f[key]or'unknown',{{'unknown','Не знаю'},{'yes','Да'},{'no','Нет'}},ui)
end
function M.target(s,ui,cb,head)
 local key=head..'TargetId';s[key]=s:field('ID игрока##procedure-target-'..head,'procedure-target:'..head,s[key]or'',16)
 if s:button('Выбрать ID##procedure-target-select-'..head,ui)then cb.procedureInput(head,s[key])end
 if s:button('Текущий водитель / выбранный человек##procedure-target-current-'..head,ui)then cb.procedureInput(head,'')end
end
function M.header(s,ui,f,cb)
 if not f then return false end
 ui.text(f.target.name..' [ID: '..f.target.id..']')
 if cb.caseValid and not cb.caseValid(f)then
  ui.text('Эта форма больше не разрешает отправку: изменился человек, сцена или процедура уже начата. Выберите ID заново.')
  return false
 end;return true
end
function M.preview(s,ui,f,cb)
 local p,why=cb.casePreview(f)
 if not p then ui.text(why);return end
 for _,line in ipairs(p.lines)do ui.text(line)end
 if not p.ready then ui.text(p.warning);return end
 local label=f.kind=='fine'and'Отыграть · затем подтвердить команду'or'Подтвердить RP и /setmark'
 if s:button(label..'##procedure-send-'..f.kind,ui)then
  local offer,err=cb.caseOffer(f);if offer then s.caseConfirm=offer else M.error(s,err)end
 end
end
function M.settings(s,ui,cb,kind)
 s.preferenceContext=true;s.settingTextChanged=false
 local cfg=s.caseDraft or model.copy(s.lib.procedures);local im=s.imgui
 local layout=model.copy(s.lib.settings.window_layout)
 local separate,changed=M.check(s,ui,'Использовать отдельное окно##procedure-separate',layout[kind..'_separate'])
 if changed then local lib=model.copy(s.lib);layout[kind..'_separate']=separate;lib.settings.window_layout=layout;local ok,why=cb.save(lib,{scope='window_layout'});if not ok then M.error(s,why)end end
 cfg.enabled=M.check(s,ui,'Включить формы штрафа и пеленгации##procedure-enabled',cfg.enabled)
 cfg[kind..'_enabled']=M.check(s,ui,'Включить '..(kind=='fine'and'штраф'or'пеленгацию')..'##procedure-kind-enabled',cfg[kind..'_enabled'])
 cfg[kind..'_intercept']=M.check(s,ui,'Открывать это окно при ручной команде##procedure-intercept',cfg[kind..'_intercept'])
 ui.text('Если формы или перехват выключены, ручная команда сохраняет прежнее поведение стандартных RP / сервера. Кнопка меню открывает настройки независимо от этого выбора.')
 if kind=='fine'then
  cfg.fine_unmasked=M.check(s,ui,'Для штрафа требовать открытое лицо##procedure-unmasked',cfg.fine_unmasked)
  ui.text('Личная памятка: 1 ПМ в $');im.PushItemWidth(-1);local n=im.new.int(cfg.pm_rate);if im.InputInt('##procedure-pm',n)then cfg.pm_rate=n[0]end;im.PopItemWidth()
  ui.text('0 — не считать. Курс задаёте вы; это не подтверждённый серверный тариф. Середина диапазона округляется до целого $, половина вверх.')
 end
 ui.text('Пауза RP, мс');im.PushItemWidth(-1);local delay=im.new.int(cfg.delay_ms);if im.InputInt('##procedure-delay',delay)then cfg.delay_ms=delay[0]end;im.PopItemWidth()
 ui.text('1000–10000 мс. Общий интервал PA тоже учитывается.')
 for _,k in ipairs(kind=='mark'and{'mark','clear'}or{'fine'})do
  s:settingsHeading(ui,'Серверная команда · '..prefs.names[k])
  cfg[k..'_command']=s:field('Шаблон команды##procedure-command-'..k,'procedure-settings:command:'..k,cfg[k..'_command'],1024)
  ui.text('Переменные: {id}, {amount}, {basis}, {article}, {part}, {phone_number}. Не подставляйте постоянный ID.')
  ui.text('Предпросмотр: '..tostring(cb.caseTemplatePreview(cfg[k..'_command'],s.caseForm)))
  cfg[k..'_source']=s:field('Где подтверждено##procedure-source-'..k,'procedure-settings:source:'..k,cfg[k..'_source'],1024)
  cfg[k..'_verified']=M.check(s,ui,'Синтаксис проверен##procedure-verified-'..k,cfg[k..'_verified'])
 end
 if kind=='mark'then ui.text('/clear может затронуть весь розыск. Остаются проверка отсутствия IC-звёзд, подтверждение и проверка результата. OOC-звёзды не используются для /pt или Alcatraz.')end
 s:settingsHeading(ui,'Ваши RP-тексты')
 ui.text('Отдельные строки /me, /do, /todo текст*действие. Переменные: {ic_name}, {passport_number}, {appearance}, {id}, {amount}, {basis}, {article}, {part}, {phone_number}, {phone_source}; {gender:мужской|женский}.')
 for _,r in ipairs(prefs.rpFields)do
  if r[1]:match('^'..kind..'_')or kind=='mark'and(r[1]=='clear_chain_rp'or r[1]=='wanted_ooc_rp')then
   cfg[r[1]]=s:field(r[2]..'##procedure-rp-'..r[1],'procedure-settings:rp:'..r[1],cfg[r[1]],8192,true,80)
   ui.text('Предпросмотр: '..tostring(cb.caseTemplatePreview(cfg[r[1]],s.caseForm)))
  end
 end
 s.caseDraft=cfg;s:autoSettings('procedures',{'procedures'},cfg,'caseDraft');s:autosaveHint(ui,'procedures')
end
function M.sanction(s,ui,cb,form)
 local catalog=cb.sanctions();local row=catalog.byId[form.sanction_id]
 if not row then ui.text('Статья пока не выбрана. Сумма и причина остаются вашими; справочник доступен отдельно.');return end
 ui.text(row.article..' · '..row.title)
 local choices={};for i,b in ipairs(row.branches)do choices[#choices+1]={i,i..'. '..b.min..'–'..b.max..' ПМ · '..b.condition:gsub('\n',' ')}end
 local index,changed=s:choice('Ветвь санкции##fine-branch',form.sanction_branch or 1,choices,ui)
 if changed then sanctions.select(form,row,index);s.cache['procedure:fine:'..form.id..':basis']=nil end
 local b=row.branches[form.sanction_branch or 1];if not b then return end
 ui.text('Условия: '..b.condition);ui.text('По источнику: '..b.alternative)
 ui.text('Выбор ветви не доказывает нарушение. Полный источник включает дополнительные условия и последствия.')
 if s:button('Полный текст статьи##fine-source',ui)then s.fineSource=row.id end
end
function M.catalog(s,ui,cb,form)
 local catalog=cb.sanctions()
 s.fineCategory=s:choice('Раздел АК##fine-category',s.fineCategory or'road',{{'all','Все'},{'road','Дорога'},{'order','Порядок'},{'police','Оружие и полиция'}},ui)
 s.fineSearch=s:field('Номер статьи или слово##fine-search','fine:search',s.fineSearch or'',512)
 local signature=s.fineCategory..'\0'..s.fineSearch
 if s.fineSearchSignature~=signature then s.fineCatalogPage=1;s.fineSearchSignature=signature end
 local rows=catalog:search(s.fineSearch,s.fineCategory);local pages=math.max(1,math.ceil(#rows/4))
 s.fineCatalogPage=math.min(pages,s.fineCatalogPage or 1);ui.text('Статей: '..#rows..' · страница '..s.fineCatalogPage..' / '..pages)
 for n=(s.fineCatalogPage-1)*4+1,math.min(#rows,s.fineCatalogPage*4)do local r=rows[n]
  s.imgui.Separator();ui.text(r.article..' · '..r.title)
  for i,b in ipairs(r.branches)do ui.text(i..'. '..b.min..'–'..b.max..' ПМ · '..b.condition:gsub('\n',' '))end
  if #r.branches==0 then ui.text('Денежная ветвь здесь не выделена. Откройте первоисточник.')end
  if s:button('Источник##fine-source-'..r.id,ui)then s.fineSource=r.id end
  if form and #r.branches>0 and s:button('Выбрать для штрафа##fine-select-'..r.id,ui)then
   sanctions.select(form,r,1);s.cache['procedure:fine:'..form.id..':basis']=nil;form.stage='basis';s.finePage='form'
  end
 end
 if s:button('Предыдущие##fine-catalog-back',ui)then s.fineCatalogPage=math.max(1,s.fineCatalogPage-1)end
 if s:button('Следующие##fine-catalog-next',ui)then s.fineCatalogPage=math.min(pages,s.fineCatalogPage+1)end
end
return M
