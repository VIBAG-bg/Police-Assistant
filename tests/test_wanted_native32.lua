-- Installed 32-bit ImGui, CPU-only. This does not start GTA or write game files.
local src=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(src:match('^(.*[/])'));local release=tests..'../'
local game=assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA required')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=release..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',
    StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do
    im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})
end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),
    int=function(v)return ffi.new('int[1]',v)end,float=function(v)return ffi.new('float[1]',v)end,bool=function(v)return ffi.new('bool[1]',v)end}
local ctx=im.CreateContext(nil);local guiIo=im.GetIO();guiIo.IniFilename=nil;guiIo.LogFilename=nil;guiIo.DeltaTime=1/60
guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',16,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local bold=guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',18,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local editor=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)

local checks,frames=0,0;local function check(ok,why)checks=checks+1;assert(ok,why)end
editor.buttonFont=bold
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
    text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local prefs=require 'pa26_procedure_settings';local wanted=require 'pa26_wanted_ui';local forms=require 'pa26_case_forms'
local cfg=prefs.defaults();cfg.allow_ooc=true
local target={id=37,ped=99,name='Longest_Player_Name_Long'}
local converter=require('encoding').CP1251
local nativeCodec={encode=function(v)return converter:encode(v,'UTF-8')end,decode=function(v)return converter:decode(v,'UTF-8')end}
local state={session='native-test',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,inVehicle=false}
local c=forms.new({settings=function()return cfg end,target=function()return target,1 end,identity=function()return {}end,
    codec=nativeCodec,equal=function()return true end,validTarget=function()return true end,
    start=function()error('Native QA must not send')end})
c:tick(state,1000)
local cb={caseBegin=function(k)return c:begin(k)end,caseBranch=function(f)return c:branch(f)end,
    caseFillWanted=function(f)return c:fillWanted(f)end,caseValid=function(f)return c:validForm(f)end,
    caseSuggestOoc=function(f)return c:oocSuggested(f)end,caseChooseOoc=function(f)return c:chooseOoc(f)end,
    caseAppearance=function(f,mode)return c:chooseAppearance(f,mode)end,
    caseTemplatePreview=function(t,f)return c:templatePreview(t,f)end,casePreview=function(f)return c:preview(f)end}
setmetatable(cb,{__index=function()return function()error('Native QA must not execute actions')end end})
local data={caseForms={reminders={{token='native-reminder',player_id=37,player_name=target.name,session='native-test',
    reason='01.01 · Нападение / Нападение на гражданина',context=prefs.oocNotes.tracking,stars=1,status='check'}}}}
local detachedNow=false
local widthNow,pageNow,frameNow;local seen={};local modalCount=0
for _,name in ipairs({'InputInt','InputText','InputTextMultiline','Button'})do
    local original=im[name]
    im[name]=function(label,...)
        local result=original(label,...)
        if label:find('wanted',1,true)or label:find('##case-new',1,true)or label:find('##confirm%-yes$')or label:find('##confirm%-no$')or label:find('##confirm%-cancel$')then
            local lo,hi=im.GetItemRectMin(),im.GetItemRectMax();local pos,size=im.GetWindowPos(),im.GetWindowSize()
            if name=='InputTextMultiline'then check(pos.x>=0 and pos.x+size.x<=guiIo.DisplaySize.x,'Multiline viewport overflow')else check(lo.x>=pos.x-1 and hi.x<=pos.x+size.x+1,'Overflow: '..pageNow..' '..label)end
            if detachedNow then check(lo.y>=pos.y and hi.y<=pos.y+size.y-8,'Detached control clipped vertically: '..pageNow..' '..label)end
            if im.IsItemVisible()then seen[widthNow..':'..label]=true end
            if label:find('##confirm%-yes$')or label:find('##confirm%-no$')or label:find('##confirm%-cancel$')then
                check(lo.y>=pos.y and hi.y<=pos.y+size.y,'Modal buttons overflow')
                local color=im.GetStyle().Colors[im.Col.Button]
                if label:find('##confirm%-yes$')then check(color.y>color.x,'YES must be green')
                elseif pageNow~='manual_action'or label:find('##confirm%-cancel$')then check(color.x>color.y,'Cancel/NO must be red')
                else check(color.z>color.x,'Manual NO must be neutral, distinct from cancel')end
            end
            if label:find('##wanted%-appearance%-first')or label:find('##wanted%-appearance%-second')or label=='##Приметы##wanted-appearance-modal'then
                check(lo.y>=pos.y and hi.y<=pos.y+size.y,'Appearance modal control clipped: '..label)
            end
        end
        return result
    end
