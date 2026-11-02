local M=require 'pa26_cef_compat';local counts={read=0,hash=0}
local read=function(path)eq(path,'virtual/main.js');counts.read=counts.read+1;return 'known bytes'end
local hash=function(text)counts.hash=counts.hash+1;eq(text,'known bytes');return M.reviewed end
local checkContract=M.new('virtual/',read,hash)
check(checkContract());for _=1,1000 do check(checkContract())end
eq(counts.read,1);eq(counts.hash,1,'No hashing on keystrokes, bridge tick or reconnect')
local bad=M.new('virtual/',read,function()return string.rep('0',64)end)
local ok,reason=bad();check(not ok);eq(reason,'cef_contract_unreviewed')
check(not M.new('x/',function()error('no file')end,hash)())
check(not M.new('x/',function()return string.rep('a',M.max_bytes+1)end,hash)())
check(not M.new('x/',function()return 'bytes'end,function()error('missing crypto')end)())
check(not M.new('x/',function()return nil end,hash)())
local source=assert(io.open('moonloader/police_assistant_2026.lua','rb')):read('*a')
check(source:find('cef_chat_support and sceneServices.cefContractAllowed==true',1,true))
local bridge=assert(io.open('moonloader/lib/pa26_chat_bridge.lua','rb')):read('*a')
check(not bridge:find('compatibility',1,true),'Bridge protocol and processing paths remain unchanged')
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
