local model=require 'pa26_author_presets';local store=require 'pa26_author_store';local M={};local C={};C.__index=C
function M.new(env)return setmetatable({env=env,status='Наборы загружаются только вашей кнопкой.'},C)end
function C:notice(text,kind)self.env.studio:notify(text,'updates',false,kind)end
function C:start(kind)
 local e=self.env;local s=e.studio
 if self.job or self.applied or s:hasModal()then return false end
 s:flushAutosave(e.callbacks,true)
 if e.fs.exists(e.workspace.base..'_files_pending.json')or e.fs.exists(e.workspace.base..'_files_pending.json.rollback')or e.fs.exists(e.workspace.base..'_files_pending.json.bak')then self:notice('Сначала перезапустите PA для завершения прежнего сохранения.');return false end
 if s.dirty or next(s.autosaves or{})or e.workspace.userFiles.blocked or e.busy()then self:notice('Сначала сохраните правки и завершите текущую отыгровку.');return false end
 local cfg,err=require('pa26_updater').validate(e.workspace.library.settings.updates)
 if not cfg or cfg.repository==''then self:notice(err or'Сначала укажите репозиторий GitHub выше.');return false end
 if not e.io then self:notice('Загрузка набора недоступна. Проверьте Windows PowerShell 5.1 и целостность PA.');return false end
 local ok,j,why=pcall(e.io.start,e.io,kind,cfg.repository,cfg.timeout_seconds)
 if not ok or not j then self:notice(why or tostring(j));return false end
 self.job=j;j.repository=cfg.repository;j.at=e.now();j.timeout=(cfg.timeout_seconds*2+20)*1000
 self.status='Загрузка '..(kind=='binds'and'бинд-листа'or'настроек')..' с GitHub…';return true
end
function C:tick()
 local e=self.env;local s=e.studio
 if self.applied then
  if not self.ackQueued and not s:hasModal()then self.ackQueued=true;self:notice('Набор сохранён. Резервная копия: '..self.backup..'\nНажмите ОК — PA перезапустится и применит новые значения. Игра продолжит работать.','info')
  elseif self.ackQueued and not s:hasModal()then e.reload()end
  return
 end
 if self.offered and not s.authorPresetConfirm then self.offered=false;self.status='Применение отменено. Текущие значения сохранены.'end
 if self.job then
  local cfg=require('pa26_updater').validate(e.workspace.library.settings.updates)
  if not cfg or cfg.repository~=self.job.repository then self.job=nil;self:notice('Источник изменился. Повторите загрузку.');return end
  if (require('pa26_core').elapsed(e.now(),self.job.at)or 0)>self.job.timeout then self.job=nil;self:notice('Истекло ожидание GitHub. Текущие бинды и настройки сохранены.');return end
  local ok,text,err,version=pcall(e.io.poll,e.io,self.job,e.json)
  if not ok or err then self.job=nil;self.status='Загрузка остановлена.';self:notice(err or tostring(text));return end
  if text then
   local payload,why=model.decode(self.job.kind,text,e.json)
   if not payload then self.job=nil;self:notice(why);return end
   self.ready={kind=self.job.kind,id=self.job.id,payload=payload,version=version,repository=self.job.repository};self.job=nil;self.status='Набор проверен. Ожидается подтверждение.'
  end
 end
 if self.ready and not s:hasModal()then
  if s.dirty or next(s.autosaves or{})or e.busy()then return end
  local r=self.ready;local source=require('pa26_updater').validate(e.workspace.library.settings.updates)
  if not source or source.repository~=r.repository then self.ready=nil;self:notice('Источник изменился. Повторите загрузку.');return end
  local p,why=model.prepare(r.kind,r.payload,e.workspace.library,e.config())
  if not p then self.ready=nil;self:notice(why);return end
  r.prepared=p;r.library=require('pa26_bindings').copy(e.workspace.library);r.config=require('pa26_bindings').copy(e.config())
  local ok,snapshot=pcall(store.snapshot,e.workspace.base,r.kind,e.fs)
  if not ok then self.ready=nil;self:notice(tostring(snapshot));return end
  local known=e.workspace.userFiles.raw or{}
  for _,key in ipairs(r.kind=='binds'and{'binds'}or{'settings'})do
   if known[key]~=nil and snapshot[key]~=known[key]then self.ready=nil;self:notice('Файл изменён вне PA. Перезапустите PA перед применением набора.');return end
  end
  if snapshot.config then
   local raw=require('pa26_config').parse(snapshot.config);local parsed,notes;if raw then parsed,notes=require('pa26_core').normalizeConfig(raw)end
   local expected=require('pa26_bindings').copy(e.config())
   if parsed then parsed.main.demo_mode=expected.main.demo_mode end
   if not parsed or (notes and #notes>0)or not model.equal(parsed,expected)then self.ready=nil;self:notice('INI изменён вне PA. Перезапустите PA перед применением настроек.');return end
  end
  r.before=snapshot;s.authorPresetConfirm=r;self.offered=true;self.ready=nil
 end
end
function C:accept()
 local e=self.env;local r=e.studio.authorPresetConfirm
 if not r then return nil,'Подтверждение уже закрыто.'end
 local source=require('pa26_updater').validate(e.workspace.library.settings.updates)
 if not source or source.repository~=r.repository then return nil,'Источник изменился. Закройте окно и загрузите набор заново.'end
 if e.fs.exists(e.workspace.base..'_files_pending.json')then return nil,'Сначала завершите прежнее сохранение.'end
 if e.busy()or not model.equal(r.library,e.workspace.library)or not model.equal(r.config,e.config())then return nil,'Данные изменились. Закройте окно и загрузите набор заново.'end
 local ok,note=store.apply(e.workspace.base,r.prepared,r.before,e.json,e.fs,e.hash,e.lock,r.id)
 if not ok then return nil,note end
 self.applied=true;self.backup=note;e.install(r.prepared);e.studio.authorPresetConfirm=nil;return true
end
function M.modal(s)
 local r=s.authorPresetConfirm;if not r then return end
 local binds=r.kind=='binds'
 return {kind='author_preset',token='author-preset:'..r.id,title=binds and'Заменить бинд-лист?'or'Применить авторские настройки?',lines={
  'Проверенный набор из GitHub '..tostring(r.repository or'')..' '..tostring(r.version or'')..'.',
  binds and('Будут заменены все '..#r.library.bindings..' текущих биндов на '..#r.prepared.library.bindings..' авторских, включая команды, клавиши и назначения биндов колесу.')or'Будут заменены настройки интерфейса, колеса, размеров окон, HUD, клавиш и функций PA.',
  binds and'Настройки оформления, профиль, контакты и заметки сохраняются.'or'Ваши бинды, профиль, контакты, заметки, напоминания и источник обновлений сохраняются. Режим ДЕМО не меняется.',
  'Перед заменой сохраняется проверенная резервная копия. После подтверждения PA перезапустится; сама GTA останется открытой.',
  'ДА — сохранить копию и заменить выбранный набор. НЕТ — оставить текущие значения.'}}
end
return M
