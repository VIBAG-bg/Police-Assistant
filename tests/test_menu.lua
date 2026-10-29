local fixture=require 'support.fixture'
local core=require 'pa26_core'
local menuModule=require 'pa26_menu'
local s=fixture(); s.step()
check(s.frames[1].condition()); check(s.frames[3].condition()); eq(s.textureLoads,2) -- This historical fixture explicitly uses a large configured window.
for _,call in ipairs(s.childCalls) do
    check(require('bit').band(call.flags,65536)~=0,'child padding must be explicitly enabled in native ImGui')
end
for _,size in ipairs({{440,300},{640,480},{800,600},{1180,920},{2560,1440}}) do
    local r=menuModule.layout(size[1],size[2]); check(r~=nil)
    check(r.x>=r.margin+r.side+r.gap); check(r.x+r.w<=size[1]-r.margin)
    check(r.bodyY>=r.headerY+r.headerH+r.gap)
    check(r.bodyY+r.bodyH<=r.footerY-r.gap)
    check(r.footerY+r.footerH<=size[2]-r.margin)
end
eq(menuModule.layout(0/0,720),nil); eq(menuModule.layout(1180,0/0),nil)
check(not s.hasLog('Ошибка интерфейса')); check(not s.hasLog('Не удалось загрузить шрифт'))
s.io.KeysDown[0x49],s.io.MouseDown[0],s.io.queuedCharacters=true,true,true
s.io.MouseWheel=7
onWindowMessage(0x0008,0); onWindowMessage(0x0007,0); s.commands.pa26(); s.step()
eq(s.io.KeysDown[0x49],false); eq(s.io.MouseDown[0],false); eq(s.io.queuedCharacters,false); eq(s.io.MouseWheel,0)
check(s.frames[1].condition()); eq(s.invalidIOReads,0)
for _,section in ipairs(menuModule.sections) do
    s.page(section.key); check(s.click==nil,'navigation click not handled: '..section.key)
    s.step(); check(s.frames[1].condition()); check(not s.hasLog('Ошибка интерфейса'))
end
for _,label in ipairs({'Список команд','Список клавиш','Список функций','Список переменных'}) do
    s.click=label..'##footer'; s.render(); s.render(); eq(s.click,nil); check(s.frames[1].condition())
end
s.page('home');s.click='Отключить PA##home';s.render();check(s.workspace.studio.shutdownConfirm)
s.click='НЕТ — отмена##confirm-no';s.render();check(not s.workspace.studio.shutdownConfirm)
s.commands.pa26();s.step()
check(not s.frames[1].condition()); check(s.frames[3].condition(),'closing main must preserve independent HUD')
eq(#s.sent,0); check(s.inputDisabled()); check(s.keyMessage(0x49,true))
s.commands.pa26hud(); s.step(); check(not s.frames[3].condition())
s.commands.pa26hudreset(); s.step(); check(s.frames[3].condition())

local function artworkFixture(options)options=options or{};options.library=require('pa26_bindings').defaults(core.defaults());options.library.settings.window_layout.initial_percent=95;return fixture(options)end
-- Real bitmap dimensions are used, never a stretched fixed-height slot.
s=artworkFixture(); s.step()
eq(#s.imageDraws,2)
check(math.abs(s.imageDraws[1].w/s.imageDraws[1].h-1)<0.0001)
check(math.abs(s.imageDraws[2].w/s.imageDraws[2].h-1983/793)<0.0001)
s.render(); eq(s.textureLoads,2,'reopen/render must use cache')
onD3DDeviceLost(); eq(s.textureReleases,2)
s.commands.pa26(); s.step(); eq(s.textureLoads,4)
onScriptTerminate(s.script); eq(s.textureReleases,4)
onScriptTerminate(s.script); eq(s.textureReleases,4,'cleanup must be idempotent')

-- Reproduce the mid-frame failure: queued texture remains owned until cleanup.
s=artworkFixture(); s.rectError=true; s.step()
eq(s.textureLoads,2); eq(s.textureReleases,0); check(s.frames[1].condition())
s.rectError=false; s.render(); eq(s.textureLoads,2); eq(s.textureReleases,0)
onScriptTerminate(s.script); eq(s.textureReleases,2)
s=artworkFixture(); s.textureFail=true; s.step(); s.render(); eq(s.textureLoads,2)
check(s.frames[1].condition()); check(not s.hasLog('Ошибка интерфейса'))
s=artworkFixture(); s.hudDrawError=true; s.step(); check(not s.frames[3].condition()); check(s.frames[1].condition())
check(s.hasLog('Компактный виджет отключён'))
for _,size in ipairs({{640,480},{800,600},{1920,1080},{2560,1440},{100,100},{0/0,720},{1280,0/0}}) do
    s=fixture(); s.io.DisplaySize.x,s.io.DisplaySize.y=size[1],size[2]; s.step()
    check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0)
end
s=fixture(); s.step(); s.hideChild=true; s.render(); check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0)
s=fixture(); s.step(); s.commands.pa26(); s.io.DisplaySize.x=0/0; s.down[0x58]=true; s.step(16,{[0x58]=true})
check(not s.frames[2].condition()); eq(#s.sent,0)

-- Dragging/closing HUD uses explicit Alt editing and cannot save RP drafts.
s=fixture(); s.step(); s.page('addons')
s.edits={['##me']='несохранённый черновик'}; s.render(); s.commands.pa26(); s.step()
s.down[0x12],s.down[0x02]=true,true; s.mx,s.my=20,180; s.mouseClicks={[1]=true}; s.step()
check(not s.frames[1].condition()); check(not s.frames[3].HideCursor)
s.mouseClicks={}; s.mx,s.my=100,220; s.step()
s.down[0x02]=false; s.step(); s.down[0x12]=false; s.step(800)
eq(s.saved.widget.x,88); eq(s.saved.widget.y,210)
eq(s.saved.introduce.me,core.defaults().introduce.me,'HUD save must preserve unsaved RP text')
check(s.inputDisabled()); eq(s.lockRequests,0)
s.down[0x12],s.down[0x01]=true,true; s.mx,s.my=348,222; s.mouseClicks={[0]=true}; s.step()
check(not s.frames[3].condition()); s.commands.pa26hudreset(); s.step(); check(s.frames[3].condition())

-- Bounded image input, unavailable paths, and IO errors must degrade locally.
local originalOpen=io.open
local function u32(n) return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local header='\137PNG\r\n\26\n'..u32(13)..'IHDR'..u32(20)..u32(10)
for _,case in ipairs({{nil,0},{'bad',3},{header,16777217},
    {'\137PNG\r\n\26\n'..u32(13)..'IHDR'..u32(5000)..u32(10),50}}) do
    s=fixture(); local menu=menuModule.new(); menu:configureAssets('fake',function() end)
    io.open=function() if not case[1] then return nil end; return {read=function() return case[1] end,seek=function() return case[2] end,close=function() end} end
    s.rendererContext=true; eq(menu:loadAsset(s.imgui,'banner'),nil); eq(menu:loadAsset(s.imgui,'banner'),nil)
    eq(s.textureLoads,0); s.rendererContext=false; io.open=originalOpen
end
s=fixture(); local menu=menuModule.new(); local closed=false; menu:configureAssets('fake',function() end)
io.open=function() return {read=function() error('read failure') end,close=function() closed=true end} end
s.rendererContext=true; eq(menu:loadAsset(s.imgui,'banner'),nil); check(closed); s.rendererContext=false; io.open=originalOpen
