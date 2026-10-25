local identity=require'pa26_identity'
local phrase=identity.defaults().passport_phrase
for _,line in ipairs({
    'Rafayel_Barvello '..phrase..' Victor_Auditore',
    '[18:32] ME Rafayel_Barvello[38] '..phrase..' Victor_Auditore[75].',
    '[18:32:07] [ME] Rafayel_Barvello (38): '..phrase..' Victor_Auditore (75).',
    '18:32 ME Rafayel_Barvello [38] '..phrase..' Victor_Auditore [75]',
    '{C2A2DA}* Rafayel_Barvello '..phrase..' Victor_Auditore.',
    '[ME] Rafayel_Barvello[38]: '..phrase..' Victor_Auditore[75]',
})do
    local actor,recipient=identity.passportMessage(line,phrase,true)
    eq(actor,'Rafayel_Barvello',line);eq(recipient,'Victor_Auditore',line)
end
for _,line in ipairs({
    'Rafayel_Barvello: '..phrase..' Victor_Auditore',
    'Rafayel_Barvello[38]: '..phrase..' Victor_Auditore',
    '[OOC] Rafayel_Barvello '..phrase..' Victor_Auditore',
    '/me Rafayel_Barvello '..phrase..' Victor_Auditore',
    'Rafayel_Barvello якобы '..phrase..' Victor_Auditore',
    'Rafayel_Barvello '..phrase..' Victor_Auditore\n/r injected',
    'Rafayel_Barvello '..phrase..' Victor_Auditore\0',
})do check(not identity.passportMessage(line,phrase,true),line)end
check(not identity.passportMessage('[18:32] ME Rafayel_Barvello[38] '..phrase..' Victor_Auditore.',phrase,false))
local legacy=identity.defaults();legacy.passport_revision=nil;legacy.passport_server='185.207.214.114:7777'
eq(assert(identity.validate(legacy)).passport_server,'','The former stock IP must not silently prevent recognition')
legacy.passport_server='custom.example:7777';eq(assert(identity.validate(legacy)).passport_server,legacy.passport_server)
legacy.passport_revision=2;legacy.passport_server='185.207.214.114:7777';eq(assert(identity.validate(legacy)).passport_server,legacy.passport_server,'An explicit new restriction remains intact')
check(not identity.validate({passport_revision=3}))

local fixture=require'support.fixture';local model=require'pa26_bindings';local core=require'pa26_core'
for _,backend in ipairs({'native','cef'})do
    local lib=model.defaults(core.defaults())
    local s=fixture({demo=false,library=lib,alerts=true,categoryWheel=true});s.name='Victor_Auditore'
    s.actors={[99]={id=38,name='Rafayel_Barvello',x=0,y=2,z=0,sx=600,sy=350}}
    s.step();s.commands.pa26select('38');s.step()
    local line='[18:32] [ME] Rafayel_Barvello[38] '..phrase..' Victor_Auditore[75].'
    if backend=='native'then s.events.onServerMessage(-1,codec.encode(line))
    else
        check(s.chatBridge:exchange(encodeJson({schema=1,page='passport-formats',chat=false,dialog=false,busy=false,
            events={{id=1,kind='message',text=line,session=s.chatBridge.env.session()}}}),s.now))
    end
    eq(s.identity:view().record.passport_seen,'unknown','Callbacks only enqueue proof')
    s.step();local r=s.identity:view().record
    eq(r.passport_seen,'yes',backend);eq(r.passport_source,'server');eq(r.ic_name,'');eq(r.passport_number,'');eq(r.mask,'unknown')
    check(type(s.identity:view().passportStatus)=='string');eq(#s.sent,0)
    s.workspace.library.identity.passport_diagnostics=false;eq(s.identity:view().passportStatus,nil)
    s.workspace.library.identity.passport_diagnostics=true;check(type(s.identity:view().passportStatus)=='string')
    onScriptTerminate(s.script)
end
