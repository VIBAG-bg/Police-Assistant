local model=require 'pa26_bindings'
local M={}
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;studio.currentNoticeScope='identity';studio.preferenceContext=true
    local view=data.identity or {};local r=view.record
    studio:settingsHeading(ui,'IC-сведения о человеке','PA распознаёт системное сообщение о показе паспорта, если документ показали именно вам. Имя и номер документа нужно заполнить отдельно. Наличие маски отмечается вручную.','identity-source')
    ui.text('Сведения хранятся в текущей игровой сцене. Показ другому человеку не засчитывается; при выходе игрока, смене сервера или жизни сведения удаляются.')
    if not r then
        ui.text('Сначала выберите человека. Его ник и ID появятся здесь; IC-данные нужно указать отдельно.')
    else
        ui.text('Выбран: '..r.target.name..' ['..r.target.id..'] · '..(r.passport_source=='server'and 'показ паспорта распознан'or 'ваши отметки'))
        local owner=view.key..':'..r.nonce..':'..r.display_revision
        if studio.identityOwner~=owner then
            for k in pairs(studio.cache)do if k:match('^identity%-form:')then studio.cache[k]=nil end end
            studio.identityOwner=owner
        end
        local patch={}
        local function choice(label,field)
            local value,changed=studio:choice(label..'##identity-'..field,r[field],{{'unknown','Не знаю'},{'yes','Да'},{'no','Нет'}},ui)
            if changed then patch[field]=value end
            return value
        end
        local function field(label,k,size,multiline)
            local value=studio:field(label..'##identity-'..k,'identity-form:'..k,r[k],size,multiline,multiline and 90 or nil)
            if value~=r[k]then patch[k]=value end
        end
        studio:settingsHeading(ui,'Паспорт')
        local seen=choice('Вы видели паспорт этого человека?', 'passport_seen')
        field('IC-имя и фамилия из паспорта','ic_name',512)
        field('Номер паспорта · если известен','passport_number',256)
        ui.text(seen=='yes'and(r.passport_source=='server'and 'Системный показ паспорта распознан. Введите имя и номер из самого документа; ник не подставляется вместо паспортных данных.'or 'Показ паспорта отмечен вами вручную.')or 'Показ паспорта пока не подтверждён.')
        studio:settingsHeading(ui,'Лицо и приметы')
        choice('На человеке маска?', 'mask')
        choice('Вы видели его лицо до маски?', 'face_before')
        field('Известные вашему персонажу приметы','appearance',2048,true)
        ui.text('Отметьте маску и узнавание самостоятельно. Серый ник или предмет на лице не позволяют надёжно определить маску. Эти отметки не устанавливают основание для розыска или применения силы.')
        studio:settingsHeading(ui,'Известный IC-телефон')
        choice('Номер известен вашему персонажу?', 'phone_known')
        field('Номер телефона · отдельно от SA:MP ID','phone_number',256)
        field('Откуда персонаж узнал номер','phone_source',1024)
        ui.text('Телефон можно записать только из известного вам источника. PA не читает скрытые номера и не подставляет его в /setmark, пока не проверен синтаксис команды.')
        if next(patch)then
            local ok,err=callbacks.identityUpdate(patch,view.key,r.nonce)
            if not ok then studio:notify(err,'identity',false)end
        end
        ui.text('Отметки сохраняются сразу. Заполнение карточки не отправляет отыгровки и команды.')
        if studio:button('Очистить сведения о человеке##identity-clear',ui)then
            local ok,err=callbacks.identityForget(view.key,r.nonce)
            if not ok then studio:notify(err,'identity',false)end
        end
    end
    studio:observeStatus('identity',view.message,'identity')
    if view.passportStatus then ui.text('Проверка показа паспорта: '..view.passportStatus)end
    im.Separator();studio:settingsHeading(ui,'Как долго помнить сведения')
    local cfg=studio.identityDraft or model.copy(studio.lib.identity)
    studio:settingsHeading(ui,'Системный показ паспорта')
    local enabled,edited=studio:check('Распознавать показ паспорта именно мне##identity-passport-chat',cfg.passport_chat)
    if edited then cfg.passport_chat=enabled end
    for _,row in ipairs({{'passport_flexible','Учитывать время, метку ME и ID рядом с никами'},{'passport_diagnostics','Показывать пояснения распознавания паспорта'}})do
        local value,changed=studio:check(row[2]..'##identity-'..row[1],cfg[row[1]])
        if changed then cfg[row[1]]=value end
    end
    cfg.passport_server=studio:field('Адрес сервера · пусто для всех##identity-passport-server','identity:passport-server',cfg.passport_server,256)
    cfg.passport_phrase=studio:field('Фраза между никами##identity-passport-phrase','identity:passport-phrase',cfg.passport_phrase,1024,true,64)
    ui.text('Образец: Player_Name '..cfg.passport_phrase..' Ваш_Ник. Сама фраза должна совпадать. Время, метка ME, ID у ников и точка в конце могут добавляться оформлением чата. Адрес можно оставить пустым; прежнее стандартное ограничение одним IP снято. Имя и номер паспорта указывайте по документу; маска определяется вами.')
    local distance=im.new.int(cfg.passport_distance)
    if im.InputInt('Проверка показавшего игрока рядом, м##identity-passport-distance',distance)then cfg.passport_distance=distance[0]end
    for _,row in ipairs({{'enabled','Включить IC-сведения'},{'retain_after_switch','Помнить сведения при выборе другого человека'}})do
        local value,edit=studio:check(row[2]..'##identity-setting-'..row[1],cfg[row[1]]);if edit then cfg[row[1]]=value end
    end
    local seconds=im.new.int(cfg.expiry_ms/1000)
    if im.InputInt('Срок каждой группы сведений, с##identity-expiry',seconds)then cfg.expiry_ms=seconds[0]*1000 end
    ui.text('0 — хранить до смены игровой ситуации; от 1 до 86400 — забывать через указанное число секунд. Паспорт, узнавание, приметы и телефон хранятся независимо. Обновление телефона не продлевает срок паспорта. При выходе игрока, смерти, смене сервера или режима старые сведения удаляются.')
    studio.identityDraft=cfg;studio:autoSettings('identity',{'identity'},cfg,'identityDraft');studio:autosaveHint(ui,'identity');studio:drawNotice(ui)
end
return M
