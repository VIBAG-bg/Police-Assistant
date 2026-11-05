local m=require 'pa26_bindings';local users=require 'pa26_user_files';local core=require 'pa26_core';local equal=require('pa26_author_presets').equal
local cfg=core.defaults();local lib=assert(m.validate(m.defaults(cfg),cfg))
lib.profile.name='Personal Officer';lib.profile.badge_number='PERSONAL-77';lib.profile.callsign='MY-UNIT'
lib.settings.wheel_names.citizen='My foot';lib.settings.wheel_car_names.citizen='My car'
lib.settings.wheel_order={root={'wanted','custom'},wanted={'s:procedure-mark','b:1'}}
lib.settings.wheel_car_order={root={'custom','service'}}
lib.settings.manual_actions.rules.cuff.rp='/me моя личная отыгровка.'
lib.vehicle.copilot.templates.risk_open='Мой сохранённый текст.'
lib.notes[1].body='Private note';lib.bindings[1].script='/me моя любимая отыгровка.';lib.bindings[1].favorite=true
lib.bindings[1].shortcut={key=0x75,ctrl=true,alt=false,shift=false}
local expected=m.copy(lib);local payload=users.partition(lib)
local encoded=TEST_JSON_ENCODE(payload);local roundtrip=TEST_JSON_DECODE(encoded)
local restored=assert(users.combine(roundtrip,cfg))
for _,k in ipairs({'bindings','wheel','profile','notes','partners','settings','vehicle'})do check(equal(restored[k],expected[k]),'Preserve '..k)end
-- Old 0.45.0 records lack only the new optional fields. No author defaults
-- are installed as a side effect of decoding those records.
lib.profile.badge_number=nil
for _,b in ipairs(lib.bindings)do b.wheel_extra_groups=nil;b.wheel_car_extra_groups=nil;b.rp_context=nil end
local next=assert(m.validate(lib,cfg));eq(next.profile.badge_number,'');eq(next.bindings[1].script,lib.bindings[1].script)
eq(next.settings.manual_actions.rules.cuff.rp,lib.settings.manual_actions.rules.cuff.rp)
eq(next.vehicle.copilot.templates.risk_open,lib.vehicle.copilot.templates.risk_open)
eq(next.settings.wheel_car_names.citizen,'My car');eq(next.settings.wheel_names.citizen,'My foot')
eq(next.settings.wheel_order.root[1],'wanted');eq(next.settings.wheel_car_order.root[1],'custom')
local b=m.newBinding(99);b.rp_context={vehicle='traffic',bike_script='/me осмотрела мотоцикл.',identity=true,checkpoints={{before=1,prompt='Подтвердить?'}}}
b.wheel_car_extra_groups={'custom'};b.script='/me осмотрела автомобиль.'
next.bindings[#next.bindings+1]=b;next.next_id=100
local p=users.partition(assert(m.validate(next,cfg)));local combined=assert(users.combine(TEST_JSON_DECODE(TEST_JSON_ENCODE(p)),cfg))
check(equal(m.find(combined,99).rp_context,b.rp_context));eq(m.find(combined,99).wheel_car_extra_groups[1],'custom')
