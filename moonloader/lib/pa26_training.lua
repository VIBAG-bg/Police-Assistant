-- Local study only. Sources and self-assessment are authored by the user.
local prefs=require 'pa26_assist_settings'
local shared=require 'pa26_patrol_settings'
local M={};local Study={};Study.__index=Study
function M.new()return setmetatable({},Study)end
function Study:cancel()self.session=nil end
function Study:start(cfg)
    if not cfg.enabled then return nil,'Включите обучение.'end
    local rows={};local signatures={}
    for _,c in ipairs(cfg.cards)do
        if c.enabled and(cfg.department=='all'or c.department=='all'or c.department==cfg.department)then
            rows[#rows+1]=shared.copy(c);signatures[c.id]=prefs.revision(c)
        end
    end
    if #rows==0 then return nil,'Добавьте и включите карточки с вопросом, ответом и источником для выбранного ведомства.'end
    -- Weakly known cards come first; the order is stable across launches.
    table.sort(rows,function(a,b)
        local pa,pb=cfg.progress[tostring(a.id)],cfg.progress[tostring(b.id)]
        local sa=pa and pa.known-pa.repeat_count or -1;local sb=pb and pb.known-pb.repeat_count or -1
        if sa==sb then return a.id<b.id end;return sa<sb
    end)
    while #rows>cfg.limit do table.remove(rows)end
    self.session={rows=rows,signatures=signatures,index=1,revealed=false,known=0,repeat_count=0,department=cfg.department,limit=cfg.limit}
    return true
end
function Study:current(cfg)
    local s=self.session;if not s then return end
    if not cfg.enabled or cfg.department~=s.department or cfg.limit~=s.limit then self:cancel();return nil,'Настройки обучения изменились. Начните заново.'end
    local available={};for _,c in ipairs(cfg.cards)do available[c.id]=c end
    for _,c in ipairs(s.rows)do
        local actual=available[c.id]
        if not actual or not actual.enabled or prefs.revision(actual)~=s.signatures[c.id]then self:cancel();return nil,'Карточки изменились. Начните обучение заново.'end
    end
    return s.rows[s.index]
end
function Study:reveal(cfg)
    local c,err=self:current(cfg);if not c then return nil,err or 'Обучение завершено.'end
    self.session.revealed=true;return true
end
function Study:grade(cfg,known)
    local c,err=self:current(cfg);if not c then return nil,err or 'Нет текущего вопроса.'end
    if type(known)~='boolean'or not self.session.revealed then return nil,'Сначала откройте ответ и сравните со своим.'end
    local copy=shared.copy(cfg);local k=tostring(c.id);local old=copy.progress[k]
    local p=old and old.revision==prefs.revision(c)and old or {known=0,repeat_count=0,revision=prefs.revision(c)}
    local field=known and 'known'or 'repeat_count';p[field]=math.min(1000000,p[field]+1);copy.progress[k]=p
    return copy,{id=c.id,index=self.session.index,known=known}
end
function Study:commit(token)
    local s=self.session
    if not s or not token or token.index~=s.index or not s.revealed or not s.rows[s.index]or token.id~=s.rows[s.index].id then return nil end
    local field=token.known and 'known'or 'repeat_count';s[field]=s[field]+1;s.index=s.index+1;s.revealed=false;return true
end
return M
