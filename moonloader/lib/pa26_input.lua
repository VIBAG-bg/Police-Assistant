-- Physical state for configured UI shortcuts. ImGui may consume game key events
-- or clear its own cache on opening a window. No text capture or key log.
local ffi=require 'ffi'
local bit=require 'bit'
local core=require 'pa26_core'
local M={MAX_SHORTCUTS=64};local Input={};Input.__index=Input
local function nativeReader()
    local ok,result=pcall(function()
        ffi.cdef [[short __stdcall GetAsyncKeyState(int vKey);]]
        local user32=ffi.load('user32')
        local fn=user32.GetAsyncKeyState
        return function(key)return tonumber(fn(key))end
    end)
    return ok and result or nil
end
function M.new(reader)
    return setmetatable({reader=reader or nativeReader()},Input)
end
function Input:resetMenu()
    if self.menu then self.menu.pending=nil;self.menu.messageDown=false;self.menu.armed=false;self.menu.firedHold=true end
end
function Input:observeMenu(message,key,configured,lparam)
    if key~=configured then return end
    local s=self.menu
    if not s or s.key~=configured then s={key=configured,armed=false};self.menu=s end
    if message==0x100 or message==0x104 then
        local repeated=type(lparam)=='number'and bit.band(lparam,0x40000000)~=0
        if not repeated and not s.messageDown then s.pending=true end
        s.messageDown=true;s.messageSeen=true
    elseif message==0x101 or message==0x105 then s.messageDown=false;s.messageSeen=true end
end
-- One physical hold / window-message cycle produces one toggle. A quick tap
-- between game frames is retained by WM_KEYDOWN; legacy polling is not mixed
-- with a working physical reader, which used to toggle again on key release.
function Input:menuPressed(key,allowed,keys,legacy,chord)
    local s=self.menu
    if not s or s.key~=key then s={key=key,armed=false};self.menu=s end
    local physical=keys and keys.physical==true
    local down=physical and keys.keys[key]==true
    local pending=s.pending;s.pending=false
    local legacyEdge=legacy==true and not s.legacy;s.legacy=legacy==true
    local released=physical and not down or not physical and not s.messageDown
    local candidate=pending or down and s.armed or not physical and not s.messageSeen and legacyEdge
    local modifiers=keys and(keys.ctrl or keys.alt or keys.shift or keys.super)
    local matched=not modifiers
    if chord and keys then matched=not keys.super and keys.ctrl==chord.ctrl and keys.alt==chord.alt and keys.shift==chord.shift end
    local fired=allowed and matched and candidate and not s.firedHold
    if fired then s.firedHold=true;s.armed=false end
    if candidate and not fired then s.firedHold=true;s.armed=false end
    if not allowed then s.armed=false end
    if released then s.firedHold=false;s.armed=true;if physical then s.messageDown=false end end
    if fired then return true,pending and'message'or physical and'physical'or'legacy'end
    if candidate and not allowed then return false,'blocked'end
    return false
end
function Input:read(shortcuts)
    if not self.reader then return nil end
    local ok,result=pcall(function()
        local function down(key)
            local raw=self.reader(key)
            assert(core.finite(raw) and raw==math.floor(raw) and raw>=-32768 and raw<=65535)
            return bit.band(raw,0x8000)~=0 -- Only current-down bit; the low press bit is unreliable.
        end
        local y,n=down(0x59),down(0x4e)
        local ctrl,alt,shift,winL,winR=down(0x11),down(0x12),down(0x10),down(0x5b),down(0x5c)
        local result={physical=true,y=y,n=n,mods=ctrl or alt or shift or winL or winR,
            ctrl=ctrl,alt=alt,shift=shift,super=winL or winR,keys={[0x59]=y,[0x4e]=n}}
        if shortcuts then
            assert(type(shortcuts)=='table' and #shortcuts<=M.MAX_SHORTCUTS)
            for _,s in ipairs(shortcuts)do
                assert(type(s)=='table' and core.finite(s.key) and s.key==math.floor(s.key) and s.key>=0 and s.key<=254)
                if s.key~=0 and result.keys[s.key]==nil then result.keys[s.key]=down(s.key)end
            end
        end
        return result
    end)
    return ok and result or nil
end
-- Only configured shortcuts, release before activation, exact modifiers and no
-- key history. Context loss or a changed assignment disarms held keys.
function Input:poll(shortcuts,allowed,keys)
    self.edges=self.edges or {};local selected
    for _,row in ipairs(shortcuts)do
        local s=row.shortcut;local name=table.concat({s.key,tostring(s.ctrl),tostring(s.alt),tostring(s.shift)},':')
        local entry=self.edges[row.id]
        if not entry or entry.name~=name then entry={name=name,armed=false};self.edges[row.id]=entry end
        local down=keys and keys.keys and keys.keys[s.key]==true
        if not allowed or not keys or not keys.physical then entry.armed=false
        elseif not down then entry.armed=true
        elseif entry.armed then
            entry.armed=false
            if s.key~=0 and not keys.super and keys.ctrl==s.ctrl and keys.alt==s.alt and keys.shift==s.shift then selected=selected or row.id end
        end
    end
    return selected
end
return M
