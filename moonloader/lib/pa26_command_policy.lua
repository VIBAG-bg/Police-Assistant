-- Final, plan-wide policy. Runs on preparation/send, never on chat editing.
local core=require 'pa26_core'
local M={};local Policy={};Policy.__index=Policy
local function copy(v)
 if type(v)~='table'then return v end
 local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
end
function M.command(text)
 if type(text)~='string'then return end
 local head,args=text:match('^%s*/([A-Za-z][A-Za-z0-9_]*)%s*(.-)%s*$')
 if head and head:lower()=='setmark'then
  local id=args:match('^(%d+)$');id=id and tonumber(id)
  if not core.validId(id)then return false,'Пеленгация: используйте /setmark ID, без других параметров.'end
  return id
 end
end
function M.new(env)return setmetatable({env=env or{}},Policy)end
function Policy:template()
 local cfg=self.env.settings and self.env.settings()
 -- Mandatory means neither the manual-handler toggle nor an imported bind may bypass it.
 return cfg and cfg.rules and cfg.rules.setmark and cfg.rules.setmark.rp or
  require('pa26_manual_actions').defaults().rules.setmark.rp
end
function Policy:render(id,ctx)
 local text=self:template();local values=copy(ctx.values or{})
 values.id=tostring(id);values.select_id=tostring(id);values.param1=tostring(id);values.params=tostring(id)
 local account=self.env.capture and self.env.capture(id,ctx.demo)
 if not account or account.id~=id or type(account.name)~='string'or account.name==''then
  return nil,'Пеленгация: ID не подключён или его личность не подтверждена.'
 end
 local name=account.name:gsub('_',' ');values.select_nick=account.name;values.select_name=name;values.suspect_name=name
 values.select_firstname,values.select_lastname=name:match('^(%S+)%s+(.*)$')
 values.select_firstname=values.select_firstname or name;values.select_lastname=values.select_lastname or''
 local failed
 text=core.expandGender(text,ctx.gender):gsub('{([^{}]+)}',function(k)
  local v=values[k];if v==nil then failed='Не заполнена переменная {'..k..'} обязательной RP.';return''end
  return tostring(v)
 end)
 if failed then return nil,failed end
 if #text>8192 or text:find('[{}]')then return nil,'Проверьте обязательную RP пеленгации.'end
 local prepared={steps={},lines={},wire={}}
 for line in(text..'\n'):gmatch('(.-)\n')do if line:find('%S')then
  if not(line:match('^/me%s+')or line:match('^/do%s+')or line:match('^/try%s+')or line:match('^/todo%s+[^*]+%*[^*]+$'))then
   return nil,'Обязательная RP: только /me, /do, /try или /todo.'
  end
  local ready,why=require('pa26_rp_text').line(line,self.env.codec,self.env.rpSettings and self.env.rpSettings(),values.my_nick)
  if not ready then return nil,why end
  local ok;ok,why=require('pa26_rp_text').append(prepared,ready);if not ok then return nil,why end
 end end
 if #prepared.steps==0 then return nil,'Обязательная RP пеленгации пуста; команда не отправлена.'end
 return prepared,account
