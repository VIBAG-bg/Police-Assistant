-- Exercise the real draw function; no dependency on the new draft helper API.
local module=require 'pa26_ground_window'
local f={request={groundTarget={id=37,name='Driver_Name'},kind='stop',token='one'},cfg=require('pa26_copilot_settings').defaults()}
f.cfg.stop_ground='exam_refusal';f.cfg.ground_intro=false
local s={groundForm=f,lib={vehicle={}},imgui={GetIO=function()return {DisplaySize={y=864}}end,ImVec2=function()end,BeginChild=function()return true end,EndChild=function()end,SameLine=function()end}}
function s:choice(_,value)return value end;function s:check(_,value)return value,false end
function s:button(label)if self.click and label:find(self.click,1,true)then self.click=nil;return true end;return false end
function s:field(label,_,value)if label:find('##ground-speech',1,true)and self.edit then local v=self.edit;self.edit=nil;return v end;return value end
function s:setBuffer()end
local preview,offered
local cb={groundValid=function()return true end,groundSpeech=function(form)return 'Речь по причине '..form.cfg.stop_ground end,
 groundPreview=function(form)preview=form.cfg._ground_speech;return{lines={preview}}end,sanctions=function()return{byId={}}end,
 groundOffer=function(form)offered=form.cfg._ground_speech;return{}end}
local function draw()module.draw(s,{text=function()end},{},cb)end
draw();eq(f.speech,'Речь по причине exam_refusal')
s.edit='Мой текст причины A';draw();eq(f.speech,s.edit or'Мой текст причины A')
f.cfg.stop_ground='left_accident';draw();eq(f.speech,'Речь по причине left_accident','Reason B must not use the edited draft of reason A')
eq(preview,f.speech);s.click='##ground-send';draw();eq(offered,'Речь по причине left_accident')
f.cfg.stop_ground='exam_refusal';draw();eq(f.speech,'Мой текст причины A','Switching back restores the unsaved per-reason draft')
s.click='##ground-speech-reset';draw();eq(f.speech,'Речь по причине exam_refusal')
s.click='##ground-speech-undo';draw();eq(f.speech,'Мой текст причины A')
f.cfg.stop_ground='left_accident';draw();s.edit='Моя причина B';draw()
local drafts=f.speechDrafts
s.groundForm={request=f.request,cfg=f.cfg,speechDrafts=drafts};draw();eq(s.groundForm.speech,'Моя причина B','Reopening the same situation retains drafts')
