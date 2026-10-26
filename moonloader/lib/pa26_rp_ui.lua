local model=require 'pa26_bindings'
local rp=require 'pa26_rp_text'
local M={}
function M.preview(s,ui,data,line,label)
    if not data.codec then return end
    line=require('pa26_core').expandGender(line,s.lib.profile.gender)
    local prepared,err=rp.line(line,data.codec,s.lib.rp_text,data.localNickname)
    ui.text((label or 'Предпросмотр')..': '..(prepared and prepared.line or tostring(err)))
    if prepared and prepared.body_budget then ui.text(#prepared.lines==1 and 'Одна реплика, без автоматического разделения.'or('Частей: '..#prepared.lines..' · с маркерами продолжения и общим интервалом.'))end
    return prepared,err
end
function M.draw(s,ui,data,callbacks)
    local d=s.rpDraft or model.copy(s.lib.rp_text);s.currentNoticeScope='rp_text'
    s:settingsHeading(ui,'Перенос длинных сообщений')
    ui.text('Если реплика в бинде, обычном чате или рации длиннее порога (по умолчанию 90 символов), PA продолжит её по целым словам с «...» на стыках. Настройки переноса ниже должны быть включены.')
    ui.text('В /todo речь*действие переносится речь. Действие после * (до 60 символов) повторяется в каждой части.')
    ui.text('До первой отправки проверяются все части и предел клиента: 127 байт CP1251 вместе с командой. Если безопасный перенос невозможен, ручной ввод сохраняется, а бинд не начинает отправку.')
    d.enabled=s:check('Переносить длинные /me и /do##rp-enabled',d.enabled)
    d.speech_enabled=s:check('Переносить обычную речь и текстовые каналы##speech-enabled',d.speech_enabled)
    local count=0;for _,enabled in pairs(d.channels)do if enabled then count=count+1 end end
    if s:button((s.showRpChannels and'Скрыть список каналов'or('Настроить каналы для переноса (включено '..count..' из 14)'))..'##rp-toggle-channels',ui)then s.showRpChannels=not s.showRpChannels end
    if s.showRpChannels then
    for _,row in ipairs({{'','Обычная речь'},{'/s','Крик /s'},{'/m','Мегафон /m'},{'/r','Рация /r'},{'/rn','OOC-рация /rn'},
        {'/f','Связь организации /f'},{'/fn','OOC-связь организации /fn'},{'/d','Департамент /d'},{'/df','Связь /df'},{'/l','Руководство /l'},{'/ln','OOC-руководство /ln'},{'/bkn','Связь /bkn'},{'/n','OOC-чат /n'},{'/b','OOC-чат /b'}})do
        d.channels[row[1]]=s:check(row[2]..'##speech-channel-'..row[1],d.channels[row[1]])
    end
    end
    for _,row in ipairs({{'body_limit','Порог разделения длинной фразы, символов (24–120)'},{'todo_action_limit','Максимум символов для действия после * в /todo (1–60)'}})do
        local value=s.imgui.new.int(d[row[1]])
        if s.imgui.InputInt(row[2]..'##rp-'..row[1],value)then d[row[1]]=value[0]end
    end
    d.marker=s:field('Маркер продолжения (обычно ...)##rp-marker','rp:marker',d.marker,64)
    if s:button((s.showRpAdvanced and'Скрыть тонкую калибровку запаса под ник'or'Тонкая калибровка запаса под длину ника и /do')..'##rp-toggle-adv',ui)then s.showRpAdvanced=not s.showRpAdvanced end
    if s.showRpAdvanced then
        ui.text('Эти значения учитывают отображаемый ник и подпись /do. Они не увеличивают сетевой предел клиента. Проверьте отображение в своей сборке.')
        for _,row in ipairs({{'display_limit','Размер части вместе с ником · 64–255'},{'margin','Запас до края строки · 0–32'},
            {'max_lines','Максимум частей RP-шаблона · 1–16'},{'fallback_nickname','Длина неизвестного ника · 1–64'},
            {'me_extra','Место рядом с ником в /me'},{'do_extra','Место для скобок и пробелов в /do'}})do
            local value=s.imgui.new.int(d[row[1]])
            if s.imgui.InputInt(row[2]..'##rp-'..row[1],value)then d[row[1]]=value[0]end
        end
        ui.text('В живом чате отдельно действует максимум 1–3 части из настроек ручного переноса.')
    end
    ui.text('Ник берётся из текущей игры: '..(data.localNickname or('ещё неизвестен; резерв '..d.fallback_nickname..' символов')))
    d.preview_text=s:field('Текст для проверки · в игру не отправляется##rp-example','rp:example',d.preview_text,4097,true,100)
    s:settingsHeading(ui,'Все части реплики')
    for _,channel in ipairs({'/me','/do','/try','','/s','/m','/r','/rn','/f','/fn','/d','/df'})do
        local roleplay=channel=='/me'or channel=='/do'
        local body=roleplay and d.preview_text or model.applyAccent(d.preview_text,s.lib.profile.accent)
        local p,err=rp.prepare(channel,body,data.codec,d,data.localNickname)
        local name=channel==''and'Обычная речь'or channel
        if p then ui.text(name..' · частей '..#p.lines..' · порог переноса '..p.split_threshold..' · для длинных частей предел '..p.body_budget);for _,line in ipairs(p.lines)do ui.text(line)end
        else ui.text(name..': '..tostring(err))end
    end
    ui.text('Перенос работает в биндах и ручном чате, включая рацию. В /todo разделяется только речь; действие после * повторяется целиком и не может превышать 60 символов. Если одно слово не помещается или частей слишком много, PA покажет ошибку до начала отправки.')
    s.rpDraft=d;s:autoSettings('rp_text',{'rp_text'},d,'rpDraft');s:autosaveHint(ui,'rp_text')
    s:settingsHeading(ui,'Готовые отыгровки')
    ui.text('Стандартные /me написаны со строчной буквы и заканчиваются точкой. Описания /do начинаются с заглавной и заканчиваются точкой, вопросы — знаком ?. Продолжения длинных реплик сохраняют ... на стыках.')
    ui.text('При обновлении PA ваши тексты сохраняются. Кнопка ниже предложит новые варианты только для отыгровок функций вне библиотеки биндов, где остался старый стандартный текст. Бинды не изменяются. Перед заменой вы увидите весь текст. После замены каждую реплику можно изменить в настройках её функции.')
    if s:button('Обновить стандартные отыгровки##rp-presets',ui)then
        local ok,err=require('pa26_rp_presets').offer(s,callbacks)
        if not ok then s:notify(err,'rp_text',false)end
    end
    s:drawNotice(ui)
end
return M
