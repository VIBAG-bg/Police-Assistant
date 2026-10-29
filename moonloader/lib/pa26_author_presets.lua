local model=require 'pa26_bindings';local users=require 'pa26_user_files';local core=require 'pa26_core'
local M={MAX_BYTES=1048576,protected={profile=true,partners=true,next_partner_id=true,wanted_reminders=true,filters=true}}
function M.equal(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not M.equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function M.validate(kind,p)
 if type(p)~='table'then return nil,'Неверный набор.'end
 if kind=='binds'then return users.validate('binds',p)end
 if kind~='settings'or p.format~='police-assistant.author-settings'or p.schema~=1 then return nil,'Неверный тип набора.'end
 for k in pairs(p)do if not({format=true,schema=true,settings=true,config=true})[k]then return nil,'Неизвестное поле набора.'end end
 local good,why=core.validateSettings(p.config);if not good then return nil,why end
 local s,err=users.validate('settings',p.settings,p.config);if not s then return nil,err end
 return {format=p.format,schema=1,settings=s,config=model.copy(p.config)}
end
function M.decode(kind,text,json)
 if type(text)~='string'or #text>M.MAX_BYTES then return nil,'Набор слишком велик.'end
 local p,err=require('pa26_library').decode(text,json,function(v)return v end);if not p then return nil,err end
 return M.validate(kind,p)
end
function M.prepare(kind,payload,lib,cfg)
 local nextLib=model.copy(lib);local nextCfg=model.copy(cfg)
 if kind=='binds'then
  local p,why=users.validate('binds',payload,cfg);if not p then return nil,why end
  nextLib.bindings=p.bindings;nextLib.next_id=p.next_id;nextLib.wheel=p.wheel;nextLib.settings.wheel_car_classic=model.copy(p.wheel_car_classic or p.wheel)
 elseif kind=='settings'then
  local p,why=M.validate(kind,payload)
  if not p then return nil,why end
  for k,v in pairs(p.settings.data)do if not M.protected[k]then nextLib[k]=model.copy(v)end end
  nextLib.profile=model.copy(lib.profile);nextLib.partners=model.copy(lib.partners);nextLib.next_partner_id=lib.next_partner_id
  nextLib.assist.history=model.copy(lib.assist.history);nextLib.settings.updates=model.copy(lib.settings.updates);nextLib.settings.wheel_car_classic=model.copy(lib.settings.wheel_car_classic)
  nextCfg=model.copy(p.config);nextCfg.main.demo_mode=cfg.main.demo_mode
 else return nil,'Неверный вид набора.'end
 local clean,why=model.validate(nextLib,nextCfg);if not clean then return nil,why end
 for _,b in ipairs(clean.bindings)do local parsed,err=require('pa26_binder').parse(b.script);if not parsed then return nil,err end end
 return {library=clean,config=nextCfg,kind=kind}
end
return M
