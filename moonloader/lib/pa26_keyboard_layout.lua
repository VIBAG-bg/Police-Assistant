-- Read-only Windows input-language indicator. No keyboard hooks or layout changes.
local M={}

function M.native(ffi)
    if not ffi or ffi.os~='Windows' then return nil end
    -- A different MoonLoader script may already have declared these functions.
    for _,declaration in ipairs({
        'void* __stdcall GetForegroundWindow(void);',
        'unsigned long __stdcall GetWindowThreadProcessId(void*, unsigned long*);',
        'void* __stdcall GetKeyboardLayout(unsigned long);',
        'unsigned long __stdcall GetCurrentProcessId(void);',
        'int __stdcall GetLocaleInfoW(unsigned long, unsigned long, unsigned short*, int);',
    })do pcall(ffi.cdef,declaration)end
    local ok,api=pcall(function()
        local user=ffi.load('user32');local kernel=ffi.load('kernel32')
        return{_user=user,_kernel=kernel,foreground=user.GetForegroundWindow,windowThread=user.GetWindowThreadProcessId,
            layout=user.GetKeyboardLayout,process=kernel.GetCurrentProcessId,locale=kernel.GetLocaleInfoW}
    end)
    return ok and api or nil
end

function M.language(ffi,api,layout)
    if layout==nil then return nil end
    local lang=tonumber(ffi.cast('uintptr_t',layout))%65536
    if lang==0 then return nil end
    local buffer=ffi.new('unsigned short[16]')
    -- LOCALE_SISO639LANGNAME is an ISO language code (ru/en/bg/uk...), not
    -- the user's preferred browser language or the text typed in the input.
    local count=tonumber(api.locale(lang,0x59,buffer,16))
    if count~=3 and count~=4 then return nil end
    if buffer[count-1]~=0 then return nil end
    local out={}
    for i=0,count-2 do
        local c=tonumber(buffer[i]);if c<97 or c>122 then return nil end
        out[#out+1]=string.char(c-32)
    end
    return table.concat(out)
end

function M.reader(ffi,api)
    api=api or M.native(ffi)
    if not api then return function()return nil end end
    local ok,read=pcall(function()
        local pid=tonumber(api.process());local owner=ffi.new('unsigned long[1]')
        if not pid or pid<=0 then return function()return nil end end
        local cachedLayout,cachedCode
        return function()
            local window=api.foreground();if window==nil then return nil end
            owner[0]=0;local thread=tonumber(api.windowThread(window,owner))
            -- Do not display or inspect another application's input language.
            if not thread or thread<=0 or tonumber(owner[0])~=pid then return nil end
            local layout=api.layout(thread);if layout==nil then return nil end
            if layout~=cachedLayout or not cachedCode then
                cachedCode=M.language(ffi,api,layout);cachedLayout=layout
            end
            if api.foreground()~=window then return nil end
            return cachedCode
        end
    end)
    if not ok then return function()return nil end end
    return function()
        local success,code=pcall(read)
        if success then return code end
        -- An unavailable API or focus race must not interrupt PA or chat.
        return nil
    end
end

return M
