local M=require 'pa26_knowledge'
local binder=require 'pa26_binder'
local model=require 'pa26_bindings'
local k=M.new();k:activate(assert(M.validate(TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON))))
local row=k.byKey['offenses:UK:39']
local f={kind='wanted',identity='passport',ic_name='Alex Smith',part='',reason='',stars='3',fine='',
    command='/su {select_id} {param1} {param2}',masked=false,face_known=false,ooc_ack=false}
-- The obsolete stars/article-based raw command must never be composed again.
local b,err
for _,identity in ipairs({'passport','appearance','ooc'})do
    f.identity=identity;f.ooc_ack=true;f.face_known=true
    b,err=k:compose(row,f,9,codec);eq(b,nil);check(err:find('помощник',1,true))
end
local catalog=require 'pa26_wanted_catalog'
eq(#catalog.rows,31)
for _,reason in ipairs(catalog.rows)do
    local card=k.byKey[reason.knowledge_key];check(card);eq(card.item.id,reason.knowledge_card.id)
    check(card.item.text:find('раздел',1,true));check(card.item.text:find('не звёзды',1,true)or card.item.text:find('а не звёзды',1,true))
end
f.identity='appearance';f.masked=false;f.kind='fine';f.command='/myfine {param1} {select_id} {param2}';f.fine='1000'
b,err=k:compose(row,f,9,codec);check(b,err);eq(b.parameters[1].default,'1000');check(b.script:find('постановление',1,true))
eq(b.stat,'fine_player');check(model.validateBinding(b).knowledge)
local jm=require 'pa26_journal';local journal=jm.new()
local e=journal:record({plan={binding=b},demo=false,sent=2},'completed')
eq(e.knowledge.article_id,'UK:39');eq(journal.data.counters.fine_player,nil)
check(jm.validate(journal.data).events[1].knowledge);check(journal:confirm(e.id));eq(journal.data.counters.fine_player,1)
f.masked=true;eq(k:compose(row,f,9,codec),nil);f.masked=false
f.identity='ooc';eq(k:compose(row,f,9,codec),nil);f.identity='appearance'
f.command='/r {select_id} {param1} {param2}';eq(k:compose(row,f,9,codec),nil)
f.command='/myfine {select_id} {param1} {param2}';f.reason=string.rep('ю',160);eq(k:compose(row,f,9,codec),nil,'oversized RP/wire must be refused')
f.reason='Основание\n/su 1 6 x';eq(k:compose(row,f,9,codec),nil,'cannot inject a second command through basis')
f.reason='100%';check(k:compose(row,f,9,codec))
-- No source values are inferred from a manual procedure.
eq(row.item.server_stars,nil);eq(row.item.currency_amount,nil);eq(row.item.game_jail_minutes,nil)
eq(k:compose(k.byKey['commands:command:invite'],f,9,codec),nil)
