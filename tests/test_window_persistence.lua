local layout=require 'pa26_window_layout';local menu=require 'pa26_menu';local model=require 'pa26_bindings';local core=require 'pa26_core'
local defaults=layout.defaults();eq(defaults.initial_percent,70);check(defaults.remember);check(defaults.wanted_separate)
local b=menu.windowBounds(1920,1080,'main');eq(b.width,1344);eq(b.height,756)
local saved={width=1100,height=620,x=80,y=50,displayW=1280,displayH=720}
local grown=assert(menu.windowRect(1920,1080,'main',saved));eq(grown.width,1650);eq(grown.height,930);eq(grown.x,120);eq(grown.y,75)
for _,size in ipairs({{640,480},{1280,720},{1920,1080},{2560,1440}})do
    for key in pairs(layout.keys)do local rect=assert(menu.windowRect(size[1],size[2],key,saved));check(rect.x>=16 and rect.y>=16);check(rect.x+rect.width<=size[1]-16 and rect.y+rect.height<=size[2]-16)end
end
defaults.windows.main=saved;check(layout.validate(defaults))
for _,bad in ipairs({0/0,math.huge,-1,40000})do local value=model.copy(defaults);value.windows.main.width=bad;check(not layout.validate(value))end
local fixture=require 'support.fixture'
local seed=model.defaults(core.defaults());seed.settings.window_layout.windows.main=model.copy(saved)
local s=fixture({productionWindows=true,demo=false,library=seed});s.step()
local window=s.windows['Police Assistant 2026##pa26-main'];eq(window.width,1100);eq(window.height,620);eq(window.x,80);eq(window.y,50)
local function same(a,b)
    eq(type(a),type(b));if type(a)~='table'then eq(a,b);return end
    for k,v in pairs(a)do same(v,b[k])end
    for k in pairs(b)do check(a[k]~=nil)end
end
local originalBinds=model.copy(s.workspace.library.bindings);local originalNotes=model.copy(s.workspace.library.notes)
s.resizeWindows={['Police Assistant 2026##pa26-main']={x=1000,y=600}};s.render();s.step(800)
local library=s.savedLibrary();eq(library.settings.window_layout.windows.main.width,1000);eq(library.settings.window_layout.windows.main.height,600)
same(library.bindings,originalBinds);same(library.notes,originalNotes)
local pending={kind='deferred'};local prepared={token='frozen'};s.workspace.pending=pending;s.workspace.prepared=prepared
check(s.workspace:saveLayout(library.settings.window_layout));eq(s.workspace.pending,pending);eq(s.workspace.prepared,prepared)
s.workspace.pending=nil;s.workspace.prepared=nil
onScriptTerminate(s.script)
s=fixture({productionWindows=true,demo=false,library=library});s.io.DisplaySize.x=1920;s.io.DisplaySize.y=1080;s.step()
window=s.windows['Police Assistant 2026##pa26-main'];eq(window.width,1500);eq(window.height,900);check(window.x>=16 and window.y>=16)
check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)
