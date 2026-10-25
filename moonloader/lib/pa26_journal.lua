local core=require 'pa26_core'
local model=require 'pa26_bindings'
local M={MAX_EVENTS=500}; local Journal={}; Journal.__index=Journal
function M.defaults() return {schema=1,next_id=1,events={},counters={},days={}} end
function M.validate(raw)
    if type(raw)~='table' or raw.schema~=1 or not core.finite(raw.next_id) or raw.next_id<1 or raw.next_id>999999999 or raw.next_id~=math.floor(raw.next_id) or not model.array(raw.events,500) then return nil,'Журнал повреждён.' end
    local out=M.defaults(); out.next_id=raw.next_id; local ids={}
    for _,e in ipairs(raw.events) do
        if type(e)~='table' or not core.finite(e.id) or e.id<1 or e.id~=math.floor(e.id) or e.id>=raw.next_id or ids[e.id] or type(e.demo)~='boolean' or type(e.confirmed)~='boolean' or not core.finite(e.sent) or e.sent<0 or e.sent>64 or e.sent~=math.floor(e.sent) then return nil,'Неверная запись журнала.' end
        if e.status~='completed' and e.status~='cancelled' then return nil,'Неверный статус.' end
        local copy={id=e.id,demo=e.demo,confirmed=e.confirmed,sent=e.sent,status=e.status}
        for _,key in ipairs({'name','date','day','target','reason','stat'}) do local s=model.clean(e[key],key=='reason' and 512 or 160); if not s then return nil,'Повреждён текст журнала.' end; copy[key]=s end
        if e.knowledge~=nil then copy.knowledge=model.knowledgeOrigin(e.knowledge);if not copy.knowledge then return nil,'Повреждено основание события.'end end
        local valid=false; for _,s in ipairs(model.stats) do if s[1]==copy.stat then valid=true end end; if not valid then return nil,'Неверный счётчик.' end
        ids[e.id]=true; out.events[#out.events+1]=copy
    end
    local function counters(value)
        if type(value)~='table' then return nil end
        local result={}; for key,n in pairs(value) do
            local valid=false; for _,spec in ipairs(model.stats) do if spec[1]==key and key~='none' then valid=true end end
            if not valid or not core.finite(n) or n<0 or n>999999999 or n~=math.floor(n) then return nil end; result[key]=n
        end; return result
    end
    out.counters=counters(raw.counters); if not out.counters or type(raw.days)~='table' then return nil,'Повреждены счётчики.' end
    local count=0
    for day,value in pairs(raw.days) do count=count+1; if count>366 or type(day)~='string' or not day:match('^%d%d%d%d%-%d%d%-%d%d$') then return nil,'Неверные даты статистики.' end
        out.days[day]=counters(value); if not out.days[day] then return nil,'Повреждён дневной счётчик.' end end
    return out
end
function M.new(data,clock)
    return setmetatable({data=data or M.defaults(),clock=clock or os.date,dirty=false,session={runs=0,demo=0,sent=0,cancelled=0},results={}},Journal)
end
function Journal:record(q,status,reason)
    local data=self.data; local day=self.clock('%Y-%m-%d')
    local target=q.plan.target; local e={id=data.next_id,name=q.plan.binding.name,date=self.clock('%d.%m.%Y %H:%M:%S'),day=day,
        target=target and (target.name..' ['..target.id..']') or 'Без цели',demo=q.demo,confirmed=false,sent=q.sent,status=status,
        reason=reason or '',stat=q.plan.binding.stat}
    if q.plan.binding.knowledge then e.knowledge=model.copy(q.plan.binding.knowledge)end
    data.next_id=data.next_id+1; data.events[#data.events+1]=e
    if #data.events>M.MAX_EVENTS then table.remove(data.events,1) end
    self.session.runs=self.session.runs+1; self.session.sent=self.session.sent+q.sent
    if q.demo then self.session.demo=self.session.demo+1 end
    if status=='cancelled' then self.session.cancelled=self.session.cancelled+1 end
    self.dirty=true; return e
end
function Journal:confirm(id)
    for _,e in ipairs(self.data.events) do if e.id==id then
        if e.demo or e.confirmed or e.sent==0 or e.stat=='none' then return nil,'Эта запись не допускает подтверждения результата.' end
        local counter=self.data.counters; counter[e.stat]=(counter[e.stat] or 0)+1
        local day=self.data.days[e.day] or {}; self.data.days[e.day]=day; day[e.stat]=(day[e.stat] or 0)+1
        local days={}; for key in pairs(self.data.days) do days[#days+1]=key end; table.sort(days)
        while #days>366 do self.data.days[table.remove(days,1)]=nil end
        e.confirmed=true; self.results[e.stat]=(self.results[e.stat] or 0)+1; self.dirty=true; return true
    end end
    return nil,'Запись не найдена.'
end
function Journal:clearLog() self.data.events={}; self.dirty=true end
function Journal:resetStats() self.data.counters={}; self.data.days={}; self.results={}; self.dirty=true end
return M
