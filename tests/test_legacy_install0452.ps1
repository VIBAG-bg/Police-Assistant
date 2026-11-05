param([Parameter(Mandatory=$true)][string]$LegacyArchive,[Parameter(Mandatory=$true)][string]$RuntimeArchive)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'tools/pa-setup-window.ps1') -Library
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Join-Path $release ('tests/install-sandbox/l52-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
[IO.Directory]::CreateDirectory($root)|Out-Null
$checks=0;$cases=New-Object 'Collections.Generic.List[string]'
function Check($Value,[string]$Why){$script:checks++;if(-not $Value){throw ('ASSERT: '+$Why)}}
function Reject([scriptblock]$Test,[string]$Pattern){
    $reason=''
    try{&$Test|Out-Null}catch{$reason=$_.Exception.Message}
    Check ($reason -match $Pattern) ('expected refusal '+$Pattern+'; received '+$reason)
}
function Zip-Text($Zip,[string]$Name){
    $reader=New-Object IO.StreamReader($Zip.GetEntry($Name).Open(),[Text.Encoding]::UTF8)
    try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
}
function Extract-One($Zip,[string]$Name,[string]$Target){
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))|Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($Zip.GetEntry($Name),$Target)
}
function Personal-Path([string]$ML,[string]$Kind){
    return Join-Path $ML ('config/police_assistant_2026_'+$Kind+'.json')
}
function Read-Part([string]$ML,[string]$Kind){return ,(Read-PaPresetJson ([IO.File]::ReadAllText((Personal-Path $ML $Kind))))}
function Write-Part([string]$ML,[string]$Kind,$Data){
    [IO.File]::WriteAllText((Personal-Path $ML $Kind),(Write-PaPresetJson $Data),(New-Object Text.UTF8Encoding($false)))
}
function Snapshot([string]$Path,[string]$Exclude=''){
    $state=@{}
    foreach($file in Get-ChildItem -LiteralPath $Path -Recurse -File){
        $rel=$file.FullName.Substring($Path.Length+1)
        if($Exclude -and $rel.StartsWith($Exclude,[StringComparison]::OrdinalIgnoreCase)){continue}
        $state[$rel]=Get-PaHash $file.FullName
    }
    return $state
}
function Assert-Snapshot([string]$Path,$State,[string]$Exclude=''){
    Check (Test-PaPresetEqual $State (Snapshot $Path $Exclude)) ('exact byte restoration at '+[IO.Path]::GetFileName($Path))
}
function New-Game([string]$Name,[bool]$Legacy=$true){
    $game=Join-Path $root $Name
    [IO.Directory]::CreateDirectory($game)|Out-Null
    $ml=Join-Path $game 'MoonLoader'
    if($Legacy){
        Copy-Item -LiteralPath $oldML -Destination $ml -Recurse
        [IO.File]::Copy($luaFile,(Join-Path $game 'lua51.dll'))
    }else{[IO.Directory]::CreateDirectory($ml)|Out-Null}
    return $ml
}
function Install([string]$DestinationRoot,[switch]$PreviewLegacyPresets,[string]$LegacyPreview,
    [switch]$SkipLegacyPresets,[int]$TestFailAfter,[switch]$TestInterrupt){
    & (Join-Path $release 'install.ps1') @PSBoundParameters
}
function Record([string]$Name){$cases.Add($Name);Write-Output ('PASS '+$Name)}
$oldSha='96f33ca6a710055f20a29d5a0374b6cb2e6119b09f2e631638153218a168d09f'
Check ((Get-PaHash $LegacyArchive) -ceq $oldSha) 'official legacy installer fixture identity'
Check ((Get-PaHash $RuntimeArchive) -ceq '21d55eeefe4c7bb9962a879c0f64ba28c564bc36a330fd282dcd46c8b7280d9f') 'verified LuaJIT archive'
$oldML=Join-Path $root 'old/MoonLoader'
$luaFile=Join-Path $root 'old/lua51.dll'
$runtime=[IO.Compression.ZipFile]::OpenRead($RuntimeArchive)
try{Extract-One $runtime 'lua51.dll' $luaFile}finally{$runtime.Dispose()}
$legacy=[IO.Compression.ZipFile]::OpenRead($LegacyArchive)
try{
    $oldManifest=Zip-Text $legacy 'INSTALL_MANIFEST.json'|ConvertFrom-Json
    foreach($row in $oldManifest.files){
        $target=Get-PaSetupPath $oldML $row.path.Replace('\','/')
        Extract-One $legacy ('moonloader/'+$row.path.Replace('\','/')) $target
        Check ((Get-PaHash $target) -ceq $row.sha256) ('0.44.0 file '+$row.path)
    }
    $oldBinds=Read-PaPresetJson (Zip-Text $legacy 'presets/pa-binds.json')
    $oldSettings=Read-PaPresetJson (Zip-Text $legacy 'presets/pa-settings.json')
    $oldBaseline=Read-PaPresetJson (Zip-Text $legacy 'presets/baseline.json')
    $oldRuntimeWorker=Join-Path $oldML 'resource/pa26/updater/pa26-update.ps1'
    Write-Part $oldML 'binds' $oldBinds
    Write-Part $oldML 'settings' $oldSettings.settings
    Write-Part $oldML 'notes' $oldBaseline.notes
    [IO.File]::WriteAllText((Join-Path $oldML 'config/police_assistant_2026.ini'),(Get-PaPresetIni $oldSettings.config))
}finally{$legacy.Dispose()}
$manifest=Read-PaJson (Join-Path $release 'INSTALL_MANIFEST.json')
$author=Read-PaAuthorPresets $release $manifest
$officialBinds=$author['pa-binds'].bindings
$officialSettings=$author['pa-settings'].settings.data
$stateFolder='config\police_assistant_2026_legacy_0452\'

$ml=New-Game 'fresh' $false
Install $ml|Out-Null
Check ((Read-Part $ml 'binds').bindings.Count -eq 83) 'clean install has 83 official bindings'
Check ((Read-Part $ml 'notes').notes.Count -eq 2) 'clean install has two sample notes'
Check ((Read-Part $ml 'settings').data.settings.help.welcome) 'only new installation arms welcome'
Check (-not [IO.Directory]::Exists((Get-PaLegacyStateRoot $ml))) 'no legacy backup during fresh install'
Record 'fresh install and onboarding seed'

$ml=New-Game 'stock'
$before=Snapshot $ml
$preview=Install $ml -PreviewLegacyPresets
Check ($preview.state -ceq 'offer' -and $preview.review.updated.Count -eq 83 -and $preview.review.personal.Count -eq 0) 'recognized tagged 0.44.0 and all its official entries'
Assert-Snapshot $ml $before
Check ((Get-PaLegacyReviewText $preview.review).Contains('Обновлённые штатные записи')) 'expanded review can display old and new Russian RP text'
Install $ml -LegacyPreview $preview.token|Out-Null
$actual=Read-Part $ml 'binds'
Check ($actual.bindings.Count -eq 83) 'untouched 0.44.0 gets 83 official entries without duplicates'
foreach($binding in $officialBinds){
    $row=@($actual.bindings|Where-Object author_ref -CEQ $binding.author_ref)[0]
    Check ($row.script -ceq $binding.script -and $row.wheel_group -ceq $binding.wheel_group -and $row.wheel_car_group -ceq $binding.wheel_car_group) ('official RP and wheels '+$binding.author_ref)
}
Check (-not (Read-Part $ml 'settings').data.settings.help.welcome) 'legacy installation does not arm fresh onboarding'
Check ((Get-PaLegacyReceipt (Get-PaLegacyStateRoot $ml)).migration -ceq $script:PaLegacyMigrationId) 'versioned completed receipt'
Record 'tagged legacy defaults, preview and commit'

$ml=New-Game 'mine'
$b=Read-Part $ml 'binds'
$s=Read-Part $ml 'settings'
$notes=Read-Part $ml 'notes'
$mine=@($b.bindings|Where-Object id -EQ 5)[0]
$mine.script='/me старое редактирование штатного сценария'
$mine.favorite=$true
$mine.shortcut=@{key=0x74;alt=$false;ctrl=$true;shift=$false}
$collision=@($b.bindings|Where-Object id -EQ 88)[0]
$collision.name='Личная коллекция 88'
$collision.category='Моя отдельная коллекция'
$collision.command='pa26_my_collection'
$collision.command_alias='add'
$collision.script='/me личный сценарий в пользовательской коллекции'
$collision.wheel_visible=$false
$collision.wheel_car_visible=$true
$collision.favorite=$true
$collision.shortcut=@{key=0x73;alt=$false;ctrl=$false;shift=$false}
$extra=Read-PaPresetJson (Write-PaPresetJson $collision)
$extra.id=110;$extra.name='Второй личный';$extra.command='pa26_my_second';$extra.command_alias='mysecond';$extra.shortcut=@{key=0x76;alt=$true;ctrl=$false;shift=$false}
$b.bindings=@($b.bindings)+@($extra);$b.next_id=111
$s.data.profile.gender='female';$s.data.profile.name='Тестовый Профиль';$s.data.profile.callsign='TEST-12'
$s.data.assist.open_shortcut=@{key=0x75;alt=$false;ctrl=$false;shift=$false}
$s.data.settings.opacity=.64
$s.data.settings.wheel_names.custom='Мой прежний сектор'
$s.data.settings.window_layout.windows=@{
    main=@{x=30;y=40;width=1000;height=720;displayW=1366;displayH=768};
    assist=@{x=600;y=65;width=700;height=650;displayW=1366;displayH=768}
}
$s.data.settings.manual_actions.rules.cuff.rp='/me редактирование стандартной команды'
$s.data.settings.manual_actions.rules['myradio']=@{enabled=$true;prefer_bind=$false;rp='/me отдельный личный шаблон'}
$notes.notes[0].body='Личная заметка с ё и тире — сохраняется побайтно.'
Write-Part $ml 'binds' $b;Write-Part $ml 'settings' $s;Write-Part $ml 'notes' $notes
$notesHash=Get-PaHash (Personal-Path $ml 'notes')
$preview=Install $ml -PreviewLegacyPresets
Check ($preview.review.personal.Count -eq 2 -and $preview.review.conflicts.Count -ge 2) 'preview reports ID and alias conflict'
Install $ml -LegacyPreview $preview.token|Out-Null
$after=Read-Part $ml 'binds';$settings=(Read-Part $ml 'settings').data
$own=@($after.bindings|Where-Object id -EQ 88)[0]
$official=@($after.bindings|Where-Object {$_['author_ref'] -ceq 'A88'})[0]
$edited=@($after.bindings|Where-Object {$_['author_ref'] -ceq 'A05'})[0]
Check ($own.script -ceq $collision.script -and $own.category -ceq $collision.category -and $own.command_alias -ceq 'add') 'personal binding wins ID and alias conflicts'
Check ($own.wheel_visible -and $own.wheel_group -ceq 'custom' -and $own.wheel_car_visible -and $own.wheel_car_group -ceq 'custom') 'personal binding remains reachable from its own section and vehicle scope'
Check ($own.favorite -and $own.shortcut.key -eq 0x73 -and $settings.assist.open_shortcut.key -eq 0x75) 'personal F4 wins over new default, old assistant F6 preserved'
Check ($official.id -ne 88 -and $official.command_alias -ceq '') 'official binding retains contents with safe new ID and no conflicting alias'
Check ($edited.script -ceq @($officialBinds|Where-Object author_ref -CEQ 'A05')[0].script) 'edited official RP replaced'
Check ($edited.favorite -and $edited.shortcut.ctrl -and $edited.shortcut.key -eq 0x74) 'edited official favorite and separate hotkey kept'
Check ($settings.profile.gender -ceq 'female' -and $settings.profile.name -ceq 'Тестовый Профиль' -and $settings.profile.callsign -ceq 'TEST-12') 'female profile and identity retained'
Check ($settings.settings.opacity -eq $officialSettings.settings.opacity -and $settings.settings.wheel_names.custom -ceq $officialSettings.settings.wheel_names.custom) 'official UI settings and stock wheel names refreshed'
Check (Test-PaPresetEqual $s.data.settings.window_layout.windows $settings.settings.window_layout.windows) 'F4/F9 geometry retained'
Check ($settings.settings.manual_actions.rules.cuff.rp -ceq $officialSettings.settings.manual_actions.rules.cuff.rp) 'official manual RP refreshed'
Check ($settings.settings.manual_actions.rules.myradio.rp -ceq $s.data.settings.manual_actions.rules.myradio.rp) 'independent manual RP retained'
Check ((Get-PaHash (Personal-Path $ml 'notes')) -ceq $notesHash) 'notes exactly preserved'
Record 'edited defaults, independent RP, geometry, ID and alias collision, personal data'

$receipt=Get-PaLegacyReceipt (Get-PaLegacyStateRoot $ml)
$private=Snapshot (Join-Path $ml 'config')
Install $ml|Out-Null
Assert-Snapshot (Join-Path $ml 'config') $private
Check ((Get-PaLegacyReceipt (Get-PaLegacyStateRoot $ml)).job -ceq $receipt.job) 'reinstall does not reapply preset'
Record 'idempotent manual reinstall'

$ml=New-Game 'combo'
$shared=Read-PaPresetJson (Write-PaPresetJson $oldBaseline.settings.data)
$shared.bindings=$oldBaseline.binds.bindings
$shared.next_id=$oldBaseline.binds.next_id
$shared.wheel=$oldBaseline.binds.wheel
$shared.notes=$oldBaseline.notes.notes
$shared.notes[0].body='Заметка из прежней общей библиотеки'
$shared.next_note_id=$oldBaseline.notes.next_note_id
foreach($name in @('settings','binds','notes')){[IO.File]::Delete((Personal-Path $ml $name))}
Write-Part $ml 'library' $shared
$oldLibraryHash=Get-PaHash (Personal-Path $ml 'library')
$preview=Install $ml -PreviewLegacyPresets
Check ($preview.review.updated.Count -eq 6 -and $preview.review.added.Count -eq 77) 'legacy built-in defaults identified separately from author file'
Install $ml -LegacyPreview $preview.token|Out-Null
Check ((Read-Part $ml 'binds').bindings.Count -eq 83) 'legacy common library received official preset'
Check ((Read-Part $ml 'notes').notes[0].body -ceq $shared.notes[0].body) 'personal note extracted from common library'
Check ((Get-PaHash (Personal-Path $ml 'library')) -ceq $oldLibraryHash) 'original common library untouched'
Record 'combined legacy library and independent personal notes'

$ml=New-Game 'skip'
$private=Snapshot (Join-Path $ml 'config')
Install $ml -SkipLegacyPresets|Out-Null
Assert-Snapshot (Join-Path $ml 'config') $private
Check (-not [IO.Directory]::Exists((Get-PaLegacyStateRoot $ml))) 'decline creates no legacy journal'
Record 'migration opt-out'

$ml=New-Game 'm45' $false
foreach($name in @('police_assistant_2026.lua','lib/pa26_core.lua')){
    $to=Get-PaSetupPath $ml $name
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))|Out-Null
    [IO.File]::Copy((Join-Path $release ('../Police-Assistant-2026-v0.45.1-dev/moonloader/'+$name)),$to)
}
Copy-Item -LiteralPath (Join-Path $oldML 'config') -Destination $ml -Recurse
$private=Snapshot (Join-Path $ml 'config')
Check ((Install $ml -PreviewLegacyPresets).state -ceq 'none') '0.45.1 is not a legacy transition'
Install $ml|Out-Null
Assert-Snapshot (Join-Path $ml 'config') $private
Record 'manual 0.45.1 upgrade preserves config'

$ml=New-Game 'badver'
[IO.File]::AppendAllText((Join-Path $ml 'lib/pa26_core.lua'),'-- changed metadata')
$private=Snapshot (Join-Path $ml 'config')
Check ((Install $ml -PreviewLegacyPresets).state -ceq 'none') 'filename and legacy entrypoint alone do not authorize migration'
[IO.File]::Delete((Join-Path $ml 'lib/pa26_core.lua'))
Check ((Install $ml -PreviewLegacyPresets).state -ceq 'none') 'missing version metadata does not authorize migration'
Install $ml|Out-Null
Assert-Snapshot (Join-Path $ml 'config') $private
Record 'missing and corrupt version metadata'

$ml=New-Game 'badcfg'
[IO.File]::WriteAllText((Personal-Path $ml 'settings'),'{truncated')
$before=Snapshot $ml
Reject {Install $ml} 'Invalid|JSON|Перенос|Недопустим|Неверн'
Assert-Snapshot $ml $before
$manifestBad=Read-PaJson (Join-Path $release 'INSTALL_MANIFEST.json')
@($manifestBad.preset_files|Where-Object path -CEQ 'presets/pa-binds.json')[0].sha256='0'*64
Reject {Get-PaLegacyPresetPlan $release $ml $manifestBad '' $false} 'Preset source integrity'
Assert-Snapshot $ml $before
Record 'invalid input or preset refused before writes'

$ml=New-Game 'stale'
$preview=Install $ml -PreviewLegacyPresets
[IO.File]::AppendAllText((Personal-Path $ml 'notes'),"`r`n")
$before=Snapshot $ml
Reject {Install $ml -LegacyPreview $preview.token} 'после предпросмотра'
Assert-Snapshot $ml $before
Record 'stale preview rejected'

$ml=New-Game 'fail'
$before=Snapshot $ml
Reject {Install $ml -TestFailAfter 3} 'Injected installation failure'
Assert-Snapshot $ml $before $stateFolder
Check (-not (Get-PaLegacyReceipt (Get-PaLegacyStateRoot $ml))) 'failure has no completion receipt'
$backup=@(Get-ChildItem -LiteralPath (Get-PaLegacyStateRoot $ml) -Directory)[0].FullName
$personal=Get-Content -LiteralPath (Join-Path $backup 'PERSONAL.json') -Raw|ConvertFrom-Json
foreach($row in $personal){Check ((Get-PaHash (Join-Path $backup $row.backup_file)) -eq $row.sha256) 'durable personal backup verified'}
Record 'rollback after partial preset replacement'

$ml=New-Game 'crash'
$before=Snapshot $ml
Reject {Install $ml -TestFailAfter 20 -TestInterrupt} 'Injected installer interruption'
Check ([IO.File]::Exists((Get-PaLegacyMarker $ml))) 'interrupted migration activates bootstrap gate'
Check (-not (Get-PaLegacyReceipt (Get-PaLegacyStateRoot $ml))) 'interrupted migration has no completion receipt'
Check ((Install $ml -PreviewLegacyPresets).state -ceq 'recover') 'next manual setup detects its journal'
Install $ml|Out-Null
Assert-Snapshot $ml $before $stateFolder
Check (-not [IO.File]::Exists((Get-PaLegacyMarker $ml))) 'recovery clears the gate after restoration'
Check ((Install $ml -PreviewLegacyPresets).state -ceq 'offer') 'recovered legacy install can be retried'
Record 'interrupted install and next-launch recovery'

# This worker and its transport remain byte-identical to 0.45.1.
$archive=Join-Path $release 'pa26-update.zip'
$asset=@{version='0.45.2';sha256=(Get-PaHash $archive);size=(Get-Item -LiteralPath $archive).Length}
$script:PaBase=Join-Path $root 'worker'
function Get-PaGameRunning{return $false}
function New-Job([string]$ML){
    $job=Join-Path $script:PaBase ('jobs/'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($job)|Out-Null
    Initialize-PaPaths $ML $job
    return Join-Path $job 'package'
}
$ml=New-Game 'auto'
$private=Snapshot (Join-Path $ml 'config')
$folder=New-Job $ml
& {
    $base=$script:PaBase
    . $oldRuntimeWorker -Mode Library
    $script:PaBase=$base
    Initialize-PaPaths $ml ([IO.Path]::GetDirectoryName($folder))
    Reject {Expand-PaPackage $archive $folder $asset} 'unowned_payload_file'
}
Assert-Snapshot (Join-Path $ml 'config') $private
$folder=New-Job $ml
$package=Expand-PaPackage $archive $folder $asset
Check (@($package.files|Where-Object path -Match '/config/|pa-legacy|presets/').Count -eq 0) 'automatic update carries no legacy tools or personal data'
Invoke-PaTransaction $folder $package
Check ((Get-PaCurrent) -ceq '0.45.2') 'compatible updater can update without migration'
Assert-Snapshot (Join-Path $ml 'config') $private
Record 'automatic 0.44.0 never migrates, old worker safely refuses'

$ml=Join-Path $root 'mine/MoonLoader'
$private=Snapshot (Join-Path $ml 'config')
$folder=New-Job $ml
$package=Expand-PaPackage $archive $folder $asset
$package.version='0.45.3'
foreach($name in @('MoonLoader/police_assistant_2026.lua','MoonLoader/lib/pa26_core.lua')){
    $path=Get-PaSetupPath $folder $name
    [IO.File]::WriteAllText($path,([IO.File]::ReadAllText($path).Replace('0.45.2','0.45.3')))
    $row=@($package.files|Where-Object path -CEQ $name)[0]
    $row.sha256=Get-PaHash $path;$row.size=(Get-Item -LiteralPath $path).Length
}
Check ((Get-PaLegacyOffer $release $oldML '0.45.3') -ceq 'none') 'future installer gate excludes even exact legacy source'
Invoke-PaTransaction $folder $package
Check ((Get-PaCurrent) -ceq '0.45.3') 'future version worker transaction completed'
Assert-Snapshot (Join-Path $ml 'config') $private
Record 'simulated 0.45.3 update preserves personal configuration and receipt'

Write-PaJson (Join-Path $PSScriptRoot 'LEGACY_INSTALL0452.json') @{
    status='passed';checks=$checks;scenarios=$cases.ToArray();game_started=$false;live_game_written=$false;legacy_archive=$oldSha
}
Write-Output ('Legacy installer: '+$checks+' checks passed.')
