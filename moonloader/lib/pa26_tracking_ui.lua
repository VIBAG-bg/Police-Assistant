-- One ordinary /setmark action; the executor owns mandatory RP. Technical OOC
-- wanted-star handling remains a separately chosen, existing procedure.
local M={}
function M.draw(s,ui,data,cb)
 s:settingsHeading(ui,'Пеленгация подозреваемого')
 require('pa26_nearby').compact(s,ui,data,cb)
 local selected=data.target
 if selected then ui.text('Выбран: '..selected.name..' ['..selected.id..']')end
 s.trackId=s:field('ID подключённого игрока · любая дистанция##tracking-id','tracking:id',s.trackId or(selected and tostring(selected.id)or''),16)
 if s:button('Отыграть RP и выполнить /setmark##tracking-send',ui)then
  cb.procedureInput('setmark',s.trackId)
 end
 ui.text('PA подставит ваш обязательный RP-шаблон и выполнит /setmark ID. Подготовка едина для кнопок, колеса и биндов. Esc / End останавливают оставшиеся строки. Результат определяет сервер.')
 if s:button('Изменить обязательную RP пеленгации##tracking-rp-settings',ui)then
  s.manualActionHead='setmark';cb.openSettings('chat','commands')
 end
 if s:button('OOC-звёзды и проверка их снятия##tracking-ooc',ui)then
  cb.openTrackingOoc(s.trackId)
 end
 if s:button('Доклады о поиске##tracking-radio',ui)then
  s.dispatchIncident='dispatch_search';cb.openAssist('patrol')
 end
end
return M