end
local originalEnd=im.EndPopup
im.EndPopup=function()
    -- ImGui reports the previous content extent on the first resized frame.
    -- Actual control bounds are checked on every frame, including that frame.
    if frameNow>=3 then check(im.GetScrollMaxY()<1,'Confirmation has inner scrolling: '..tostring(pageNow)..' width='..tostring(widthNow)..' display='..guiIo.DisplaySize.x..'x'..guiIo.DisplaySize.y..' max='..im.GetScrollMaxY())end
    modalCount=modalCount+1;return originalEnd()
end
local function form(page)
    local f=assert(c:begin(page=='list'and'wanted_list'or'wanted'))
    f.life_ack=true;f.passport_seen='no';f.mask='no';f.appearance='синяя куртка, известные приметы';f.reason_id='08.01';f.facts='Законное требование в текущей ситуации.'
    if page=='passport'then f.passport_seen='yes';f.ic_name='John Smith';f.passport_number='12345'
    elseif page=='mask'or page=='mask_passport'then f.mask='yes';f.face_before='yes';if page=='mask_passport'then f.passport_seen='yes';f.ic_name='John Smith'end
    elseif page=='ooc'or page=='phone'then f.mode='ooc';f.ooc_ack=true;f.ooc_reason='tracking';f.phone_known='yes';f.phone_number='555123';f.phone_source='Владелец сообщил по RP.'
    elseif page=='basis'then f.stage='basis'
    elseif page=='appearance_choice'or page=='appearance_input'then f.stage=page
    elseif page=='preview'or page=='final'then f.stage='preview';f.inVehicle=true;state.inVehicle=true;c:tick(state,1000)end
    return f
