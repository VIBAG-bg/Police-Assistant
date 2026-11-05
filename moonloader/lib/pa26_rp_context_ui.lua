-- Existing editor and paginated confirmations; never sends or reads game state.
local model=require 'pa26_bindings';local M={}
function M.draw(s,ui,b)
 local c=b.rp_context or{};local changed,v
 s:settingsHeading(ui,'Контекст и этапы RP')
 local function save()b.rp_context=c;s.dirty=true;s.plan=nil end
 local mode=c.vehicle or'off'
 v,changed=s:choice('Вариант транспорта##rp-context',mode,{{'off','Один текст'},{'traffic','Авто / мотоцикл'},{'inspection','Осмотр авто / внешний осмотр мотоцикла'}},ui)
 if changed then c.vehicle=v~='off'and v or nil;save()end
 if c.vehicle=='traffic'then
  ui.text('Основной текст выше — закрытый автомобиль. Модель берётся из выбранной машины Copilot; при неизвестной модели PA покажет оба варианта до запуска.')
  v,changed=s:field('Мотовариант · те же переменные##rp-bike','rp-bike:'..b.id,c.bike_script or'',16385,true,180)
  if changed then c.bike_script=v;save()end
 elseif c.vehicle=='inspection'then ui.text('Для мотоцикла используется существующий текст Copilot «Внешний осмотр мотоцикла». Двери, салон и багажник не отыгрываются. Настройте текст в Copilot → Настройки и тексты.')end
 v,changed=s:check('Имя цели требует установленной IC-личности##rp-identity',c.identity==true)
 if changed then c.identity=v;save()end
 v,changed=s:check('Только общение текущего 10-55 / 10-66##rp-contact',c.contact_phase==true)
 if changed then c.contact_phase=v;save()end
 ui.text('Подтверждения привязаны к номеру реплики, не к строке паузы. ДА отправляет только этот этап; НЕТ / Esc отменяет остаток. «Без предупреждения» эти решения не пропускает. Итоговый текст доступен во вкладке «Запуск».')
 local seconds;seconds,changed=s:field('Ожидание решения, секунд (1–90)##rp-stage-timeout','rp-timeout:'..b.id,tostring((c.approval_timeout_ms or 90000)/1000),8)
 if changed then c.approval_timeout_ms=(tonumber(seconds)or 0)*1000;save()end
 for i,p in ipairs(c.checkpoints or{})do
  local number;number,changed=s:field('Перед репликой №##rp-check-'..i,'rp-check-number:'..b.id..':'..i,tostring(p.before),8)
  if changed then p.before=tonumber(number)or 0;save()end
  v,changed=s:field('Вопрос офицеру##rp-check-'..i,'rp-check-prompt:'..b.id..':'..i,p.prompt,2049,true,72)
  if changed then p.prompt=v;save()end
  if s:button('Удалить подтверждение##rp-check-'..i,ui)then table.remove(c.checkpoints,i);save();break end
 end
 if #(c.checkpoints or{})<16 and s:button('+ Подтверждение этапа##rp-check-add',ui)then
  c.checkpoints=c.checkpoints or{};local used={};for _,x in ipairs(c.checkpoints)do used[x.before]=true end
  local n=1;while used[n]do n=n+1 end
  c.checkpoints[#c.checkpoints+1]={before=n,prompt='Обстановка и факты позволяют передать эту реплику?'};save()
 end
end
function M.variantIntent(v)
 if v.intent then return v.intent end
 local lines={v.binding.name,'У выбранной цели нет достоверного класса транспорта. Выберите подходящий вариант после проверки сцены. Esc — ничего не отправлять.'}
 for _,choice in ipairs({'car','bike'})do
  lines[#lines+1]=choice=='car'and'ЗАКРЫТЫЙ АВТОМОБИЛЬ'or'МОТОЦИКЛ / ВНЕШНИЙ ОСМОТР'
  local b,why=require('pa26_rp_context').resolve(v.binding,v.stamp,choice)
  local plan
  if b then plan,why=require('pa26_binder').compile(b,v.snapshot,v.request.args,v.codec,nil,{rpSettings=v.rpSettings})end
  if plan then for _,line in ipairs(plan.lines)do lines[#lines+1]=line end else lines[#lines+1]='Не готов к запуску: '..tostring(why)end
 end
 v.intent={kind='binding_variant',token='variant:'..tostring(v),title='Для какого транспорта отыграть?',lines=lines}
 return v.intent
end
return M
