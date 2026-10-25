local model=require 'pa26_bindings'
local store=require 'pa26_library'
local core=require 'pa26_core'
local data={}; local fail={}
local fs={exists=function(p) return data[p]~=nil end,read=function(p) return data[p] end,
    write=function(p,text) if fail.write then return nil end; data[p]=fail.partial and text:sub(1,20) or text; return true end,
    remove=function(p) if fail.remove then return nil end; data[p]=nil; return true end,
    rename=function(a,b) if fail.rename or (fail.replace and a=='book.tmp') or not data[a] or data[b] then return nil end; data[b]=data[a]; data[a]=nil; return true end}
local json={encode=function(v) return TEST_JSON_ENCODE(v) end,decode=function(v) return TEST_JSON_DECODE(v) end}
local cfg=core.defaults(); local validate=function(v) return model.validate(v,cfg) end
local defaults=function() return model.defaults(cfg) end
local lib,notes,fresh=store.load('book',json,validate,defaults,fs); check(fresh); eq(#notes,0)
check(store.save('book',lib,json,validate,fs)); check(store.decode(data.book,json,validate))
local before=data.book; lib.bindings[1].name='Исправлено'
for _,name in ipairs({'write','partial','replace'}) do fail[name]=true; check(not store.save('book',lib,json,validate,fs)); eq(data.book,before,'old file changed after '..name); fail[name]=false; data['book.tmp']=nil end
check(store.save('book',lib,json,validate,fs)); eq(data['book.bak'],before)
data.book='bad json'; local recovered,warnings=store.load('book',json,validate,defaults,fs); check(#warnings>0); eq(recovered.bindings[1].name,'Представиться')
check(store.save('book',recovered,json,validate,fs)); eq(data['book.rejected'],'bad json'); eq(data['book.bak'],before)
local backup=data['book.bak']; data['book.rollback']='broken previous write'; check(store.save('book',recovered,json,validate,fs)); check(store.decode(data['book.bak'],json,validate)); check(data['book.rejected'])
check(not store.decode(string.rep('[',25)..string.rep(']',25),json,validate))
check(not store.decode('[]\0',json,validate))
check(not store.decode(string.rep('x',store.MAX_BYTES+1),json,validate))
local broad=defaults(); for n=7,30 do local b=model.newBinding(n); b.script=string.rep('x',3000); broad.bindings[#broad.bindings+1]=b; broad.next_id=n+1 end
check(store.save('large',broad,json,validate,fs)); eq(#store.load('large',json,validate,defaults,fs).bindings,30)
check(#data.large>65536,'test must exceed the old INI reader limit')
check(store.save(TEST_TEMP_PATH,broad,json,validate)); local native=store.load(TEST_TEMP_PATH,json,validate,defaults); eq(#native.bindings,30)
