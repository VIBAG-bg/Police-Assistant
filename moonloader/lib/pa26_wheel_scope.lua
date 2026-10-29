-- Context projection is read-only. Existing foot paths remain authoritative.
local core=require 'pa26_core'
local M={fields={'mode','profile','names','child_limit','system_groups','order'}}
local groups={citizen=true,documents=true,detention=true,frisk=true,wanted=true,service=true,leadership=true,custom=true}
local function copy(v)if type(v)~='table'then return v end;local out={}for k,x in pairs(v)do out[k]=copy(x)end;return out end
M.copy=copy
M.names={citizen='Мегафон и 10-55',documents='Проверка и бортовой ПК',detention='Погоня и 10-66',frisk='Досмотр и обыск',wanted='Розыск и штрафы',service='Рация и патруль',leadership='Вызовы и руководство',custom='Свои бинды (авто)'}
M.systemGroups={['copilot-stop_order']='citizen',['copilot-tire']='citizen',['copilot-stop']='citizen',['copilot-explain_stop']='citizen',['assist-megaphone']='citizen',
 ['copilot-pursuit']='detention',['copilot-high_risk']='detention',['copilot-risk_order']='detention',['copilot-return_car']='detention',['copilot-lost']='detention',['copilot-finish']='detention',
 ['copilot-fast_wanted']='wanted',['copilot-pursuit_mark']='wanted'}
function M.fresh(settings,slots)
 settings.wheel_car_separate=true;settings.wheel_car_mode='categories';settings.wheel_car_profile='compact'
 settings.wheel_car_child_limit=6;settings.wheel_car_names=copy(M.names);settings.wheel_car_system_groups=copy(M.systemGroups)
 settings.wheel_car_order={};settings.wheel_car_classic=copy(slots)
end
function M.active(lib,state)
 return lib.settings.wheel_car_separate==true and state and state.inVehicle==true and'car'or'foot'
end
function M.key(scope,field)return scope=='car'and('wheel_car_'..field)or('wheel_'..field)end
function M.settings(settings,scope)
 if scope~='car'then return settings end
 local s=copy(settings)
 for _,field in ipairs(M.fields)do s['wheel_'..field]=copy(settings['wheel_car_'..field])end
 return s
end
function M.slots(lib,scope)return scope=='car'and lib.settings.wheel_car_classic or lib.wheel end
function M.project(lib,scope)
 if scope~='car'then return lib end
 local out={}for k,v in pairs(lib)do out[k]=v end
 out.settings=M.settings(lib.settings,scope);out.wheel=M.slots(lib,scope);out.bindings={}
 for i,b in ipairs(lib.bindings)do local v={}for k,x in pairs(b)do v[k]=x end
  v.wheel_visible=b.wheel_car_visible==nil and b.wheel_visible or b.wheel_car_visible
  v.wheel_group=b.wheel_car_group or b.wheel_group or'auto';out.bindings[i]=v
 end
 return out
end
function M.validate(raw,foot,slots,ids,clean,array,systems)
 local out={};local separate=raw.wheel_car_separate
 if separate==nil then separate=false end -- Legacy users keep the shared wheel until opting in.
 if type(separate)~='boolean'then return nil,'Отдельное колесо в машине: включено или выключено.'end
 out.wheel_car_separate=separate
 for _,field in ipairs(M.fields)do local v=raw[M.key('car',field)];out[M.key('car',field)]=copy(v==nil and foot[M.key('foot',field)]or v)end
 if not ({classic=true,categories=true})[out.wheel_car_mode]or not({compact=true,extended=true,full=true})[out.wheel_car_profile]then return nil,'Неверный режим автомобильного колеса.'end
 local limit=out.wheel_car_child_limit
 if not core.finite(limit)or limit%1~=0 or limit<0 or limit>16 then return nil,'Второе кольцо в машине: авто либо 1–16 действий.'end
 if type(out.wheel_car_names)~='table'or type(out.wheel_car_system_groups)~='table'then return nil,'Повреждены секции автомобильного колеса.'end
 for id,name in pairs(out.wheel_car_names)do local v=clean(name,160)
  if not groups[id]or not v or v:find('[\r\n]')then return nil,'Название секции в машине: одна строка до 160 байт.'end
  out.wheel_car_names[id]=v~=''and v or nil
 end
 for id,group in pairs(out.wheel_car_system_groups)do
  if not systems[id]or not(groups[group]or group=='disabled')then return nil,'Неизвестное действие или секция автомобильного колеса.'end
 end
 local order,err=require('pa26_wheel_order').validate(out.wheel_car_order);if not order then return nil,err end;out.wheel_car_order=order
 local classic=raw.wheel_car_classic;if classic==nil then classic=slots end
 if not array(classic,6)or #classic~=6 then return nil,'Автомобильное колесо: ровно шесть прямых мест.'end
 out.wheel_car_classic={}
 for i,id in ipairs(classic)do
  if not core.finite(id)or id%1~=0 or id<0 or(id~=0 and not ids[id])then return nil,'Неизвестный бинд автомобильного колеса.'end
  out.wheel_car_classic[i]=id
 end
 return out
end
return M