end
-- A complete configured preparation must precede the command in this same
-- plan. A lone arbitrary /me, stale metadata or another target is insufficient.
function Policy:prepare(plan,provided)
 if plan.commandPolicy and not self:valid(plan)then return nil,'Предпросмотр пеленгации изменился; подготовьте действие заново.'end
 local relevant=false
 for _,s in ipairs(plan.steps or{})do local id,err=M.command(s.text)
  if id==false then return nil,err end
  if id~=nil then relevant=true end
 end
 if not relevant then return plan end
 local ctx=provided or(self.env.context and self.env.context(plan))
 if not ctx then return nil,'Контекст пеленгации недоступен.'end
 local out=copy(plan);out.steps={};out.lines={};out.wire={};out.commandPolicy={accounts={},template=self:template(),gender=ctx.gender,
  revision=self.env.revision and self.env.revision(),baseWire=copy(plan.commandPolicy and plan.commandPolicy.baseWire or plan.wire)}
 local previous={} -- reset after each server command / consumed preparation
 for _,s in ipairs(plan.steps)do
  local id,err=M.command(s.text)
  if id==false then return nil,err end
  if id~=nil then
   local rp,account=self:render(id,ctx);if not rp then return nil,account end
   if plan.target and plan.target.id~=id then return nil,'RP и /setmark указывают на разных людей.'end
   local suffix=#previous>=#rp.lines
   if suffix then for i=1,#rp.lines do if previous[#previous-#rp.lines+i]~=rp.lines[i]then suffix=false;break end end end
   local needed={}
   -- A bound, identity-checked custom preparation can use its own wording.
   -- Require both an officer action and a terminal/search request statement;
   -- arbitrary RP elsewhere in the script never counts as authorization.
   local custom=false;local subject=plan.target or plan.wantedSubject
   if not suffix and subject and subject.id==id and subject.name==account.name and #previous>=2 then
    local me,statement,request,terminal=false,false,false,false
    for _,line in ipairs(previous)do
     me=me or line:match('^/me%s')~=nil;statement=statement or line:match('^/do%s')~=nil
     request=request or line:find('пеленг',1,true)~=nil or line:find('местоположен',1,true)~=nil or line:find('сектор нахожден',1,true)~=nil
     terminal=terminal or line:find('терминал',1,true)~=nil or line:find('комплекс',1,true)~=nil or line:find('компьютер',1,true)~=nil
    end
    custom=me and statement and request and terminal
   end
   if custom then
    local remaining=#previous
    for i=#out.steps,1,-1 do if out.steps[i].kind=='message'then table.insert(needed,1,i);remaining=remaining-1;if remaining==0 then break end end end
   end
   if suffix then
    local cursor=#rp.lines
    for i=#out.steps,1,-1 do local step=out.steps[i]
     if step.kind=='message'then
      if step.text~=rp.lines[cursor]then return nil,'Подготовка пеленгации изменилась.'end
      table.insert(needed,1,i);cursor=cursor-1;if cursor==0 then break end
     end
    end
   elseif not custom then
    for _,step in ipairs(rp.steps)do out.steps[#out.steps+1]=copy(step);needed[#needed+1]=#out.steps end
   end
   local command=copy(s);command.setmarkPolicy={id=id,required=needed}
   out.steps[#out.steps+1]=command;out.commandPolicy.accounts[id]=account;previous={}
  else
   out.steps[#out.steps+1]=copy(s)
   if s.kind=='message'then
    if s.text and(s.text:match('^/me%s')or s.text:match('^/do%s')or s.text:match('^/try%s')or s.text:match('^/todo%s'))then
     previous[#previous+1]=s.text
    else previous={}end
   elseif s.kind~='wait'and s.kind~='key'and s.kind~='check'then previous={}end
  end
  if #out.steps>64 then return nil,'Обязательная RP превысит лимит 64 шагов. Сократите бинд.'end
 end
 for _,s in ipairs(out.steps)do if s.kind=='message'then
  if type(s.text)~='string'or type(s.wire)~='string'then return nil,'Повреждённый шаг пеленгации.'end
  local wire,why=core.encodeWire(s.text,self.env.codec)
  if not wire or wire~=s.wire then return nil,why or'Текст и отправляемая команда не совпадают.'end
  out.lines[#out.lines+1]=s.text;out.wire[#out.wire+1]=s.wire
 end end
 return out
end
function Policy:valid(plan)
 local p=plan.commandPolicy;if not p then return true end
 if p.template~=self:template()or self.env.revision and p.revision~=self.env.revision()then return false end
 local gender=self.env.gender and self.env.gender()
 if not self.env.gender then local ctx=self.env.context and self.env.context(plan);gender=ctx and ctx.gender end
 if gender~=p.gender then return false end
 for _,a in pairs(p.accounts)do
  if not self.env.valid or not self.env.valid(a,plan.demo)then return false end
 end
 return true
end
function Policy:beforeSend(q,step)
 local id,err=M.command(step.text)
 if id==false then return nil,err end
 if id==nil then return true end
 local rule=step.setmarkPolicy
 if not rule or rule.id~=id or not self:valid(q.plan)then return nil,'Пеленгация отменена: подготовка или личность изменились.'end
 for _,i in ipairs(rule.required)do
  if not q.delivered or q.delivered[i]~=true then return nil,'Обязательная RP пеленгации не завершена.'end
 end
 if #rule.required==0 then return nil,'Нет обязательной RP пеленгации.'end
 return true
end
return M
