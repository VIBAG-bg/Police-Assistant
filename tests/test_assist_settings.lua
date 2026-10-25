local prefs=require 'pa26_assist_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local study=require 'pa26_training'
local function valid(c)return prefs.validate(c)end
local cfg=prefs.defaults();check(valid(cfg));check(not cfg.evidence.enabled);check(not cfg.evidence.time_enabled);eq(#cfg.training.cards,0)
local old=model.defaults(core.defaults());old.assist=nil;old.vehicle.phrases=nil
for i=1,8 do old.vehicle['phrase_'..i..'_shortcut']=nil end
local clean=assert(model.validate(old,core.defaults()));eq(#clean.vehicle.phrases,8);check(not clean.assist.evidence.time_enabled)
for _,sp in ipairs({{'delay_ms',-1},{'delay_ms',30001},{'timeout_ms',999},{'timeout_ms',600001},{'confirmation_ms',999},{'delay_ms',0/0}})do
    local c=model.copy(cfg);c.evidence[sp[1]]=sp[2];check(not valid(c))
end
for _,s in ipairs({'/time 1','/time\n/su 1','time','/time;evil','/time{a}'})do local c=model.copy(cfg);c.evidence.time_command=s;check(not valid(c))end
cfg.evidence.time_enabled=true;check(not valid(cfg));cfg.evidence.time_verified=true;check(not valid(cfg));cfg.evidence.time_source='/help: /time';check(valid(cfg))
cfg.evidence.prompt='Строка 1\nСтрока 2';check(valid(cfg))
cfg.training.cards={{id=1,name='Основание',enabled=true,question='Вопрос?\nВторая строка',answer='Ответ.\nПродолжение.',source='Личный конспект',revision='20.10.2026',department='EPD'},
    {id=2,name='Общий',enabled=true,question='Второй?',answer='Два.',source='Свой материал',revision='1',department='all'},
    {id=3,name='FBI',enabled=true,question='Третий?',answer='Три.',source='Свой материал',revision='1',department='FBI'}}
cfg.training.next_id=4;cfg.training.department='EPD';cfg=assert(valid(cfg))
local t=study.new();check(t:start(cfg.training));local c=assert(t:current(cfg.training));eq(c.id,1)
check(not t:grade(cfg.training,true));check(t:reveal(cfg.training))
local changed,token=t:grade(cfg.training,false);check(changed);eq(t.session.index,1,'Persistence must succeed before advancing')
check(t:commit(token));check(not t:commit(token));eq(t:current(changed).id,2)
local migrated=model.copy(cfg);migrated.training=changed;check(valid(migrated).training.progress['1'])
for _,k in ipairs({'question','answer','source','revision','department'})do
    local c=model.copy(migrated);c.training.cards[1][k]=k=='department'and 'FBI'or(c.training.cards[1][k]..' изменено')
    local n=assert(valid(c));check(not n.training.progress['1'],'Edited revision cannot retain old progress')
end
local c2=model.copy(changed);c2.cards[2].answer='Изменено';check(not t:current(c2));check(not t.session)
local partial=prefs.defaults();partial.training.cards={{id=1,name='Черновик',enabled=false,question='',answer='',source='',revision='',department='all'}};partial.training.next_id=2
check(valid(partial));partial.training.cards[1].enabled=true;check(not valid(partial))
local collision=model.defaults(core.defaults());collision.assist.evidence_shortcut={key=0x59,ctrl=false,alt=false,shift=false}
check(not model.validate(collision,core.defaults()))
collision.assist.evidence_shortcut=model.copy(collision.vehicle.megaphone_shortcut);check(not model.validate(collision,core.defaults()))
for _,limit in ipairs({1,2,50})do local c=model.copy(cfg.training);c.limit=limit;check(t:start(c));eq(#t.session.rows,math.min(2,limit))end
local tooMany=prefs.defaults();for i=1,97 do tooMany.training.cards[i]={}end;check(not valid(tooMany))
local bad=model.copy(cfg);bad.training.progress['1']={revision='x',known=-1,repeat_count=0};check(not valid(bad))
local h=prefs.defaults();h.history={{status='verified',demo=true,verified=true,date='',label='',path='',details=''}};check(not valid(h))
