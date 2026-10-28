local model=require 'pa26_bindings'
local grid=require 'pa26_map_grid'
local M={}
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;studio.currentNoticeScope='map_grid';studio.preferenceContext=true;studio.currentUi=ui
    local d=studio.mapGridDraft or model.copy(studio.lib.map_grid)
    local state=data.mapState or {}
    local preview=grid.validate(d)or studio.lib.map_grid
    studio:settingsHeading(ui,'Квадраты карты')
    ui.text('Буква и номер обозначают клетку координатной сетки, например H-18. По умолчанию 24 × 24 клетки с шагом 250 игровых единиц. Это отдельная сетка PA, а не подтверждённая карта официальных секторов SFPS.')
    ui.text('Названия районов Doherty, Hashbury и другие уже берутся из GTA и показываются отдельно. Поддерживаются обычный чат и CEF: сетка сама ничего не отправляет.')
    local autoCity,cityChanged=studio:check('Автозаполнение {city}##map-auto-city',d.auto_city)
    if cityChanged then d.auto_city=autoCity end
    local city=grid.values(d,studio.lib.profile,state and state.x,state and state.y,state and state.interior,state and state.z,state and state.zoneKey).city
    ui.text('Предпросмотр {city}: '..(city and city~=''and city or'нет данных')..'. Определяются три города и пять округов. Ручной город в профиле сохраняется: выключите автозаполнение, чтобы использовать его. В интерьере берётся последнее известное место снаружи, если оно есть.')
    for _,r in ipairs({{'enabled','Включить квадраты карты'},{'radar','Сетка на радаре'},{'pause_map','Сетка на карте в паузе'},
        {'hud','Квадрат в HUD'},{'labels','Подписи клеток'},{'axis_labels','Индексы у краёв карты'},{'highlight','Выделять мою клетку'}})do
        local v,edit=studio:check(r[2]..'##map-'..r[1],d[r[1]]);if edit then d[r[1]]=v end
    end
    local live=grid.cell(preview,state.x,state.y,state.interior)
    ui.text('Текущий квадрат: '..(live and live.label or (state.interior and state.interior>0 and'в интерьере не определяется'or'нет доступных координат в границах сетки')))
    ui.text(data.mapAdapterStatus or'Проекция карты пока не проверена. Расчёт клетки работает отдельно от графического адаптера.')
    if type(callbacks.recheckMap)=='function'and studio:button('Проверить совместимость проекции снова##map-recheck',ui)then callbacks.recheckMap()end
    ui.text('На неподдерживаемом или изменённом клиенте линии карты отключаются; расчёт квадрата, бинды и остальные функции PA продолжают работать. Карты в отдельных CEF-страницах не изменяются.')
    im.Separator();studio:settingsHeading(ui,'Квадрат в биндах и докладах')
    ui.text('{map_square} — клетка этой сетки. {location} — район вместе с доступным квадратом. В биндах {area} остаётся только районом; {square} по умолчанию берётся из профиля.')
    local reports,reportsChanged=studio:check('Квадрат рядом с районом в докладах##map-report-area',d.report_area)
    if reportsChanged then d.report_area=reports end
    ui.text('Применяется к Shots fired, SOS, CODE 0/1/4, докладам патруля, остановки и погони, событиям и своим автодокладам с {area}. Личный текст шаблона сохраняется. Если в нём уже есть {map_square}, {square} или {location}, повторный квадрат не добавляется. Без {area} место автоматически не дописывается.')
    d.location_template=studio:field('Формат места##map-location-template','map-location-template',d.location_template,1024,true,76)
    ui.text('Используйте {area} и {map_square} по одному разу. Например: {area}, квадрат {map_square}. В интерьере и вне сетки остаётся только район: отсутствие квадрата не мешает передать SOS. Выключенный переключатель возвращает прежнее значение {area} в докладах; явная {location} по-прежнему использует этот формат.')
    local locationValues={area=state.area or(data.radioState and data.radioState.area),map_square=live and live.label,map_grid=preview}
    ui.text('Место в предпросмотре: '..(grid.location(locationValues)or'нет доступного района')..'.')
    ui.text('Изменения здесь сами ничего не отправляют. Предпросмотр конкретного доклада доступен в его разделе; перед отправкой сохраняются подтверждение и обычная очередь PA.')
    local auto,changed=studio:check('Автозаполнение {square}##map-auto-square',d.auto_square)
    if changed then d.auto_square=auto end
    ui.text('Эта настройка влияет на бинды и доклады с {square}. Ручной сектор не стирается: выключите переключатель, чтобы вернуть его. Сектор активного патруля {sector} остаётся отдельным полем.')
    local current=grid.values(preview,studio.lib.profile,state.x,state.y,state.interior)
    ui.text('Предпросмотр: {map_square} = '..(current.map_square or'недоступен')..'; {square} = '..(current.square and current.square~=''and current.square or'не заполнен')..'.')
    ui.text('Универсальный бинд: /r {local_tag}Патруль: {location}. В интерьере он передаст только район. Если нужен обязательный квадрат, используйте {map_square}: без него PA остановит такой бинд и попросит проверить данные. Мегафон и локальные /me /do автоматически местом не дополняются.')
    im.Separator();studio:settingsHeading(ui,'Геометрия и подписи')
    ui.text('Меняйте эти поля, только если ваша команда договорилась о другой сетке. Название клетки одинаково рассчитывается для карты, HUD и переменных; на внутренней границе выбирается клетка справа или снизу.')
    for _,r in ipairs({{'west','Западная граница X',-10000,10000},{'north','Северная граница Y',-10000,10000},
        {'cell_size','Размер клетки в единицах GTA',50,2000},{'columns','Количество столбцов',1,48},{'column_start','Первый номер столбца',0,99}})do
        ui.text(r[2]);im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local n=im.new.int(d[r[1]]);if im.InputInt('##map-'..r[1],n)then d[r[1]]=math.max(r[3],math.min(r[4],n[0]))end
        ui.finish()
    end
    d.row_labels=studio:field('Буквы строк с севера на юг##map-rows','map-rows',d.row_labels,64)
    ui.text('От 1 до 26 разных заглавных латинских букв; число букв задаёт число строк.')
    d.separator=studio:choice('Разделитель##map-separator',d.separator,{{'-','H-18'},{'','H18'}},ui)
    local west,south,east,north=grid.bounds(d)
    ui.text('Границы предпросмотра: X '..west..' … '..east..'; Y '..south..' … '..north..'.')
    im.Separator();studio:settingsHeading(ui,'Оформление сетки')
    d.theme=studio:choice('Цвет##map-theme',d.theme,{{'white','Белый'},{'blue','Голубой'},{'gold','Золотистый'}},ui)
    for _,r in ipairs({{'font_size','Размер подписей',9,24},{'line_width','Толщина линий',1,3},{'min_label_px','Минимальный размер клетки для подписей, пикс.',25,150}})do
        ui.text(r[2]);im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local n=im.new.int(d[r[1]]);if im.SliderInt('##map-'..r[1],n,r[3],r[4])then d[r[1]]=n[0]end
        ui.finish()
    end
    for _,r in ipairs({{'line_alpha','Непрозрачность линий'},{'label_alpha','Непрозрачность подписей'}})do
        ui.text(r[2]);im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local n=im.new.float(d[r[1]]);if im.SliderFloat('##map-'..r[1],n,.05,1)then d[r[1]]=n[0]end
        ui.finish()
    end
    local valid,err=grid.validate(d)
    studio.mapGridDraft=d
    if not valid then ui.text('Не сохранено: '..err..' Исправьте поле; последняя сохранённая сетка продолжает работать.')
    else studio:autoSettings('map_grid',{'map_grid'},d,'mapGridDraft');studio:autosaveHint(ui,'map_grid')end
    studio:drawNotice(ui);studio.preferenceContext=nil
end
return M
