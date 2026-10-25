local model=require 'pa26_bindings'
local core=require 'pa26_core'
local presets=require 'pa26_rp_presets'
local fresh=model.defaults(core.defaults())
eq(#presets.plan(fresh).items,0)
local old=model.copy(fresh)
for _,r in ipairs(presets.items)do
    local parent=old
    if r.binding_id then parent=model.find(old,r.binding_id)end
    for i=1,#r.path-1 do parent=parent[r.path[i]]end
    parent[r.path[#r.path]]=r.old[#r.old]
end
old.taser.draw_template='моя собственная отыгровка.'
old.weapons.items['24'].name='Custom Weapon';old.weapons.items['24'].enabled=false
old.settings.opacity=.7;old.procedures.fine_command='/ticket {id} {amount} {basis}'
local p=presets.plan(old);check(#p.items>90)
local updated,err=presets.apply(old,p);check(updated,err)
eq(updated.taser.draw_template,'моя собственная отыгровка.');eq(old.taser.draw_template,updated.taser.draw_template)
eq(updated.weapons.items['24'].name,'Custom Weapon');check(not updated.weapons.items['24'].enabled)
eq(updated.settings.opacity,.7);eq(updated.procedures.fine_command,old.procedures.fine_command)
check(model.validate(updated,core.defaults()));eq(#presets.plan(updated).items,0)
local stale=model.copy(old);stale.weapons.items['31'].template='Ещё одна правка.'
check(not presets.apply(stale,p));eq(stale.weapons.items['31'].template,'Ещё одна правка.')
local failedSave={lib=old,rpPresetConfirm=p,weaponDraft={keep=true}}
local ok,why=presets.accept(failedSave,{save=function()return nil,'LOCAL MOCK: disk write failed'end})
check(not ok);check(why:find('LOCAL MOCK',1,true));check(failedSave.weaponDraft.keep)
eq(failedSave.lib.weapons.items['31'].template,old.weapons.items['31'].template)
local fixture=require 'support.fixture'
local s=fixture({demo=false,library=old});s.step();s.page('settings')
local function healthy()check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function click(label)s.click=label;s.render();eq(s.click,nil,label);healthy()end
click('Перенос /me и /do##rp-settings');s.render()
click('Обновить стандартные отыгровки##rp-presets');s.render()
local studio=s.workspace.studio;check(studio.rpPresetConfirm);check(studio:hasModal())
local modal=studio:modalIntent({});eq(modal.kind,'rp_presets');check(#modal.lines>150)
check(table.concat(modal.lines,'\n'):find('Custom Weapon',1,true))
eq(s.workspace.library.weapons.items['31'].template,old.weapons.items['31'].template)
click('НЕТ##confirm-no');check(not studio.rpPresetConfirm)
click('Обновить стандартные отыгровки##rp-presets');s.render();click('ДА##confirm-yes');s.step(700)
eq(s.workspace.library.weapons.items['31'].template,fresh.weapons.items['31'].template)
eq(s.workspace.library.taser.draw_template,'моя собственная отыгровка.')
studio:select(studio.selected)
eq(studio.draft.script,model.find(s.workspace.library,studio.selected).script,'An open clean draft must not resurrect the old standard')
local saved=s.savedLibrary()
eq(saved.weapons.items['31'].template,fresh.weapons.items['31'].template);eq(saved.taser.draw_template,'моя собственная отыгровка.')
studio.dirty=true;click('Обновить стандартные отыгровки##rp-presets');check(not studio.rpPresetConfirm)
eq(#s.sent,0);eq(#s.localChat,0);healthy();onScriptTerminate(s.script)
