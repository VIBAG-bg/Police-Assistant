local prefs=require 'pa26_custody_settings';local M={}
function M.draw(s,ui,cfg,data,callbacks)
 local d=cfg.command_reports or prefs.defaults();cfg.command_reports=d
 s:settingsHeading(ui,'Доклады после /cuff и /arrest')
 ui.text('После реальной передачи команды с ID появляется готовый доклад. Y передаёт его в рацию; N скрывает. Демо и отмена до отправки не создают предложение. Результат сервера PA не устанавливает; перед Y проверьте, что действие выполнено.')
 d.enabled=s:check('Предлагать готовые доклады##custody-enabled',d.enabled)
 for _,r in ipairs({{'toast_ms','Видимое время тоста, с'},{'ttl_ms','Срок актуальности предложения, с'},{'duplicate_ms','Защита от повторов команды, с'},{'queue_limit','Максимум ожидающих докладов'}})do
  local k=r[1]=='queue_limit'and 1 or 1000;local n=s.imgui.new.int(d[r[1]]/k)
  if s.imgui.InputInt(r[2]..'##custody-'..r[1],n)then d[r[1]]=n[0]*k end
 end
 ui.text('Показ: 1–60 с; актуальность: 1–300 с; повторы: 1–10 с; очередь: 1–8. Время показа идёт только на экране. Ввод и срочные уведомления ставят показ на паузу.')
 d.hint=s:field('Пояснение под докладом##custody-hint','custody:hint',d.hint,4096,true,72)
 for _,r in ipairs(prefs.kinds)do local row=d[r[1]]
  s:settingsHeading(ui,r[2]);row.enabled=s:check('Предлагать после /'..r[3]..' ID##custody-'..r[1],row.enabled)
  row.title=s:field('Заголовок##custody-title-'..r[1],'custody:'..r[1]..':title',row.title,512)
  row.channel=s:choice('Канал##custody-channel-'..r[1],row.channel,require('pa26_server_commands').radioChoices,ui)
  row.template=s:field('Текст доклада##custody-template-'..r[1],'custody:'..r[1]..':template',row.template,3073,true,90)
  local text,err;if callbacks.custodyPreview then text,err=callbacks.custodyPreview(r[1],d)end
  ui.text(text and('Предпросмотр: '..text)or('Для предпросмотра: '..tostring(err or'дождитесь игрового контекста')))
 end
 ui.text('MANUAL 110: 10-15 — подозреваемые арестованы, с количеством и местом; MANUAL 220.10 различает задержание и арест и требует доклад после /arrest. Для КПЗ используется ясный текст без выдуманного отдельного тен-кода. Шаблоны — редактируемая формулировка PA. {unit}, {local_tag}, {location}, {area}, {map_square}, {city}, {count}=1, {subject}=общая формулировка, {officer}, {crew}; полный список переменных — у докладов событий. Ник и ID автоматически в IC-текст не попадают.')
end
return M
