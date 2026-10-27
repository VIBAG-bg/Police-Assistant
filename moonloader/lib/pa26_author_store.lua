-- Small independent transaction for explicit author-preset imports. Never touches notes.
local model=require 'pa26_author_presets';local config=require 'pa26_config';local jsonStore=require 'pa26_library'
local M={};local keys={binds=true,settings=true,config=true}
local function target(base,k)return base..(k=='config'and'.ini'or'_'..k..'.json')end
local function copyPath(base,id,k,which)return base..'_preset_backup_'..id..'_'..k..'.'..which end
local function call(fs,key,... )local ok,a,b=pcall(fs[key],...);if ok then return a,b end;return nil,tostring(a)end
local function valid(j)
 if type(j)~='table'or j.format~='pa-author-transaction'or j.schema~=1 or not({prepared=true,committed=true})[j.phase]or type(j.id)~='string'or #j.id~=32 or not j.id:match('^[a-f0-9]+$')or type(j.files)~='table'then return nil end
 local n=0;for k,v in pairs(j.files)do
  if not keys[k]or type(v)~='table'or type(v.had)~='boolean'or type(v.after)~='string'or #v.after~=64 or not v.after:match('^[a-f0-9]+$')or(v.had and(type(v.before)~='string'or #v.before~=64 or not v.before:match('^[a-f0-9]+$')))then return nil end;n=n+1
 end
 if n<1 or n>2 or(j.files.binds and n~=1)then return nil end;return j
end
local function decide(base,json,fs)
 for _,suffix in ipairs({'','.rollback','.bak'})do
  local text=call(fs,'read',base..'_preset_pending.json'..suffix)
  if text then local ok,j=pcall(json.decode,text);if ok and valid(j)then return j end end
 end
end
local function pending(base,fs)
 for _,suffix in ipairs({'','.rollback','.bak'})do if call(fs,'exists',base..'_preset_pending.json'..suffix)then return true end end
 return false
end
local function replace(base,j,k,text,fs)
 local path=target(base,k);local tmp=copyPath(base,j.id,k,'apply');local displaced=copyPath(base,j.id,k,'displaced')
 if text==nil then return not call(fs,'exists',path)or call(fs,'remove',path)end
 if call(fs,'read',path)==text then return true end
 if not call(fs,'write',tmp,text)or call(fs,'read',tmp)~=text then return nil end
 if call(fs,'exists',displaced)and not call(fs,'remove',displaced)then return nil end
 if call(fs,'exists',path)and not call(fs,'rename',path,displaced)then return nil end
 return call(fs,'rename',tmp,path)and call(fs,'read',path)==text
end
local function recoverLocked(base,json,fs,hash)
 if not pending(base,fs)then return true end
 local j=decide(base,json,fs);if not j then return nil,'Повреждён журнал применения набора. Файлы сохранены; требуется восстановление копий.'end
 local originals={}
 for k,row in pairs(j.files)do
  local needed=j.phase=='committed'or row.had
  local text=needed and call(fs,'read',copyPath(base,j.id,k,j.phase=='committed'and'after'or'before'))or nil
  if needed and(not text or hash(text)~=(j.phase=='committed'and row.after or row.before))then return nil,'Повреждена копия набора: '..k end
  local actual=call(fs,'read',target(base,k));local h=actual and hash(actual)
  if h and h~=row.after and h~=row.before then return nil,'Файл '..k..' изменён извне. Копии сохранены; автоматическое восстановление остановлено.'end
  originals[k]=text or false
 end
 for k in pairs(j.files)do if not replace(base,j,k,originals[k]or nil,fs)then return nil,'Восстановление набора не завершено. Повтор сохранён.'end end
 for _,suffix in ipairs({'.bak','.rollback',''})do local p=base..'_preset_pending.json'..suffix;if call(fs,'exists',p)and not call(fs,'remove',p)then return nil,'Не удалось завершить журнал набора.'end end
 return true
end
function M.recover(base,json,fs,hash,lock)
 fs=fs or jsonStore.fs
 if not pending(base,fs)then return true end
 local release=lock(base..'_preset.lock');if not release then return nil,'Применение набора уже выполняется. Повторите запуск позже.'end
 local ok,a,b=pcall(recoverLocked,base,json,fs,hash);release();if not ok then return nil,tostring(a)end;return a,b
end
function M.snapshot(base,kind,fs)
 local out={};for _,k in ipairs(kind=='binds'and{'binds'}or{'settings','config'})do local path=target(base,k);local text=call(fs,'read',path);if call(fs,'exists',path)and type(text)~='string'then error('Не удалось прочитать '..k)end;out[k]=text or false end;return out
end
function M.apply(base,prepared,before,json,fs,hash,lock,id)
 local release=lock(base..'_preset.lock');if not release then return nil,'Другой процесс уже применяет набор.'end
 local function work()
  if pending(base,fs)then return nil,'Сначала завершите восстановление предыдущего набора.'end
  if not model.equal(before,M.snapshot(base,prepared.kind,fs))then return nil,'Файлы изменились после предпросмотра. Загрузите набор заново.'end
  local rows={};local parts=require('pa26_user_files').partition(prepared.library)
  if prepared.kind=='binds'then rows.binds=json.encode(parts.binds)
  else rows.settings=json.encode(parts.settings);local text,err=config.serialize(prepared.config);if not text then return nil,err end;rows.config=text end
  local j={format='pa-author-transaction',schema=1,phase='prepared',id=id,files={}}
  if not valid({format=j.format,schema=1,phase='prepared',id=id,files={binds={had=false,after=string.rep('a',64)}}})then return nil,'Неверный номер копии.'end
  for k,text in pairs(rows)do
   local old=before[k];local after=copyPath(base,id,k,'after');local prior=copyPath(base,id,k,'before')
   if call(fs,'exists',after)or call(fs,'exists',prior)then return nil,'Такая копия уже существует.'end
   if not call(fs,'write',after,text)or call(fs,'read',after)~=text then return nil,'Не удалось подготовить новый файл.'end
   if old and(not call(fs,'write',prior,old)or call(fs,'read',prior)~=old)then return nil,'Не удалось создать резервную копию.'end
   j.files[k]={had=old~=false,before=old and hash(old)or false,after=hash(text)}
  end
  if not model.equal(before,M.snapshot(base,prepared.kind,fs))then return nil,'Файлы изменились во время подготовки. Ничего не заменено.'end
  local journal=base..'_preset_pending.json';local ok,err=jsonStore.save(journal,j,json,valid,fs);if not ok then return nil,err end
  for k,text in pairs(rows)do
   if not replace(base,j,k,text,fs)then local restored,note=recoverLocked(base,json,fs,hash);return nil,restored and'Запись не удалась; прежние значения восстановлены.'or note end
  end
  j.phase='committed';ok,err=jsonStore.save(journal,j,json,valid,fs)
  if not ok then local restored,note=recoverLocked(base,json,fs,hash);return nil,restored and err or note end
  ok,err=recoverLocked(base,json,fs,hash);if not ok then return nil,err end
  return true,base..'_preset_backup_'..id
 end
 local ok,a,b=pcall(work);release();if not ok then return nil,tostring(a)end;return a,b
end
return M
