local M=require 'pa26_knowledge'
local model=require 'pa26_bindings'
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
local data,err=M.validate(raw);check(data~=nil,err)
eq(#data.offenses,41);eq(#data.articles,987);eq(#data.commands,51)
local files,failed={},false
local fs={exists=function(p)return files[p]~=nil end,read=function(p)return files[p]end,
    write=function(p,v)if failed then return nil end;files[p]=v;return true end,
    rename=function(a,b)if not files[a]or files[b]then return nil end;files[b]=files[a];files[a]=nil;return true end,
    remove=function(p)files[p]=nil;return true end}
local now=0
files.bundle=TEST_KNOWLEDGE_JSON;files.policy=TEST_KNOWLEDGE_POLICY_JSON
local options={json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end},fs=fs,path='active',bundle='bundle',
    policyPath='policy',personalPath='kb_personal.json',now=function()return now end}
local k=M.new(options);check(k:load());eq(#k.records,1370)
for _,r in ipairs(k.records)do
    check(type(r.key)=='string');check(type(M.status(r))=='string')
    for _,l in ipairs(k:detail(r))do check(type(l.text)=='string');check(type(l.label)=='string')end
    for _,s in ipairs(k:sourceLines(r))do check(s.url:match('^https://forum%.exsellentrp%.com/'));check(type(s.date)=='string')end
end
local all=k:search('',{group='offenses'});eq(#all,41)
local results=k:search('УБИЛ',{group='offenses'});check(#results>0);eq(results[1].item.id,'UK:39')
eq(#k:search('/invite',{group='commands'}),1);eq(#k:search('10-66',{group='radio'}),1)
eq(#k:search('  Ук  СТ. 39 ',{group='offenses'}),1)
eq(#k:search('%s',{group='offenses'}),0,'query must be literal, not a Lua pattern')
eq(#k:search('нападение',{group='commands'}),0)
check(k:search('',{group='commands',rp=true})[1].item.rp_required)
eq(#k:search('',{group='commands',rp=true}),21);eq(#k:search('',{group='commands',rp=false}),30)
check(#k:search('',{department='EPD'})<#k.records)
eq(#k:search('',{status='index'}),987)
local row=k.byKey['offenses:UK:39'];check(row)
check(k:favorite(row.key));eq(#k:search('',{favorite=true}),1)
k:opened(row.key);k:opened('commands:command:invite');eq(#k.personal.recent,2)
eq(k:search('',{recent=true})[1].key,'commands:command:invite')
k:opened(row.key);eq(#k.personal.recent,2);eq(k.personal.recent[1],row.key)
check(k:note(row.key,'Моя заметка\n100%'));check(k:mapping(row.key,{stars='3',fine='1000',minutes=''}))
eq(k.personal.mappings[row.key].origin,'manual');eq(row.item.server_stars,nil)
eq(k:mapping(row.key,{stars='three'}),nil)
k:tick();check(k.personalDirty);now=600;k:tick();check(not k.personalDirty);check(files.kb_personal_json==nil)
local again=M.new(options);check(again:load());eq(again.personal.notes[row.key],'Моя заметка\n100%')
eq(again.personal.mappings[row.key].stars,'3')
check(again.policies.taser_copy.note:find('EPD',1,true));check(again.policies.raid_clock.note:find('не подтверждено',1,true))
failed=true;k:note(row.key,'Не потерять');now=1200;k:tick();check(k.personalError);check(k.personalDirty)
k.action='load';k:tick();eq(k.personal.notes[row.key],'Не потерять','reload must not drop unsaved notes')
failed=false;k.personalError=nil;check(k:flush());eq(M.new(options):load(),true)
local candidate=model.copy(raw);candidate.catalog_version='test-next';candidate.offenses[1].notes='Новая заметка источника'
files.kb_import_json=nil;files['kb_import.json']=TEST_JSON_ENCODE(candidate)
k.action='preview_import';k:tick();check(k.candidate);eq(k.data.catalog_version,raw.catalog_version)
k.action='apply_import';k:tick();eq(k.data.catalog_version,'test-next');eq(k.personal.notes[row.key],'Не потерять')
-- Second version gives rollback a real previous active file.
candidate.catalog_version='test-third';files['kb_import.json']=TEST_JSON_ENCODE(candidate)
k.action='preview_import';k:tick();k.action='apply_import';k:tick();eq(k.data.catalog_version,'test-third')
k.action='rollback';k:tick();eq(k.data.catalog_version,'test-next');eq(k.personal.mappings[row.key].stars,'3')
files['kb_import.json']='{"bad":true}';k.action='preview_import';k:tick();eq(k.candidate,nil);check(k.operationError)
eq(k.data.catalog_version,'test-next')
local corrupt=model.copy(raw);corrupt.schema_version=999;eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.commands[1].rp_required='false';eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.offenses[1].source.source_id='not-found';eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.offenses[2].id=corrupt.offenses[1].id;eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.sources[1].url='javascript:alert(1)';eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.patrol_profile.events[1].radio_code={};eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.patrol_profile.sources='bad';eq(M.validate(corrupt),nil)
corrupt=model.copy(raw);corrupt.offenses[1].sanctions[1].life_alternative='false';eq(M.validate(corrupt),nil)
files.active='{invalid';local fallback=M.new(options);check(fallback:load());eq(fallback.data.catalog_version,raw.catalog_version)
eq(files.active,'{invalid','bad original must be preserved')
files.bundle='bad';local broken=M.new(options);check(not broken:load());eq(#broken.records,0);check(broken.error)
local personal=M.personalDefaults();personal.notes['offenses:obsolete']='Retained';check(M.validatePersonal(personal))
personal.mappings.x={stars='-1'};eq(M.validatePersonal(personal),nil)
