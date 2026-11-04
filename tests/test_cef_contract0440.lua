local M=require 'pa26_cef_compat'
local counts={start=0,poll=0,close=0};local sample={schema=2,known=false,allowed=true,state='CONTRACT_COMPATIBLE',reason='normalized_contract_and_dom',
 sha256=string.rep('d',64),fingerprint='test',capabilities={dom=true,outgoing=true,incoming=true,payloads=true,lifecycle=true,focus=true,ipc=true,adapter_order=true}}
local c=M.controller({start=function()counts.start=counts.start+1;return {}end,poll=function()counts.poll=counts.poll+1;return sample end,close=function()counts.close=counts.close+1 end})
eq(c:check(0),sample)
for i=1,10000 do eq(c:check(i),sample)end
eq(counts.start,1);eq(counts.poll,1);eq(counts.close,1,'No process or filesystem work after initialization')
local timeout=M.controller({start=function()return{}end,poll=function()end});eq(timeout:check(0).reason,'analysis_pending');eq(timeout:check(30001).reason,'analysis_timeout')
local failure=M.controller({start=function()error('denied')end});eq(failure:check(0).state,'UNAVAILABLE')
local invalid=M.controller({start=function()return{}end,poll=function()return{schema=2,allowed=true}end});eq(invalid:check(0).reason,'analysis_invalid_reply')
local source=assert(io.open('moonloader/police_assistant_2026.lua','rb')):read('*a')
check(source:find('cef_chat_support and sceneServices.cefContractAllowed==true',1,true))
check(source:find('cefVerifier:check',1,true))
local p=TEST_JSON_DECODE(assert(io.open('presets/pa-settings.json','rb')):read('*a'))
local windows=p.settings.data.settings.window_layout.windows
eq(next(windows),nil,'Shared author defaults reset old pixels and use the responsive reference')
eq(p.settings.data.settings.window_layout.default_style,'author')
local model=require 'pa26_bindings';local core=require 'pa26_core';local cfg=core.defaults();local lib=model.defaults(cfg)
local ready=assert(require('pa26_author_presets').prepare('settings',p,lib,cfg))
eq(next(ready.library.settings.window_layout.windows),nil)
local layout=require 'pa26_geometry'
for _,size in ipairs({{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 local rect=layout.rect(size[1],size[2],'assist',nil,70,'author')
 check(rect.width>=math.min(1000,size[1]-32));check(rect.x>=16 and rect.y>=16)
 check(rect.x+rect.width<=size[1]-16);check(rect.y+rect.height<=size[2]-16)
end
local fixture=require 'support.fixture';local f=fixture({reviewedCef=false,render=false});f.step()
check(not f.chatBridge.env.settings().enabled);eq(f.cefContractChecks,1)
for _=1,100 do f.step(16)end;eq(f.cefContractChecks,1,'Unknown client is not repeatedly hashed')
eq(f.chatBridge.server,nil);eq(f.chatBridge.status,'disabled');onScriptTerminate(f.script)
