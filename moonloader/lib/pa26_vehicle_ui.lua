local model=require 'pa26_bindings'
local settings=require 'pa26_vehicle_settings'
local vehicle=require 'pa26_vehicle'
local M={}
function M.offer(studio,callbacks,kind,nearest)
    local p,err=callbacks.vehicleOffer(kind,nearest)
    if p then studio.vehicleConfirm=p else studio:notify(err,'vehicle',false)end
end
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;studio.currentNoticeScope='vehicle';studio.preferenceContext=true
    local d=studio.vehicleDraft or model.copy(studio.lib.vehicle);local view=data.vehicle or {}
    studio:settingsHeading(ui,'Трафик-стоп и преследование')
    if studio:button('Открыть реплики мегафона##vehicle-megaphone',ui)then callbacks.openAssist('megaphone')end
    if data.radioState then ui.text('Место: '..(require('pa26_map_grid').location(data.radioState)or 'не определено'))end
    ui.text('Выбор машины не меняет выбранного человека. Перед докладом, отыгровкой или обращением в мегафон PA покажет текст и попросит подтверждение.')
    if view.selected then
        local values=vehicle.describe(view.selected,d,studio.lib.profile.gender)
        ui.text(values and values.vehicle_description or 'Описание не заполнено')
        ui.text('SA:MP ID '..view.selected.id..' · модель '..view.selected.model_id..' · '..math.floor(view.selected.distance)..' м · '..(view.phase or 'Выбрана'))
        ui.text('Цвета GTA: '..tostring(view.selected.color1)..' / '..tostring(view.selected.color2)..' · названия можно изменить ниже по ID.')
    elseif view.nearest then
        local values=vehicle.describe(view.nearest,d,studio.lib.profile.gender)
        ui.text('Ближайшая видимая: '..(values and values.vehicle_description or tostring(view.nearest.model_id)))
    else ui.text('Подходящая машина не найдена. Ваша машина исключена из выбора.')end
    if studio:button('Выбрать ближайшую и начать 10-55##vehicle-select',ui)then M.offer(studio,callbacks,'traffic_stop',true)end
    if #(view.candidates or {})>1 then
        ui.text('Или выберите нужную машину из ближайших на экране:')
        for _,car in ipairs(view.candidates)do
            local values=vehicle.describe(car,d,studio.lib.profile.gender)
            if studio:button((values and values.vehicle_description or tostring(car.model_id))..' · '..math.floor(car.distance)..' м ['..car.id..']##vehicle-candidate-'..car.id,ui)then
                local ok,err=callbacks.vehicleSelect(car.id);if not ok then studio:notify(err,'vehicle',false)end
            end
        end
    end
    if view.selected then
        for _,row in ipairs(settings.actions)do
            if studio:button(row[2]..'##vehicle-action-'..row[1],ui)then M.offer(studio,callbacks,row[1],false)end
        end
        if studio:button('Снять выбор машины##vehicle-clear',ui)then callbacks.vehicleClear()end
    end
    studio:observeStatus('vehicle',view.message,'vehicle')
    if studio:button('Мои требования в мегафон##vehicle-own-megaphone',ui)then callbacks.openAssist('megaphone')end
    ui.text('Направление вашего экипажа: '..(view.direction or 'не определено'))
    if view.selection_status then ui.text(view.selection_status)end
    im.Separator();studio:settingsHeading(ui,'Настройки транспорта')
    for _,row in ipairs({{'enabled','Трафик-стоп и погоня'},{'require_patrol','Только в активном патруле'},
        {'front_only','Экран и прямая видимость'},{'occupied_only','Только с водителем'},{'direction_enabled','Направление движения'}})do
        local v,edit=studio:check(row[2]..'##vehicle-'..row[1],d[row[1]]);if edit then d[row[1]]=v end
    end
    d.selection_mode=studio:choice('Направление выбора##vehicle-selection-mode',d.selection_mode,{{'auto','Авто: машина, пешком — камера'},{'vehicle','Куда направлена моя машина'},{'camera','Куда смотрит камера'},{'screen','Только видимость на экране'}},ui)
    d.selection_ranking=studio:choice('В начале списка##vehicle-selection-ranking',d.selection_ranking,{{'direction','Ближе к выбранному направлению'},{'distance','Ближе ко мне'}},ui)
    for _,r in ipairs({{'cone_angle','Отклонение в каждую сторону, градусы',10,120},{'height_tolerance','Перепад высоты, м · 0 без ограничения',0,30}})do
        ui.text(r[2]);im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local value=im.new.int(d[r[1]]);if im.SliderInt('##vehicle-'..r[1],value,r[3],r[4])then d[r[1]]=value[0]end;ui.finish()
    end
    ui.text('Автоматически выбирается направление собственной машины; пешком — направление камеры. Разворот камеры назад из машины не меняет конус. При заднем ходе конус всё равно смотрит перед капотом. Если направление недоступно, режим «Авто» оставляет видимость на экране и показывает причину; строгие режимы просят сменить режим. Фильтр высоты помогает исключить транспорт на эстакаде. Уже выбранная машина не заменяется другой автоматически.')
    for _,row in ipairs({{'radius','Дальность выбора, м'},{'retain_distance','Дальность удержания, м'},{'approach_distance','Подойти к машине пешком, м'},
        {'scan_ms','Обновление машин, мс'},{'motion_ms','Замер движения, мс'},
        {'max_motion_distance','Порог скачка координат, м'},{'confirmation_ms','Срок подтверждения, мс'}})do
        ui.text(row[2]);im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local n=im.new.int(d[row[1]]);if im.InputInt('##vehicle-'..row[1],n)then d[row[1]]=n[0]end;ui.finish()
    end
    ui.text('Порог движения за замер, м');im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
    local threshold=im.new.float(d.stationary_distance)
    if im.SliderFloat('##vehicle-motion-threshold',threshold,.05,5)then d.stationary_distance=threshold[0]end;ui.finish()
    d.manual_direction=studio:field('Направление вручную · если авто отключено##vehicle-manual-direction','vehicle:manual-direction',d.manual_direction,512)
    ui.text('PA определяет направление по движению машины, в том числе задним ходом. Поворот камеры ничего не меняет. Для остановившейся машины используется отдельный текст. Если выключить автоопределение, укажите направление вручную или уберите {direction} из доклада.')
    for i,label in ipairs({'Север','Северо-восток','Восток','Юго-восток','Юг','Юго-запад','Запад','Северо-запад'})do
        d.directions[i]=studio:field(label..'##vehicle-direction-'..i,'vehicle:direction:'..i,d.directions[i],256)
    end
    for _,row in ipairs({{'stationary','При остановке'},{'unknown_model','Если модель не определена'},{'unknown_color','Если цвет не определён'},{'color_separator','Разделитель двух цветов'}})do
        d[row[1]]=studio:field(row[2]..'##vehicle-label-'..row[1],'vehicle:label:'..row[1],d[row[1]],512)
    end
    local v,edit=studio:choice('Канал докладов##vehicle-channel',d.channel,require('pa26_server_commands').radioChoices,ui)
    if edit then d.channel=v end
    v,edit=studio:choice('Канал мегафона##vehicle-megaphone-channel',d.megaphone_channel,{{'/m','/m · мегафон'},{'/s','/s · крик'}},ui)
    if edit then d.megaphone_channel=v end
    studio:settingsHeading(ui,'Периодические доклады при остановке и погоне')
    for _,row in ipairs({{'pause_patrol_reports','Пауза патрульных при 10-55'},
        {'pursuit_periodic','Отдельный доклад о погоне'},{'pursuit_confirmation','Подтверждать доклад о погоне'}})do
        local value,edited=studio:check(row[2]..'##vehicle-periodic-'..row[1],d[row[1]]);if edited then d[row[1]]=value end
    end
    ui.text('Интервал докладов о погоне, с');im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
    local period=im.new.int(d.pursuit_interval_ms/1000)
    if im.InputInt('##vehicle-pursuit-interval',period)then d.pursuit_interval_ms=period[0]*1000 end;ui.finish()
    d.pursuit_periodic_template=studio:field('Автодоклад о погоне##vehicle-pursuit-periodic','vehicle:pursuit-periodic',d.pursuit_periodic_template,2048,true,78)
    local periodic,periodicError=callbacks.vehiclePreview('pursuit_periodic',d)
    ui.text(periodic and('Предпросмотр: '..periodic)or('Для предпросмотра: '..tostring(periodicError)))
    ui.text('Перед автодокладом появится предупреждение; до отправки его можно отменить. Доклады используют общую очередь. Если рацию ведёт напарник, PA не отправляет их автоматически.')
    studio:settingsHeading(ui,'Тексты и предпросмотр')
    ui.text('Грамматический род: {gender:передал|передала}. Без /команды. Переменные: {model}, {model_id}, {vehicle_id}, {vehicle_color}, {color_one}, {color_two}, {vehicle_description}, {direction}; также {unit}, {station}, {crew}, {area}, {location}, {map_square}, {sector}, {callsign} и поля профиля.')
    for _,row in ipairs(settings.actions)do
        local key=row[1]..'_template'
        d[key]=studio:field(row[2]..'##vehicle-template-'..key,'vehicle:template:'..key,d[key],2048,true,78)
        local text,err=callbacks.vehiclePreview(row[1],d)
        ui.text(text and('Предпросмотр: '..text)or('Для предпросмотра: '..tostring(err)))
    end
    d.description_template=studio:field('Описание машины##vehicle-description','vehicle:description',d.description_template,1024,true,62)
    ui.text('Для описания доступны {model}, {model_id}, {vehicle_id}, {vehicle_color}, {color_one}, {color_two}. Если цвет не удалось определить, PA не подставляет случайное название.')
    studio:settingsHeading(ui,'Названия моделей и цветов')
    for _,sp in ipairs({{'model_aliases','Модель GTA',400,611,'model_id'},{'color_aliases','Цвет GTA',0,255,'color1'}})do
        local id=studio[sp[1]..'Edit']or(view.selected and view.selected[sp[5]])or sp[3]
        ui.text(sp[2]..' · ID');im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local n=im.new.int(id);if im.InputInt('##vehicle-alias-'..sp[1],n)then id=n[0]end;ui.finish()
        studio[sp[1]..'Edit']=id
        if id>=sp[3]and id<=sp[4]then
            local key=tostring(id)
            local value=studio:field('Своё название##vehicle-alias-name-'..sp[1],'vehicle:alias:'..sp[1]..':'..key,d[sp[1]][key]or '',512)
            d[sp[1]][key]=value~=''and value or nil
            ui.text('Пустое поле возвращает стандартное название модели / палитры. Свои названия сохраняются по ID.')
        end
    end
    studio:settingsHeading(ui,'Горячие клавиши')
    for _,row in ipairs(settings.keys)do
        ui.text(row[2]..': '..model.shortcutName(d[row[1]]))
        if studio:button('Назначить##vehicle-key-'..row[1],ui)then callbacks.capture({kind='feature',group='vehicle',field=row[1]})end
        if d[row[1]].key~=0 and studio:button('Убрать##vehicle-key-clear-'..row[1],ui)then d[row[1]]={key=0,ctrl=false,alt=false,shift=false}end
    end
    ui.text('Клавиша мегафона открывает выбор реплик. Остальные действия сначала показывают подтверждение: Y — ДА, N — НЕТ. Во время ввода в чат сочетания не срабатывают. Машину выбираете вы; цель погони не меняется автоматически.')
    studio.vehicleDraft=d;studio:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');studio:autosaveHint(ui,'vehicle');studio:drawNotice(ui)
end
return M
