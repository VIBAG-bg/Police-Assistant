local fixture=require'support.fixture'
local core=require'pa26_core'
local model=require'pa26_bindings'
-- Keep independent overlays visible while pressing the compact panel's own X.
for _,overlay in ipairs({'none','alerts','taser','notifications'})do
    local seed=model.defaults(core.defaults());seed.weapon_warning.trigger='stable';seed.weapon_warning.trigger_revision=1
    local s=fixture({demo=false,alerts=true,notifications=true,library=seed});s.step()
    if s.frames[1].condition()then s.commands.pa26()end
    s.step();s.commands.pa26hudreset();s.step()
    -- render() owns a real-shaped ImGui context. Enable the explicit Alt cursor.
    s.down[0x12]=true;s.step();local r=s.hud.bounds or s.hud:layout(s.io.DisplaySize.x,s.io.DisplaySize.y)
    check(r);s.mx,s.my=r.x+r.w-12*r.scale,r.y+12*r.scale
    s.mouseClicks={[0]=true};s.step();s.mouseClicks=nil
    check(not s.hud.settings.visible,'compact X must hide the panel ('..overlay..')')
    eq(s.hud.bounds,nil);check(not s.hud.interactive and not s.hud.editing and not s.hud.drag)
    s.down[0x12]=false
    if overlay=='alerts'then s.commands.pa26sos()
    elseif overlay=='taser'then s.weapon=24
    elseif overlay=='notifications'then s.weapon=23 end
    s.drawnText={};s.step();for _=1,6 do s.step(1000)end
    for _,text in ipairs(s.drawnText)do check(text~='Police Assistant','other overlays must not redraw the hidden HUD')end
    check(not s.hud.settings.visible)
    check(not s.hud.failed);check(not s.hasLog('Ошибка интерфейса'));check(not s.hasLog('Компактный виджет отключён'))
    if overlay=='alerts'then check(s.alerts:visible())
    elseif overlay=='taser'then check(s.taser:view().visible)
    elseif overlay=='notifications'then check(s.notifications:view().visible)end
    eq(s.saved.widget.visible,false,'hidden flag is saved without changing other settings')
    -- A forced render must not touch ImGui at all for a hidden/failed HUD.
    local touched=false;s.hud:draw({GetIO=function()touched=true;error('hidden')end});check(not touched)
    onScriptTerminate(s.script)
end
local s=fixture({demo=false});s.step();s.commands.pa26hudreset();s.step()
s.hud:setVisible(false);onScriptTerminate(s.script)
eq(s.saved.widget.visible,false,'quitting before the debounce must preserve the close')
