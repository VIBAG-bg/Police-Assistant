local knowledge=require 'pa26_knowledge'
local model=require 'pa26_bindings'
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
check(#TEST_KNOWLEDGE_JSON<=knowledge.MAX_BYTES,'Runtime knowledge must fit the bounded JSON reader')
local k=knowledge.new();k:activate(assert(knowledge.validate(model.copy(raw))))
local function joined(lines)
    local values={};for _,line in ipairs(lines)do values[#values+1]=line.label..' '..line.text end
    return table.concat(values,'\n')
end
eq(#raw.sources,94);eq(#raw.articles,1073)
eq(#raw.rules,212);eq(raw.catalog_version,'erp-20261028-normative-0420')
eq(raw.forum_update.public_pages_read,189);eq(raw.forum_update.password_boundaries,4)
for _,sid in ipairs({'355','358'})do eq(k.sources[sid].verification_status,'needs_review');eq(k.sources[sid].interpretation_status,'previous_snapshot_only')end
local ooc=k.byKey['rules:wanted_ooc'].item
check(ooc.text:find('исключительно для /setmark',1,true));check(ooc.text:find('сразу после',1,true))
local mask=k.byKey['rules:rp_mask'].item
check(mask.text:find('одновременно',1,true));check(mask.text:find('без потери человека из виду',1,true))
for _,note in ipairs(k.byKey['rules:wanted_ic'].item.department_notes)do check(note.text:find('непрерывной видимости',1,true))end
check(k.byKey['rules:epd_rank_current'].item.text:find('с 4 ранга',1,true))
check(k.byKey['rules:epd_roles'].item.text:find('SWAT',1,true))
check(k.byKey['rules:fbi_academy'].item.text:find('24 IC-месяца',1,true))
check(k.byKey['rules:fbi_academy'].item.verification_status=='conflict_pending')
local archived,current=0,0
for _,row in ipairs(k.records)do if row.group=='articles'then
    if k:isArchived(row)then archived=archived+1 else current=current+1 end
end end
eq(archived,196);eq(current,877)
for _,key in ipairs({'articles:police:28','articles:prison:14'})do
    local row=k.byKey[key];check(row,key);check(k:isArchived(row));eq(knowledge.status(row),'Архивная редакция')
    eq(knowledge.tone(row),'muted');check(joined(k:detail(row)):find('Архивная редакция',1,true))
    local value,err=k:compose(row,{},'test',codec);eq(value,nil);check(err:find('архивная',1,true))
    -- A personal title/status override must not silently turn the archived legal source into current law.
    local copy=model.copy(row);copy.item.verification_status='reviewed_source_summary';copy.item.title='Мой заголовок'
    check(k:isArchived(copy));local binding,e=k:compose(copy,{},'test',codec);eq(binding,nil);check(e:find('архивная',1,true))
    k:favorite(row.key);check(k:isFavorite(row.key));check(k.byKey[row.key])
end
for _,key in ipairs({'articles:police604:22','articles:police604:26','articles:prison603:14'})do
    check(k.byKey[key],key);check(not k:isArchived(k.byKey[key]))
end
eq(k.byKey['articles:police604:26'].title,'Отчётность о применении силы')
check(k.byKey['articles:police:26'].title:find('Физическая сила',1,true))
check(k.sources['96'].kind=='archived_law'and k.sources['96'].superseded_by=='604')
check(k.sources['174'].kind=='archived_law'and k.sources['174'].superseded_by=='603')
local rights=k.byKey['drafts:rights'];eq(rights.item.origin,'forum_recommendation')
eq(rights.item.verification_status,'historical_source_index');check(k:isArchived(rights));eq(knowledge.tone(rights),'muted');check(k.byKey['drafts:rights_manual_20261028'])
check(rights.item.source_recommended_text:find('Вы задержаны по подозрению',1,true))
check(joined(k:detail(rights)):find('MANUAL 210',1,true));check(rights.item.legal_basis[4]:find('ст. 30',1,true))
for _,rule in ipairs(raw.rules)do
    for _,reference in ipairs(rule.sources or{})do
        if reference.source_id=='96'or reference.source_id=='174'then eq(rule.id,'new_law_editions')end
    end
end
check(k.byKey['rules:dangerous_area'].item.text:find('в одиночку',1,true))
check(k.byKey['rules:force'].item.sources[1].source_id=='604')
check(k.byKey['rules:epd_manual_stop']);check(k.byKey['rules:fbi_mo_coordination'])
local epd=k:search('согласованная операция',{department='EPD',group='rules'})
for _,row in ipairs(epd)do check(row.key~='rules:fbi_mo_coordination')end
local fbi=k:search('согласованная операция',{department='FBI',group='rules'});check(#fbi>0)
check(joined(k:detail(k.byKey['rules:miranda'],'EPD')):find('MANUAL 210',1,true))
check(not joined(k:detail(k.byKey['rules:miranda'],'FBI')):find('MANUAL 210',1,true))
check(k.byKey['gaps:radio_manual_variants']);check(k.byKey['gaps:vehicle_warning_levels']);check(k.byKey['gaps:miranda_manual_update'])
for _,command in ipairs(raw.commands)do eq(command.runtime_verified,false)end
check(raw.installed_in_game==false);check(raw.semantic_review.full_catalog_review_complete==false)
