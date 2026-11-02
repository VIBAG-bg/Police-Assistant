-- Reports are editable suggestions after a real outgoing command, not server receipts.
local core=require 'pa26_core';local shared=require 'pa26_patrol_settings'
local M={kinds={{'detention','Задержание подозреваемого','cuff'},{'jail','Помещение в КПЗ','arrest'}}}
M.variables=shared.copy(shared.variables);M.variables.count=true;M.variables.subject=true
function M.defaults()
 return {enabled=true,toast_ms=20000,ttl_ms=120000,duplicate_ms=1000,queue_limit=4,
  hint='Y — передать доклад; N — не передавать. Команда передана клиенту; перед Y убедитесь, что действие выполнено.',
  detention={enabled=true,channel='/f',title='Задержание · передать доклад?',
   template='{local_tag}{unit}: 10-15, задержан один подозреваемый. 10-20: {location}.'},
  jail={enabled=true,channel='/f',title='КПЗ · передать доклад?',
   template='{local_tag}{unit}: один задержанный помещён в КПЗ. 10-20: {location}.'}}
end
function M.template(text)
 text=shared.text(text,768)
 if not text or text==''or text:match('^[/@]')then return nil,'Нужен текст доклада без команды и перевода строки.'end
 local rest=core.stripGender(text):gsub('{([a-z_]+)}',function(k)return M.variables[k]and''or'{'end)
 if rest:find('[{}]')then return nil,'Неизвестная переменная доклада задержания / КПЗ.'end
 return text
end
function M.validate(raw)
 local out=M.defaults();if raw==nil then return out end
 if type(raw)~='table'then return nil,'Повреждены настройки докладов задержания / КПЗ.'end
 for k in pairs(raw)do if out[k]==nil then return nil,'Неизвестная настройка докладов задержания / КПЗ.'end end
 if raw.enabled~=nil then if type(raw.enabled)~='boolean'then return nil,'Включение докладов: да / нет.'end;out.enabled=raw.enabled end
 for _,r in ipairs({{'toast_ms',1000,60000},{'ttl_ms',1000,300000},{'duplicate_ms',1000,10000},{'queue_limit',1,8}})do
  local n=raw[r[1]]or out[r[1]];if not shared.integer(n,r[2],r[3])then return nil,'Проверьте время и очередь докладов задержания / КПЗ.'end;out[r[1]]=n
 end
 if out.ttl_ms<out.toast_ms then return nil,'Срок актуальности не может быть короче видимого показа.'end
 out.hint=shared.text(raw.hint or out.hint,1024);if not out.hint or out.hint==''then return nil,'Нужно пояснение к подтверждению доклада.'end
 for _,r in ipairs(M.kinds)do local row=raw[r[1]]or out[r[1]]
  if type(row)~='table'or type(row.enabled)~='boolean'or(row.channel~='/r'and row.channel~='/f'and row.channel~='/d')then return nil,'Доклад: проверьте включение и канал рации.'end
  local title=shared.text(row.title,160);local template,why=M.template(row.template)
  if not title or title==''or not template then return nil,why or'Нужен заголовок доклада.'end
  out[r[1]]={enabled=row.enabled,channel=row.channel,title=title,template=template}
 end
 return out
end
return M
