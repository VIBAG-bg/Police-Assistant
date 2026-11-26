-- Immutable color roles. Renderers resolve one palette per surface.
local M={default='police',choices={
    {'police','Полиция · Морской синий'},
    {'swat','SWAT · Тёмный графит'},
    {'fbi','FBI · Строгий индиго'},
    {'alcatraz','Алькатрас · Сталь и янтарь'},
}}

local function readonly(data)
    return setmetatable({},{
        __index=data,
        __newindex=function()error('Palette is read-only',2)end,
        __metatable=false,
    })
end
local function color(r,g,b,a)return readonly({r,g,b,a or 1})end
local function tint(c,a)return color(c[1],c[2],c[3],a)end
local function mix(a,b,x,alpha)
    return color(a[1]+(b[1]-a[1])*x,a[2]+(b[2]-a[2])*x,a[3]+(b[3]-a[3])*x,alpha)
end

local safe=color(.38,.86,.63)
local warn=color(1,.79,.39)
local alert=color(1,.52,.52)
local muted=color(.72,.79,.86)
local white=color(.96,.98,1)
local danger=color(.48,.16,.23)
local function palette(bg,surface,accent,primary)
    return readonly({
        text=white,textMuted=muted,
        windowBg=tint(bg,.86), childBg=tint(surface,.36), cardBg=tint(surface,.55),
        sidebarBg=mix(surface,accent,.17,.91), headerBg=mix(surface,accent,.12,.87),
        footerBg=tint(surface,.67), border=mix(surface,accent,.63,.40),
        popupBg=mix(bg,surface,.65,.99), separator=mix(surface,accent,.48,.46),
        frameBg=tint(surface,.94), frameHovered=mix(surface,primary,.55),
        frameActive=primary, scrollbarBg=tint(bg,.42),
        scrollbarGrab=mix(surface,accent,.34), scrollbarGrabHovered=mix(surface,accent,.56),
        scrollbarGrabActive=mix(surface,accent,.72), sliderGrab=tint(accent,.84),
        sliderGrabActive=accent, checkMark=accent,
        btnPrimary=primary, btnPrimaryHover=mix(primary,accent,.19), btnPrimaryActive=mix(primary,accent,.30),
        btnSecondary=tint(surface,.96), btnSecondaryHover=mix(surface,primary,.55),
        btnSecondaryActive=mix(surface,primary,.79),
        btnDanger=danger, btnDangerHover=color(.60,.21,.29), btnDangerActive=color(.64,.23,.31),
        hudBg=tint(bg,.91), hudHeader=tint(primary,.97),
        hudBorder=mix(surface,accent,.64,.59), hudBadge=mix(surface,primary,.55,.95),
        wheelRoot=tint(surface,.86), wheelRootActive=tint(primary,.96),
        wheelRootPending=mix(surface,primary,.64,.93), wheelChild=mix(bg,surface,.77,.91),
        wheelChildSelected=tint(primary,.97), wheelCenter=tint(bg,.96), wheelAccent=accent,
        wheelDivider=tint(bg,.94), wheelChildDisabled=tint(bg,.78),
        toastBg=mix(bg,surface,.47,.97), toastBodyBg=mix(surface,primary,.23,.93),
        statusSafe=safe, statusWarn=warn, statusAlert=alert, statusMuted=muted,
    })
end

local palettes={
    police=palette(color(.040,.068,.107),color(.074,.143,.213),color(.32,.77,.95),color(.080,.335,.490)),
    swat=palette(color(.040,.053,.065),color(.095,.132,.157),color(.42,.82,.87),color(.145,.345,.391)),
    fbi=palette(color(.044,.054,.107),color(.107,.129,.229),color(.56,.70,1.0),color(.203,.281,.553)),
    alcatraz=palette(color(.064,.062,.060),color(.150,.132,.107),color(.96,.73,.40),color(.389,.273,.127)),
}

function M.valid(id)return type(id)=='string' and palettes[id]~=nil end
function M.get(id)return M.valid(id) and palettes[id] or palettes[M.default] end
function M.vec(im,c,alpha)return im.ImVec4(c[1],c[2],c[3],alpha or c[4])end
function M.u32(im,c,alpha)return im.ColorConvertFloat4ToU32(M.vec(im,c,alpha))end

return M
