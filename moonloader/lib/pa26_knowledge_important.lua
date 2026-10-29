-- Build in main after a catalogue revision; GUI consumes plain presentation rows.
local model=require 'pa26_bindings'
local defs=require 'pa26_important_data'
local M={}
local function clean(s)return tostring(s or''):gsub('https?://%S+',''):gsub('##','# #')end
local function label(row)
 local edit=row and row.edit and row.edit.status
 return edit=='override'and'Моя версия' or edit=='custom'and'Моя карточка'or(edit=='conflict'or edit=='collision')and'Личная правка требует сравнения'or nil
end
function M.build(k)
 local out={revision=k.revision,cards=model.copy(defs.cards),byId={},rows={},radioCount=0,required=0,free=0}
 local function add(c,s,row)
  row=model.copy(row);row.title=clean(row.title);row.text=clean(row.text);row.card=c.id;row.section=s.id
  row.key=c.id..':'..row.id;row.search=model.casefold(row.title..' '..row.text..' '..c.title..' '..s.title)
  s.rows[#s.rows+1]=row;return row
 end
 for _,c in ipairs(out.cards)do out.byId[c.id]=c
  for _,s in ipairs(c.sections)do local rows=s.rows;s.rows={}
   for _,r in ipairs(rows)do
    local rcopy=model.copy(r)
    for _,ref in ipairs(r.refs or{})do if label(k.byKey[ref])then rcopy.note='В РЕЕСТРЕ есть личная версия связанного правила; памятка изложена по исходной редакции.';break end end
    add(c,s,rcopy)
   end
  end
 end
 local function section(card,id)for _,s in ipairs(out.byId[card].sections)do if s.id==id then return s end end end
 for group,codes in pairs(defs.radio_groups)do
  for _,code in ipairs(codes)do local item=k.byKey['radio:manual4:'..code]
   if item then add(out.byId.radio,section('radio',group),{id=code,title=code,text=item.item.meaning,note=label(item),refs={item.key}});out.radioCount=out.radioCount+1 end
  end
 end
 local manual=k.byKey['rules:manual-current:4:110:1']
 if manual then
  local text=manual.item.text or''
  for _,code in ipairs({'LINCOLN','ADAM','MARY','HENRY','AIR','DAVID','CHARLES','ROBERT'})do
   local found
   for line in text:gmatch('[^\r\n]+')do if line:match('^%s*'..code..'%s*[%(%-]')then found=line;break end end
   if found then add(out.byId.radio,section('radio','units'),{id='unit-'..code,title=code,text=found,note=label(manual),refs={manual.key}})end
  end
 end
 local stop=k.byKey['rules:manual-current:4:230:2']
 if stop then
  local procedure=(stop.item.text or''):match('Процедура:(.*)');local steps={}
  local names={'Требование остановиться','Двигатель, ключи и руки','Доклад об остановке','Багажник и осмотр салона','Представиться и назвать причину','Проверка и решение','Завершение и итоговый доклад'}
  for line in(procedure or''):gmatch('[^\r\n]+')do local n,body=line:match('^%s*([1-7])%.%s*(.*)')
   if n then steps[tonumber(n)]={id='step-'..n,title='Шаг '..n..' · '..names[tonumber(n)],text=body,refs={stop.key},note=label(stop)}end
  end
  if #steps==7 then
   local s=section('traffic','stop');for i=#s.rows,1,-1 do if s.rows[i].id=='sequence'then table.remove(s.rows,i)end end
   for _,r in ipairs(steps)do add(out.byId.traffic,s,r)end
   add(out.byId.traffic,s,{id='stop-safety',title='Безопасное место и ночной осмотр',text='Попросите переставить автомобиль, если он оказался на опасном участке. Мануал запрещает прижиматься к обочине на поворотах, развилках, мостах, склонах и в тоннелях. При возможности сверните с дороги с обильным движением. Ночью используйте фонарик для осмотра салона. Адекватное поведение и обстоятельства нарушения могут позволять устное предупреждение.',refs={stop.key},note=label(stop)})
  end
 end
 for _,row in ipairs(k.records)do local i=row.item;local n=tonumber(i.article)
  if row.group=='articles'and i.code=='AK'and n and n>=20 and n<=62 then
   local lines={};for _,v in ipairs(i.sanctions or{})do lines[#lines+1]=(v.condition or'')..' '..(v.alternative or v.source_excerpt or'')end
   local r={id=i.id,title=(i.reference or('АК '..n))..' · '..i.title,text=i.text or i.local_text or table.concat(lines,'\n'),
       summary=table.concat(lines,'\n'),note=label(row),refs={row.key},action={kind='fine',value=i.reference or('Административный кодекс ст. '..n)}}
   add(out.byId.fines,section('fines','all'),r)
   add(out.byId.fines,section('fines',n>=37 and n<=49 and'road'or n<=36 and'public'or'authority'),r)
  end
 end
 for _,s in ipairs(out.byId.fines.sections)do table.sort(s.rows,function(a,b)local x,y=tonumber(a.id:match('AK:(%d+)')),tonumber(b.id:match('AK:(%d+)'));return x and y and x<y or not(x and y)and a.id<b.id end)end
 local wanted=require 'pa26_wanted_catalog'
 for _,r in ipairs(wanted.rows)do
  local laws={};for _,ref in ipairs(r.refs)do local law=k.byKey['articles:'..ref]
   if law then laws[#laws+1]=(law.item.reference or ref)..' · '..law.item.title end
  end
  local text=r.note..'\n'..(#laws>0 and('Возможные нормы, при наличии их признаков:\n'..table.concat(laws,'\n'))or'Прямое соответствие норме не установлено; проверьте состав по обстоятельствам.')
  add(out.byId.catalog,section('catalog','all'),{id=r.id,title=r.id..' · '..r.title..' · '..r.stars..' зв.',text=text,
   summary=r.group_title..' · '..r.mapping_status,refs=r.refs,action={kind='wanted',value=r.id}})
 end
 local seen={}
 for _,entry in ipairs(defs.command_matrix)do if not seen[entry.command]then seen[entry.command]=true
  local ref=k.byKey['commands:command:'..entry.command:sub(2)];local required=entry.rp_required
  if ref and type(ref.item.rp_required)=='boolean'then required=ref.item.rp_required end
  local row={id=entry.command,title=entry.command,text=required and'Требует RP-отыгровки.'or'Не требует отдельной RP-отыгровки по разделу XI.',
   note=label(ref),refs=ref and{ref.key}or{},summary=required and'RP обязательно'or'Без отдельного RP'}
  add(out.byId.commands,section('commands','all'),row);add(out.byId.commands,section('commands',required and'required'or'free'),row)
  if required then out.required=out.required+1 else out.free=out.free+1 end
 end end
 add(out.byId.commands,section('commands','extra'),{id='/ticket',title='/ticket ID сумма причина',text='Синтаксис отдельно подтверждён пользователем. Процедура штрафа сопровождается RP. Команда не входит в таблицу 50 команд раздела XI.',action={kind='fine'}})
 add(out.byId.commands,section('commands','extra'),{id='/wanted',title='/wanted',text='Общий серверный список преступников. По предоставленным наблюдениям поиска по ID в нём нет. Отдельная RP-отыгровка не требуется.'})
 local indexed={}
 for _,c in ipairs(out.cards)do for _,s in ipairs(c.sections)do for _,r in ipairs(s.rows)do if not indexed[r.key]then indexed[r.key]=true;out.rows[#out.rows+1]=r end end end end
 out.byId.radio.subtitle=out.radioCount..' кодов · маркировки и порядок доклада'
 out.byId.commands.subtitle=(out.required+out.free)..' команд · с RP: '..out.required..' · без отдельного RP: '..out.free
 return out
end
function M.filter(data,query,card,tab)
 local out={};query=model.casefold(query or''):match('^%s*(.-)%s*$')
 local source=data.rows
 if card and data.byId[card]then for _,s in ipairs(data.byId[card].sections)do if s.id==tab then source=s.rows;break end end end
 for _,r in ipairs(source)do if(not card or r.card==card)and(query==''or r.search:find(query,1,true))then out[#out+1]=r end end
 return out
end
return M
