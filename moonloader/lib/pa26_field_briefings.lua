-- Concise PA explanations of the supplied source; editable, not official quotations.
local M={}
local rows={
 {name='Рация: понятный доклад',department='EPD',tag='',favorite=false,lines={
  'Доклад начинается с маркировки юнита. Затем понятно опишите ситуацию и место.',
  'В Мануале допускается свободная форма. Десятичные коды не обязательны: главное — ясная суть.'}},
 {name='Рация: 10-20, 10-15, 10-70',department='EPD',tag='',favorite=false,lines={
  '10-20 — местоположение. Называйте район и понятный ориентир.',
  '10-15 — задержанный под стражей. Сообщайте только установленный вами факт задержания.',
  '10-70 — запрос поддержки. Укажите место и какую помощь требуется оказать.'}}}
function M.defaults()local out={};for i,r in ipairs(rows)do out[i]={name=r.name,tag=r.tag,department=r.department,favorite=r.favorite,lines={}};for j,l in ipairs(r.lines)do out[i].lines[j]=l end end;return out end
function M.source(row)
 for _,r in ipairs(rows)do if row.name==r.name and row.department==r.department and #row.lines==#r.lines then
  local match=true;for i,l in ipairs(r.lines)do if row.lines[i]~=l then match=false;break end end
  if match then return 'Проверенный конспект PA · Мануал Гуерры, том 4, раздел 110 · предоставленная редакция 28.10.2026. Полный источник — в РЕЕСТРЕ.'end
 end end
 return 'Пользовательский конспект · не проверен. Личная версия не изменяет официальный источник.'
end
return M
