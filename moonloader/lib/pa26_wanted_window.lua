-- Dedicated PA window: same procedure state machine, bounded pages, no scrolling.
local prefs=require 'pa26_procedure_settings'
local catalog=require 'pa26_wanted_catalog'
local wanted=require 'pa26_wanted_ui'
local M={}
local function notify(s,why)s:notify(why or 'Проверьте сведения.','procedures',false)end
local function question(s,f,ui,label,key)
    f[key]=s:choice(label..'##wanted-'..key,f[key],{{'unknown','Не знаю'},{'yes','Да'},{'no','Нет'}},ui)
end
local function nextIdentity(s,f,cb)
    local ok,why=cb.caseNext(f);if not ok then notify(s,why)end
end
function M.draw(s,ui,data,cb)
    local im=s.imgui;local f=s.caseForm;local cfg=s.lib.procedures
    s.currentUi=ui;s.currentNoticeScope='procedures';s.preferenceContext=false
    if not f then
        ui.text('Введите /su ID подключённого игрока либо откройте розыск для выбранного человека.')
        if s:button('Новая форма##case-new',ui)then local value,why=cb.caseBegin('wanted');if value then s.caseForm=value else notify(s,why)end end
        return
    end
    if cb.caseValid and not cb.caseValid(f)then
        s.wantedAppearance=nil;ui.text('Форма устарела: игрок отключился или игровая сцена изменилась. Повторите /su ID.');return
    end
    ui.text(f.target and('Подозреваемый: '..f.target.name..' [ID: '..f.target.id..']')or'Общий список преступников')
    local narrow=im.GetWindowSize().y<650
    if f.stage~='identity'then s.wantedIdentityPage=nil;s.wantedPassportEditor=nil end
    if f.stage=='identity'then
        if s.wantedIdentityPage=='phone'then
            ui.text('Телефон для RP-пеленгации /setmark')
            question(s,f,ui,'Номер телефона известен вашему персонажу по RP?','phone_known')
            f.phone_number=s:field('IC-номер телефона##wanted-phone_number','wanted-form:'..f.id..':phone_number',f.phone_number,512)
            f.phone_source=s:field('Откуда известен номер по RP##wanted-phone_source','wanted-form:'..f.id..':phone_source',f.phone_source,512)
            ui.text('Ник, ID и приметы не заменяют известный IC-телефон.')
            if s:button('Готово · к условиям##wanted-phone-edit-back',ui)then s.wantedIdentityPage=narrow and 'details'or nil end
            return
        end
        if s.wantedPassportEditor then
            ui.text('Уточнение подтверждённых паспортных данных')
            f.ic_name=s:field('Имя и фамилия##wanted-ic_name','wanted-form:'..f.id..':ic_name',f.ic_name,512)
            f.passport_number=s:field('Номер паспорта##wanted-passport_number','wanted-form:'..f.id..':passport_number',f.passport_number,512)
            if s:button('Готово · к сведениям##wanted-passport-edit-back',ui)then s.wantedPassportEditor=nil end
            return
        end
        local details=narrow and s.wantedIdentityPage=='details'
        if not details then
            if cfg.wanted_require_life_ack then f.life_ack=s:check('Основание получено в текущей игровой жизни · не использую сведения до смерти / RK##wanted-life-ack',f.life_ack)end
            if cfg.allow_ooc then f.mode=s:choice('Ветка розыска##wanted-mode',f.mode,{{'ic','IC · по паспорту или приметам'},{'ooc','OOC · только для пеленгации /setmark'}},ui)end
            if f.mode=='ic'then
                question(s,f,ui,'На подозреваемом полная RP-маска (/mask + аксессуар на лице)?','mask')
                question(s,f,ui,'Вы видели паспорт этого человека?','passport_seen')
                if cb.caseFillWanted then cb.caseFillWanted(f)end
            end
        end
        if not narrow or details then
            if f.mode=='ooc'then
                f.ooc_reason=s:choice('Для какой механики нужны звёзды##wanted-ooc-purpose',f.ooc_reason,prefs.oocReasons,ui)
                ui.text(prefs.oocNotes[f.ooc_reason]or '')
                ui.text(f.phone_known=='yes'and f.phone_number~=''and ('IC-телефон: '..f.phone_number)or 'IC-телефон пока не указан.')
                if s:button('Телефон для RP-пеленгации##wanted-phone-edit',ui)then s.wantedIdentityPage='phone'end
                f.ooc_ack=s:check('Телефон включён; RP-пеленгация; звёзды сниму сразу##wanted-ooc-ack',f.ooc_ack)
            else
                if f.mask=='yes'then question(s,f,ui,'Вы установили личность по лицу или паспорту ДО маски и НЕ теряли человека из виду?','face_before')end
                if f.passport_seen=='yes'then
                    ui.text('Паспорт подтверждён: '..f.ic_name..' · № '..f.passport_number)
                    if s:button('Уточнить имя или номер##wanted-passport-edit',ui)then s.wantedPassportEditor=true end
                end
            end
            if f.mode=='ic'and cb.caseSuggestOoc and cb.caseSuggestOoc(f)then
                ui.text('IC-личность не установлена. OOC доступен только для RP-пеленгации /setmark.')
                if s:button('Перейти к OOC-звёздам##wanted-use-ooc',ui)then local ok,why=cb.caseChooseOoc(f);if not ok then notify(s,why)end end
            end
        end
        if narrow and not details and f.mode=='ic'and f.passport_seen=='yes'then
            ui.text('Паспорт: '..f.ic_name..' · № '..f.passport_number)
            if s:button('Уточнить имя или номер##wanted-passport-edit',ui)then s.wantedPassportEditor=true end
        end
        if narrow and not details and(f.mode=='ooc'or f.mask=='yes')then
            if s:button('Далее · уточнение сведений##wanted-identity-details',ui)then s.wantedIdentityPage='details'end
        else
            local _,why=cb.caseBranch(f);if why and not narrow then ui.text(why)end
            if s:button('Далее · причина розыска##wanted-next',ui)then nextIdentity(s,f,cb)end
            if details and s:button('Назад · вопросы##wanted-identity-back',ui)then s.wantedIdentityPage=nil end
        end
    elseif f.stage=='appearance_choice'or f.stage=='appearance_input'then
        s.wantedAppearance={form=f,stage=f.stage};ui.text('Выберите общую отыгровку либо введите приметы в отдельном окне.')
    elseif f.stage=='basis'then
        if s.wantedBasisDetails then
            local row=catalog.byId[f.reason_id]
            if row then ui.text(row.id..' · '..row.title..' · '..row.stars..' ур.');ui.text(row.mapping_status..'. '..row.note)
                ui.text('Нормы: '..table.concat(row.refs,', '))
                if cb.openWantedKnowledge and s:button('Открыть карточку в базе##wanted-knowledge',ui)then cb.openWantedKnowledge(row.knowledge_key)end
            end
            f.facts=s:field('Факты ситуации##wanted-facts','wanted-form:'..f.id..':facts',f.facts or'',2048,true,64)
            if s:button('Назад · выбор причины##wanted-basis-details-back',ui)then s.wantedBasisDetails=nil end
        else
            wanted.reasonPicker(s,ui,f,cb,{compact=true,perPage=narrow and 2 or 4})
            if s:button('Подробности основания и факты##wanted-basis-details',ui)then s.wantedBasisDetails=true end
            if s:button('Проверить отыгровку и команду##wanted-preview',ui)then local ok,why=cb.caseNext(f);s.wantedPreviewPage=1;if not ok then notify(s,why)end end
            if s:button('Назад · сведения##wanted-back-identity',ui)then f.stage='identity'end
        end
    else
        local p,why=cb.casePreview(f);if not p then ui.text(why);return end
        local pageSize=narrow and 1 or 3;local pages=math.max(1,math.ceil(#p.lines/pageSize))
        local page=math.max(1,math.min(pages,s.wantedPreviewPage or 1));s.wantedPreviewPage=page
        if p.gameReason then ui.text(p.gameReason.id..' · '..p.gameReason.title..' · '..p.gameReason.stars..' ур.')end
        for n=(page-1)*pageSize+1,math.min(#p.lines,page*pageSize)do ui.text(n..'. '..p.lines[n])end
        if pages>1 then
            ui.text('Предпросмотр · '..page..' / '..pages)
            local width=math.max(1,(im.GetContentRegionAvail().x-10)/2)
            if s:button('Предыдущая##wanted-preview-page-back',ui,width)then s.wantedPreviewPage=math.max(1,page-1)end
            im.SameLine(0,10)
            if s:button('Следующая##wanted-preview-page-next',ui,width)then s.wantedPreviewPage=math.min(pages,page+1)end
        end
        ui.text('Сначала только RP. После отыгровки — отдельное ДА/НЕТ перед командой.')
        if s:button('Отыграть ориентировку в чат (затем ДА/НЕТ на выдачу)##wanted-prepare',ui)then
            local offer,err=cb.caseOffer(f)
            if offer then local ok;ok,err=cb.caseAccept(offer);if not ok then notify(s,err)end else notify(s,err)end
        end
        if f.kind=='wanted'and s:button('Назад · выбор причины##wanted-back-basis',ui)then f.stage='basis'end
    end
end
return M
