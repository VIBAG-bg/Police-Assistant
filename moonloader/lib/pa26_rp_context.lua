-- Optional binding context. Reuses the Copilot vehicle observation and classifier.
-- No game reads, callbacks, timers or sends. Unmarked personal bindings are unchanged.
local core=require 'pa26_core'
local M={}
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
function M.validate(raw)
 if raw==nil then return nil end
 if type(raw)~='table'then return nil,'Проверьте контекст RP.'end
 for k in pairs(raw)do if not({vehicle=true,bike_script=true,identity=true,contact_phase=true,checkpoints=true,approval_timeout_ms=true})[k]then return nil,'Неизвестное поле контекста RP.'end end
 local r={}
 if raw.approval_timeout_ms~=nil then
  if not core.finite(raw.approval_timeout_ms)or raw.approval_timeout_ms%1~=0 or raw.approval_timeout_ms<1000 or raw.approval_timeout_ms>90000 then return nil,'Ожидание решения: от 1 до 90 секунд.'end
  r.approval_timeout_ms=raw.approval_timeout_ms
 end
 if raw.vehicle~=nil then
  if raw.vehicle~='traffic'and raw.vehicle~='inspection'then return nil,'Контекст транспорта: остановка или осмотр.'end
  r.vehicle=raw.vehicle
 end
 if raw.bike_script~=nil then
  if type(raw.bike_script)~='string'or #raw.bike_script>16384 or not core.validUtf8(raw.bike_script)or raw.bike_script:find('[%z\1-\8\11\12\14-\31]')then return nil,'Проверьте мотовариант RP.'end
  r.bike_script=raw.bike_script
 end
 for _,k in ipairs({'identity','contact_phase'})do if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Проверьте условие RP: '..k end;r[k]=raw[k]end end
 if raw.checkpoints~=nil then
  if type(raw.checkpoints)~='table'or #raw.checkpoints>16 then return nil,'Не больше 16 подтверждений RP.'end
  local n,seen=0,{};r.checkpoints={}
  for i,c in pairs(raw.checkpoints)do
   if type(i)~='number'or i%1~=0 or i<1 or i>#raw.checkpoints or type(c)~='table'or not core.finite(c.before)or c.before%1~=0 or c.before<1 or c.before>64 or seen[c.before]or
     type(c.prompt)~='string'or #c.prompt>2048 or not c.prompt:match('%S')or not core.validUtf8(c.prompt)or c.prompt:find('%c')then return nil,'Подтверждение: номер реплики 1–64 и понятный вопрос.'end
   n=n+1;seen[c.before]=true;r.checkpoints[i]={before=c.before,prompt=c.prompt}
  end
  if n~=#raw.checkpoints then return nil,'Повреждён список подтверждений RP.'end
 end
 return r
end
function M.class(source)
 local c=source and source.car
 if not c or c.stale then return 'unknown'end
 local kind=require('pa26_vehicle_types').class(c.model_id)
 if kind=='bike'then return 'bike'end
 if kind=='car'or kind=='van'or kind=='truck'or kind=='bus'then return 'car'end
 return 'unknown'
end
function M.resolve(binding,source,choice)
 local rc=binding.rp_context
 if not rc then return binding end
 if rc.contact_phase and source and source.phase~='10-55'and source.phase~='10-66'then return nil,'Разъяснение остановки доступно во время общения в текущем 10-55 / 10-66.'end
 if not rc.vehicle then return binding end
 local variant=M.class(source)
 if variant=='unknown'then
  if choice~='car'and choice~='bike'then return nil,nil,{car=copy(source and source.car),life=source and source.life}end
  variant=choice
 end
 local result=copy(binding)
 if variant=='bike'then
  if rc.vehicle=='inspection'then
   local text=source and source.inspect_bike
   if type(text)~='string'or not text:match('%S')then return nil,'Настройте внешний осмотр мотоцикла в Copilot.'end
   result.script='/do '..text
  elseif not rc.bike_script or not rc.bike_script:match('%S')then return nil,'Заполните мотовариант в редакторе бинда.'
  else result.script=rc.bike_script end
 end
 return result,nil,nil,variant
end
function M.checks(binding,ctx)
 local r,rc={},binding.rp_context
 if not rc then return r end
 for _,c in ipairs(rc.checkpoints or{})do r[c.before]={prompt=c.prompt}end
 if rc.identity and not ctx.icIdentity then
  local name=ctx.values.select_name or 'неизвестно'
  r[1]=r[1]or{prompt=''}
  r[1].prompt='Вы установили по RP личность «'..name..'»? Ник и SA:MP ID сами по себе этого не подтверждают. '..r[1].prompt
 end
 return r
end
return M