end
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2])
    for _,width in ipairs({300,500,math.min(display[1]-32,1100)})do
        widthNow=width
        for _,page in ipairs({'settings','identity','passport','mask','ooc','appearance_choice','appearance_input','basis','preview','list','review','final','manual_action'})do
            pageNow=page;state.inVehicle=false;c:tick(state,1000)
            editor.caseForm=form(page);editor.caseKind=page=='list'and'wanted_list'or'wanted'
            editor.caseConfirm=nil;editor.wantedAppearance=nil;editor.modalToken=nil;editor.modalVisible=false
            editor.manualAction=nil
            if page=='manual_action'then editor.manualAction={token='native-manual',lines={'/cuff 37','ДА — RP и команда. НЕТ — только команда. Esc — отменить.','/me снял наручники с пояса.','/do Фиксация проверена.'}}end
            if page=='final'then
                local p=assert(c:preview(editor.caseForm));p.phase='command';p.token='native-final';p.lines={p.lines[#p.lines]};editor.caseConfirm=p
            end
            local bottom=0
            for frame=1,160 do
                frameNow=frame
                im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(width,display[2]-32),im.Cond.Always)
                im.Begin('wanted-native-'..page,nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
                if frame==1 then im.SetScrollY(0)end
                editor.currentUi=ui
                if page=='settings'then wanted.settings(editor,ui,cfg,cb)
                elseif page=='review'then wanted.review(editor,ui,data,cb)
                elseif page=='final'or page=='manual_action'then editor:drawModal(ui,data,cb)
                elseif page=='appearance_choice'or page=='appearance_input'then wanted.form(editor,ui,data,cb,cfg);editor:drawModal(ui,data,cb)
                else wanted.form(editor,ui,data,cb,cfg)end
                check(#stack==0,'Unbalanced scopes: '..page)
                local atBottom=frame>=3 and im.GetScrollY()>=im.GetScrollMaxY()-1;bottom=atBottom and bottom+1 or 0
                if frame>=2 then im.SetScrollY(math.min(im.GetScrollMaxY(),im.GetScrollY()+math.max(90,(display[2]-32)*.55)))end
                im.End();im.Render();check(im.GetDrawData().Valid,'No draw data');frames=frames+1
                if bottom>=2 then break end
            end
        end
    end
end
editor.manualAction=nil
for _,label in ipairs({'##wanted-time-delay_ms','##Текст напоминания##wanted-reminder-text','##Приметы##wanted-appearance-modal',
    'Общая (без ввода)##wanted-appearance-first','С приметами##wanted-appearance-second','Далее · к выбору статьи##wanted-appearance-first','Назад##wanted-appearance-second',
    'Проверить отыгровку и команду##wanted-preview','Отыграть ориентировку в чат (затем ДА/НЕТ на выдачу)##wanted-prepare','ДА — выдать розыск##confirm-yes','НЕТ — не выдавать розыск##confirm-no','Отменить всё (Esc) — не отправлять##confirm-cancel'})do
    check(seen['300:'..label],'Required control unreachable at 300 px: '..label)
end
check(modalCount>0)
local hudModule=require 'pa26_hud';local hud=hudModule.new(core.widgetDefaults(),{})
hud.connected=true;hud.data={identity='Victor_Auditore[45] | Ping: 69',district='San Fierro',clock='24.10.2026 12:00:00'}
local bodyFont=guiIo.Fonts.Fonts.Data[0]
check(bold~=nil and bodyFont~=nil and bold~=bodyFont,'A distinct bold font must be loaded')
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2])
    for _,square in ipairs({'J-6','X-24'})do
        hud.mapSquare=square;im.NewFrame();hud:draw(im,bodyFont,bold)
        local r=hud.bounds;check(r and r.x+r.w<=display[1]+1 and r.y+r.h<=display[2]+1,'HUD exceeds screen')
        local labelW=bodyFont:CalcTextSizeA(14*r.scale,100000,0,'Квадрат карты: ').x
        local codeW=bold:CalcTextSizeA(17*r.scale,100000,0,square).x
        check(labelW+codeW<=242*r.scale,'Larger bold square label clipped')
        im.Render();check(im.GetDrawData().Valid,'Invalid HUD draw data');frames=frames+1
    end
end
local detached=require 'pa26_wanted_window';local geometry=require 'pa26_menu'
detachedNow=true
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2]);local rect=geometry.windowRect(display[1],display[2],'wanted')
    for _,page in ipairs({'identity','passport','mask','mask_passport','mask_details','mask_passport_details','ooc','ooc_details','phone','basis','preview','details','passport_edit'})do
        pageNow='detached-'..page;widthNow=rect.width;state.inVehicle=false;c:tick(state,1000)
        local formPage=({details='basis',passport_edit='passport',mask_details='mask',mask_passport_details='mask_passport',ooc_details='ooc'})[page]or page
        editor.caseForm=form(formPage);editor.caseKind='wanted'
        editor.caseConfirm=nil;editor.wantedAppearance=nil;editor.wantedIdentityPage=nil;editor.wantedPreviewPage=1
        if page=='phone'then editor.wantedIdentityPage='phone'end
        if page=='mask_details'or page=='mask_passport_details'or page=='ooc_details'then editor.wantedIdentityPage='details'end
        editor.wantedBasisDetails=page=='details';editor.wantedPassportEditor=page=='passport_edit'
        for frame=1,5 do
            frameNow=frame;im.NewFrame();im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(18,18))
            im.SetNextWindowPos(im.ImVec2(rect.x,rect.y),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(rect.width,rect.height),im.Cond.Always)
            im.Begin('dedicated-native-'..page,nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove+im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse)
            detached.draw(editor,ui,data,cb);check(#stack==0,'Detached scope mismatch')
            if frame>=3 then check(im.GetScrollMaxY()<1,'Detached view needs scrolling: '..page..' at '..display[1]..'x'..display[2]..' max='..im.GetScrollMaxY())end
            im.End();im.PopStyleVar(1);im.Render();frames=frames+1
        end
    end
end
detachedNow=false
editor:release();im.DestroyContext(ctx)
local out=assert(io.open(tests..'WANTED_NATIVE32_RESULTS.json','wb'))
out:write(string.format('{"status":"passed","checks":%d,"frames":%d,"resolutions":4,"min_window_width":300,"modal_frames":%d,"gta_started":false,"game_files_written":false,"server_contacted":false,"renderer":"installed 32-bit ImGui, CPU only"}\n',checks,frames,modalCount));out:close()
print('Wanted native32: '..checks..' checks; '..frames..' frames; no GTA or sends.')
