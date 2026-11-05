-- Voluntary author update: recognize exact stock RP; never overwrite a fork.
-- No files are touched here. The existing preview/backup/transaction owns saving.
local model=require 'pa26_bindings';local M={}
local function equal(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function ref(b)return b.author_ref or string.format('A%02d',b.id)end
function M.claimAssignments(binding,commands,keys,windowKeys)
 local conflicts={}
 for _,field in ipairs({'command','command_alias'})do
  local command=binding[field]
  if command~=''then
   if commands[command]then conflicts[#conflicts+1]='/'..command;binding[field]=''
   else commands[command]=true end
  end
 end
 local shortcut=binding.shortcut
 if shortcut.key~=0 then
  local key=model.shortcutName(shortcut)
  if keys[key]or windowKeys and windowKeys[shortcut.key]then
   conflicts[#conflicts+1]=key
   binding.shortcut={key=0,ctrl=false,alt=false,shift=false}
  else keys[key]=true end
 end
 return conflicts
end

function M.freeId(nextId,used,reserved)
 while used[nextId]or reserved[nextId]do nextId=nextId+1 end
 if nextId>=999999999 then return nil,'Не удалось выделить ID без конфликта.'end
 return nextId
end

function M.prepare(payload,lib)
 local out=model.copy(lib);local previous=require('pa26_author_rp').previous
 local changes={updated={},added={},preserved=#lib.bindings};local used,commands,keys,reserved={},{},{},{}
 for _,b in ipairs(lib.bindings)do
  used[b.id]=true;for _,c in ipairs(model.bindingCommands(b))do commands[c]=true end
  if b.shortcut.key~=0 then keys[model.shortcutName(b.shortcut)]=true end
 end
 for _,b in ipairs(payload.bindings)do reserved[b.id]=true end
 for _,incoming in ipairs(payload.bindings)do
  local reference=ref(incoming);local stock=previous[reference];local found
  for _,b in ipairs(out.bindings)do
   local candidate=b.author_ref==reference or not b.author_ref and stock and b.id==stock.id
   if candidate and((b.script==incoming.script and equal(b.rp_context,incoming.rp_context))or
       stock and b.script==stock.script and b.rp_context==nil)then found=b;break end
  end
  if found then
   local before=model.copy(found)
   found.script=incoming.script;found.rp_context=model.copy(incoming.rp_context);found.author_ref=reference
   if stock and found.name==stock.name then found.name=incoming.name end
   -- An individually moved slot keeps its location. Only untouched stock
   -- assignments follow the new author's placement.
   for _,k in ipairs({'wheel_visible','wheel_car_visible','wheel_group','wheel_car_group','wheel_extra_groups','wheel_car_extra_groups','category'})do
    local a=found[k];local old=stock and stock[k]
    if old==nil and(k=='wheel_extra_groups'or k=='wheel_car_extra_groups')then old={}end
    if stock and equal(a,old)then found[k]=model.copy(incoming[k])end
   end
   if not equal(before,found)then changes.updated[#changes.updated+1]={name=found.name,before=before.script,after=found.script,id=found.id}end
  else
   if #out.bindings>=model.MAX_BINDS then return nil,'Авторский набор не помещается без удаления ваших биндов (лимит '..model.MAX_BINDS..'). Ваши данные сохранены. Освободите место или импортируйте нужные сценарии отдельно.'end
   local b=model.copy(incoming)
   if used[b.id]then
    local id,err=M.freeId(out.next_id,used,reserved);if not id then return nil,err end;b.id=id
   end
   used[b.id]=true;out.next_id=math.max(out.next_id,b.id+1);b.author_ref=reference
   M.claimAssignments(b,commands,keys)
   b.skip_confirmation=false -- A newly added copy never skips its first preview.
   out.bindings[#out.bindings+1]=b;changes.added[#changes.added+1]={name=b.name,id=b.id,after=b.script}
  end
 end
 if #lib.bindings==0 then out.wheel=model.copy(payload.wheel);out.settings.wheel_car_classic=model.copy(payload.wheel_car_classic or payload.wheel)end
 return out,changes
end
function M.rebaseOrder(order,lib)
 local authored={}
 for _,b in ipairs(lib.bindings)do if b.author_ref then
  local id=tonumber(b.author_ref:sub(2));local expected=require('pa26_author_rp').bindings[tostring(id)]
  if expected and b.script==expected.script then authored[id]=b.id end
 end end
 local out=model.copy(order)
 for group,rows in pairs(out)do if group~='root'then
  local mapped={}
  for _,key in ipairs(rows)do local id=tonumber(key:match('^b:(%d+)$'))
   if not id then mapped[#mapped+1]=key elseif authored[id]then mapped[#mapped+1]='b:'..authored[id]end
  end
  out[group]=mapped
 end end
 return out
end
return M
