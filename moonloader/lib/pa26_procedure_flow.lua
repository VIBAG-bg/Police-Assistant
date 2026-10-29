-- A bounded mailbox shared by native chat, CEF and GUI intents.
-- The adapter's observe/resolve/open callbacks are invoked only by tick in main().
local core=require 'pa26_core';local parser=require 'pa26_procedure_input';local model=require 'pa26_bindings'
local M={};local Flow={};Flow.__index=Flow
function M.new(env)return setmetatable({env=env,serial=0},Flow)end
function Flow:capture(head,args,ground)
 args=tostring(args or'')
 if not core.validUtf8(args)then local ok,value=pcall(self.env.codec.decode,args);if ok then args=value end end
 if not core.validUtf8(args)or #args>1024 or args:find('%c')then return nil,'Команда должна быть одной строкой допустимого размера.'end
 local cfg=self.env.settings();local kind=head=='ticket'and'fine'or head=='setmark'and'mark'
 if not kind then return nil,'Неизвестная процедура.'end
 local p,why
 if not cfg[kind..'_intercept']or not cfg.enabled or not cfg[kind..'_enabled']then
  p={head=head,kind=kind,raw='/'..head..(args~=''and(' '..args)or''),passThrough=true}
 else p,why=parser.parse(head,args)end
 if not p then return nil,why end
 local s=self.env.context();self.serial=self.serial+1
 p.serial=self.serial;p.at=self.env.now();p.session=s.session;p.localId=s.localId;p.local_nick=s.local_nick;p.demo=s.demo;p.epoch=self.env.epoch()
 if not p.id and not p.passThrough then local t=self.env.suggest(kind);p.id=t and t.id end
 if p.id then p.generation=self.env.generation(p.id)end
 p.ground=model.copy(ground);self.pending=p;return true
end
function Flow:tick(s,now)
 local p=self.pending;if not p then return end
 local age=core.elapsed(now,p.at)
 if not age or age>5000 or s.session~=p.session or s.localId~=p.localId or s.local_nick~=p.local_nick or s.demo~=p.demo or self.env.epoch()~=p.epoch or not s.alive then
  self.pending=nil;self.env.notice('Команда устарела после изменения сцены. Повторите её для нужного человека.');return
 end
 if not s.focused or s.paused then self.pending=nil;return end
 if s.blocked or s.typing or s.modal or s.busy then return end
 self.pending=nil
 if p.passThrough then self.env.pass(p.raw);return end
 local target,why
 if p.id then
  if self.env.generation(p.id)~=p.generation then self.env.notice('ID сменил владельца. Повторите команду.');return end
  target,why=self.env.resolve(p.kind,p.id,p.generation)
  if not target then self.env.notice(why);return end
 end
 self.env.open(p.kind,p,target)
end
return M
