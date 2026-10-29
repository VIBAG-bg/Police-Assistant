local core=require 'pa26_core'
local M={keys={main=true,quick=true,tips=true,assist=true,wanted=true,fine=true,mark=true,ground=true}}
function M.defaults()return {revision=1,remember=true,initial_percent=70,wanted_separate=true,fine_separate=true,mark_separate=true,windows={}}end
function M.validate(raw)
    if raw==nil then return M.defaults()end
    if type(raw)~='table'or raw.revision~=1 or type(raw.remember)~='boolean'or type(raw.wanted_separate)~='boolean'or
        not core.finite(raw.initial_percent)or raw.initial_percent~=math.floor(raw.initial_percent)or raw.initial_percent<50 or raw.initial_percent>95 or type(raw.windows)~='table'then
        return nil,'Проверьте настройки окон: начальный размер 50–95%, сохранение и отдельное окно розыска.'
    end
    local out=M.defaults()
    for _,key in ipairs({'fine_separate','mark_separate'})do
        if raw[key]~=nil then if type(raw[key])~='boolean'then return nil,'Неверный переключатель отдельного окна.'end;out[key]=raw[key]end
    end
    out.remember=raw.remember;out.wanted_separate=raw.wanted_separate;out.initial_percent=raw.initial_percent
    for key,row in pairs(raw.windows)do
        if not M.keys[key]or type(row)~='table'then return nil,'Неизвестное сохранённое окно PA.'end
        local clean={}
        for _,field in ipairs({'width','height','x','y','displayW','displayH'})do
            local n=row[field]
            if not core.finite(n)or n<0 or n>32768 then return nil,'Повреждённый размер или положение окна PA.'end
            clean[field]=n
        end
        if clean.width<1 or clean.height<1 or clean.displayW<220 or clean.displayH<220 then return nil,'Неверное разрешение сохранённого окна PA.'end
        out.windows[key]=clean
    end
    return out
end
function M.same(a,b)
    if not a or not b then return a==b end
    for _,k in ipairs({'width','height','x','y','displayW','displayH'})do if math.abs(a[k]-b[k])>.75 then return false end end
    return true
end
return M
