local shared=require 'pa26_patrol_settings'
local M={}
M.channels={'','/s','/m','/r','/rn','/f','/fn','/d','/df','/l','/ln','/bkn','/n','/b'}
function M.defaults()
    local channels={};for _,channel in ipairs(M.channels)do channels[channel]=true end
    return {revision=2,enabled=true,speech_enabled=true,channels=channels,display_limit=115,body_limit=90,margin=6,me_extra=1,do_extra=3,
        fallback_nickname=24,max_lines=8,todo_action_limit=60,marker='...',preview_text='достал служебное удостоверение, развернул его перед собеседником и дал возможность ознакомиться с данными, после чего убрал удостоверение обратно.'}
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'or type(raw.enabled)~='boolean'then return nil,'Проверьте переключатель переноса /me и /do.'end
    out.enabled=raw.enabled
    if raw.revision~=nil and raw.revision~=2 then return nil,'Неизвестная версия переноса текста.'end
    if raw.speech_enabled~=nil then
        if type(raw.speech_enabled)~='boolean'then return nil,'Проверьте переключатель переноса речи.'end
        out.speech_enabled=raw.speech_enabled
    end
    if raw.channels~=nil then
        if type(raw.channels)~='table'then return nil,'Проверьте каналы переноса текста.'end
        for key,value in pairs(raw.channels)do
            if out.channels[key]==nil or type(value)~='boolean'then return nil,'Неизвестный канал переноса текста.'end
            out.channels[key]=value
        end
    end
    for _,r in ipairs({{'display_limit',64,255},{'body_limit',24,120},{'margin',0,32},{'me_extra',0,32},{'do_extra',0,32},{'fallback_nickname',1,64},{'max_lines',1,16}})do
        if not shared.integer(raw[r[1]],r[2],r[3])then return nil,'Неверный параметр переноса: '..r[1]end;out[r[1]]=raw[r[1]]
    end
    if raw.todo_action_limit~=nil then
        if not shared.integer(raw.todo_action_limit,1,60)then return nil,'Действие /todo: максимум от 1 до 60 символов.'end
        out.todo_action_limit=raw.todo_action_limit
    end
    -- The user changed the stock 99-character threshold to 90. Other custom
    -- thresholds remain intact; revision 2 permits an explicit 99 as well.
    if raw.revision==nil and raw.body_limit==99 then out.body_limit=90 end
    out.marker=shared.text(raw.marker,16)
    if not out.marker or out.marker==''or out.marker:find('%s')then return nil,'Маркер продолжения: короткий текст без пробелов, например ... или ….'end
    if out.display_limit-out.margin-out.fallback_nickname-math.max(out.me_extra,out.do_extra)<16 then return nil,'После запаса, ника и подписи должно остаться хотя бы 16 символов для текста.'end
    out.preview_text=shared.text(raw.preview_text or out.preview_text,2048)
    if not out.preview_text or out.preview_text==''then return nil,'Введите одну строку для проверки переноса.'end
    return out
end
return M
