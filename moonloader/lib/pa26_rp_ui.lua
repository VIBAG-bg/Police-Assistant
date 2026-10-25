local model=require 'pa26_bindings'
local rp=require 'pa26_rp_text'
local M={}
function M.preview(s,ui,data,line,label)
    if not data.codec then return end
    local prepared,err=rp.line(line,data.codec,s.lib.rp_text,data.localNickname)
    ui.text((label or 'Предпросмотр')..': '..(prepared and prepared.line or tostring(err)))
    if prepared and prepared.body_budget then ui.text(#prepared.lines==1 and 'Одна реплика, без автоматического разделения.'or('Частей: '..#prepared.lines..' · с маркерами продолжения и общим интервалом.'))end
    return prepared,err
end
function M.draw(s,ui,data,callbacks)
    local d=s.rpDraft or model.copy(s.lib.rp_text);s.currentNoticeScope='rp_text'
    s:settingsHeading(ui,'Перенос длинных сообщений')
    ui.text('По умолчанию в одной части не больше 90 символов, включая акцент, пробелы и ... . PA переносит последнее не помещающееся слово целиком. Первая часть заканчивается ..., следующая начинается с ... . Короткая реплика остаётся целой.')
    ui.text('Лимит относится к готовому тексту реплики. Команда канала и ник считаются отдельно; предел отправки клиента также проверяется. Изменить порог можно ниже.')
    ui.text('Запас под ник и скобки влияет только на размер частей длинного текста. Короткая реплика из-за него не разделяется. Для /do место под подпись пока задано приблизительно — уточните его по отображению в игре.')
    d.enabled=s:check('Переносить длинные /me и /do##rp-enabled',d.enabled)
    d.speech_enabled=s:check('Переносить обычную речь и текстовые каналы##speech-enabled',d.speech_enabled)
    for _,row in ipairs({{'','Обычная речь'},{'/s','Крик /s'},{'/m','Мегафон /m'},{'/r','Рация /r'},{'/rn','OOC-рация /rn'},
        {'/f','Связь организации /f'},{'/fn','OOC-связь организации /fn'},{'/d','Департамент /d'},{'/df','Связь /df'},{'/l','Руководство /l'},{'/ln','OOC-руководство /ln'},{'/bkn','Связь /bkn'},{'/n','OOC-чат /n'},{'/b','OOC-чат /b'}})do
        d.channels[row[1]]=s:check(row[2]..'##speech-channel-'..row[1],d.channels[row[1]])
    end
    for _,row in ipairs({{'display_limit','Размер части вместе с ником · 64–255'},
        {'body_limit','Разделять текст длиннее этого числа · 24–120'},
        {'margin','Запас до края строки · 0–32'},
        {'max_lines','Максимум частей одной реплики · 1–16'},
        {'todo_action_limit','Действие после * в /todo · максимум 1–60 символов'},
        {'fallback_nickname','Длина ника, если он ещё неизвестен · 1–64'},
        {'me_extra','Место для пробела рядом с ником в /me'},
        {'do_extra','Место для скобок и пробелов в /do'}})do
        local value=s.imgui.new.int(d[row[1]])
        if s.imgui.InputInt(row[2]..'##rp-'..row[1],value)then d[row[1]]=value[0]end
    end
    d.marker=s:field('Маркер продолжения##rp-marker','rp:marker',d.marker,64)
    ui.text('Обычный маркер продолжения — ... . PA отдельно проверяет предел отправки: 127 символов в кодировке игрового чата, включая команду. Эти настройки не увеличивают предел клиента.')
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
    ui.text('При обновлении PA ваши тексты сохраняются. Кнопка ниже предложит новые варианты только там, где остались прежние стандартные отыгровки. Перед заменой вы увидите весь текст. После замены каждую реплику можно изменить в настройках её функции.')
    if s:button('Обновить стандартные отыгровки##rp-presets',ui)then
        local ok,err=require('pa26_rp_presets').offer(s,callbacks)
        if not ok then s:notify(err,'rp_text',false)end
    end
    s:drawNotice(ui)
end
return M
