-- Manual chat rules shared by native chat and the CEF adapter.
-- Command names use keyboard positions, not a server command allowlist.
local core=require 'pa26_core'
local M={VERSION=1}
local map={}
local source='йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ'
local target="qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP[]ASDFGHJKL;'ZXCVBNM,.`"
local i=0
for char in source:gmatch('[\194-\244][\128-\191]*')do i=i+1;map[char]=target:sub(i,i)end
assert(i==#target,'Keyboard map length mismatch')

function M.policy(settings)
    settings=settings or{}
    local copy={};for key,value in pairs(map)do copy[key]=value end
    local manual
    if settings.manual_chat and settings.rp_text then
        local cfg=require('pa26_manual_chat').validate(settings.manual_chat)
        local rp=require('pa26_rp_settings').validate(settings.rp_text)
        if cfg and rp then manual={enabled=cfg.enabled,maxParts=cfg.max_parts,threshold=rp.body_limit,marker=rp.marker,
            displayLimit=rp.display_limit,margin=rp.margin,meExtra=rp.me_extra,doExtra=rp.do_extra,
            nicknameLength=require('pa26_rp_text').nicknameLength(settings.nickname,rp),rpEnabled=rp.enabled,speechEnabled=rp.speech_enabled,channels=rp.channels,todoActionLimit=rp.todo_action_limit}end
    end
    return{version=M.VERSION,manual=manual,skipBrackets=settings.accent_skip_brackets~=false,
        dotCommands=settings.chat_dot_commands~=false,keyboardMap=copy,
        radioPrefix={enabled=settings.manual_radio_prefix~=false,localTag=type(settings.local_tag)=='string'and settings.local_tag or''}}
end
function M.skipAccent(text,settings)
    if type(text)~='string'then return false end
    settings=settings or{}
    return text:match('^%s*[/!]')~=nil or text:match('^%s*$')~=nil or
        settings.accent_skip_brackets~=false and text:match('^%s*[()]')~=nil or
        settings.chat_dot_commands~=false and text:sub(1,1)=='.'
end
function M.dotCommand(text,settings)
    if type(text)~='string'or(settings and settings.chat_dot_commands==false)or text:sub(1,1)~='.'or
        text:sub(2,2)=='.'or not core.validUtf8(text)then return text,false end
    -- Only the initial token is mapped. Arguments are kept byte-for-byte.
    local name,rest=text:match('^%.([^ \t\r\n]+)(.*)$')
    if not name then return text,false end
    local translated=name:gsub('[%z\1-\127\194-\244][\128-\191]*',function(c)return map[c]or c end)
    if not translated:match('^[A-Za-z][A-Za-z0-9_]*$')then return text,false end
    return'/'..translated..rest,true
end
-- This helper is called only for an identified manual submission. Templates and
-- other scripts' automatic commands retain their own text and channel.
function M.radioCommand(text,settings)
    settings=settings or{}
    local tag=settings.local_tag
    if type(text)~='string'or settings.manual_radio_prefix==false or type(tag)~='string'or tag==''then return text,false end
    local head,space,body=text:match('^( */[rR])( +)(.*)$')
    if not head or body:match('^ *$')then return text,false end
    local supplied=body:sub(1,#tag)==tag and(body==tag or body:sub(#tag+1,#tag+1)==' 'or tag:sub(-1):match('%p')~=nil)
    return supplied and text or head..space..tag..' '..body,true
end
return M
