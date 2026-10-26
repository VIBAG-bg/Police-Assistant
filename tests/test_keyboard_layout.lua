local ffi=require'ffi';local layout=require'pa26_keyboard_layout'
local ptr=function(n)return ffi.cast('void*',n)end
local languages={[0x419]='ru',[0x409]='en',[0x809]='en',[0x402]='bg',[0x422]='uk',[0x411]='ja',[0x464]='fil'}
local state={window=ptr(10),owner=42,thread=7,layout=ptr(0xf0190419),localeCalls=0}
local api={process=function()return 42 end,foreground=function()return state.window end,
    windowThread=function(window,out)eq(window,ptr(10));out[0]=state.owner;return state.thread end,
    layout=function(thread)eq(thread,7);return state.layout end,
    locale=function(lang,kind,out,count)
        state.localeCalls=state.localeCalls+1;eq(kind,0x59);eq(count,16)
        local code=state.bad or languages[lang];if not code then return 0 end
        for i=1,#code do out[i-1]=code:byte(i)end;out[#code]=0
        return #code+1
    end}
local read=layout.reader(ffi,api)
eq(read(),'RU');local calls=state.localeCalls;eq(read(),'RU');eq(state.localeCalls,calls,'unchanged HKL reuses only its label')
for id,code in pairs(languages)do state.layout=ptr(id);eq(read(),code:upper())end
state.owner=99;calls=state.localeCalls;eq(read(),nil);eq(state.localeCalls,calls,'another process is never inspected')
state.owner=42;state.window=nil;eq(read(),nil);state.window=ptr(10)
state.thread=0;eq(read(),nil);state.thread=7
state.layout=nil;eq(read(),nil);state.layout=ptr(0);eq(read(),nil)
state.layout=ptr(0x7777);eq(read(),nil,'unknown locale is not guessed from the browser language')
for _,bad in ipairs({'r','russ','RU','r1','<x','r\0'})do state.bad=bad;eq(read(),nil)end
state.bad=nil;state.layout=ptr(0x409);eq(read(),'EN','recovers after invalid locale')
local old=api.foreground;local reads=0
api.foreground=function()reads=reads+1;return reads%2==1 and ptr(10)or ptr(11)end
eq(read(),nil,'focus changed while reading');api.foreground=old
api.layout=function()error('unavailable API')end;eq(read(),nil)
eq(layout.reader(nil)(),nil);eq(layout.reader({os='Linux'})(),nil)
eq(layout.reader(ffi,{process=function()error('missing API')end})(),nil)

-- The live bridge computes the language only for an open, enabled CEF chat.
local fixture=require'support.fixture';local model=require'pa26_bindings';local core=require'pa26_core'
local seed=model.defaults(core.defaults());eq(seed.settings.cef_layout_indicator,true)
seed.settings.cef_layout_indicator=nil;eq(assert(model.validate(seed,core.defaults())).settings.cef_layout_indicator,true)
seed.settings.cef_layout_indicator=false;eq(assert(model.validate(seed,core.defaults())).settings.cef_layout_indicator,false)
seed.settings.cef_layout_indicator='false';check(not model.validate(seed,core.defaults()))
seed.settings.cef_layout_indicator=true;seed.profile.accent='[Личный акцент]:'
local f=fixture({demo=false,library=seed});f.step();local bridge=f.chatBridge;local reads=0;local code='RU'
bridge.env.layout=function()reads=reads+1;return code end
local function poll(chat)
    return decodeJson(assert(bridge:exchange(encodeJson({schema=1,page='keyboard',chat=chat,dialog=false,busy=chat,events={}}),f.now)))
end
local result=poll(false);eq(reads,0);eq(result.layoutIndicator,true);eq(result.keyboardLayout,nil)
result=poll(true);eq(result.keyboardLayout,'RU');eq(reads,1)
code='EN';eq(poll(true).keyboardLayout,'EN')
for _,bad in ipairs({'ru','R','RUSSIAN','<b>','RU\n','РУ',false})do code=bad;eq(poll(true).keyboardLayout,nil)end
code='BG';eq(poll(true).keyboardLayout,'BG')
bridge.env.layout=function()error('not available')end;eq(poll(true).keyboardLayout,nil)
bridge.env.layout=function()error('must not run when disabled')end
f.workspace.library.settings.cef_layout_indicator=false;result=poll(true);eq(result.layoutIndicator,false);eq(result.keyboardLayout,nil)
f.workspace.library.settings.cef_chat_support=false;f.workspace.library.settings.cef_layout_indicator=true
result=poll(true);eq(result.enabled,false);eq(result.keyboardLayout,nil)
f.workspace.library.settings.cef_chat_support=true
poll(false)

-- Russian GUI, immediate save, reload and personal accent preservation.
f.page('settings');require('support.ui_routes').chat(f,'filters')
local preset=false;for _,button in ipairs(f.buttonCalls)do if button.label=='Русский акцент##accent-default'then preset=true end end
check(not preset,'the redundant accent preset button has been removed')
f.toggle='Язык ввода рядом с полем чата##cef-layout';f.render();f.step(650)
eq(f.workspace.library.settings.cef_layout_indicator,false)
local path='moonloader\\config\\police_assistant_2026_library.json'
local saved=f.savedLibrary();eq(saved.settings.cef_layout_indicator,false);eq(saved.profile.accent,'[Личный акцент]:')
eq(assert(model.validate(saved,core.defaults())).settings.cef_layout_indicator,false)
f.toggle='Язык ввода рядом с полем чата##cef-layout';f.render();f.step(650)
saved=f.savedLibrary();eq(saved.settings.cef_layout_indicator,true);eq(saved.profile.accent,'[Личный акцент]:')
eq(#f.sent,0,'indicator and settings never send a game message')
onScriptTerminate(f.script)
