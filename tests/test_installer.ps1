Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$paRelease=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$paManifestBefore=(Get-FileHash -LiteralPath (Join-Path $paRelease 'INSTALL_MANIFEST.json') -Algorithm SHA256).Hash
$paInstallerBefore=(Get-FileHash -LiteralPath (Join-Path $paRelease 'install.ps1') -Algorithm SHA256).Hash
$paRoot=Join-Path $paRelease ('tests\install-sandbox\run-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $paRoot | Out-Null
function Snapshot([string]$root) {
    $result=@{}
    foreach($item in Get-ChildItem -LiteralPath $root -File -Recurse) { $result[$item.FullName.Substring($root.Length)]=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
    return $result
}
function Create-Case([string]$name,[bool]$cef) {
    $base=Join-Path $paRoot $name
    $ml=Join-Path $base 'MoonLoader'
    New-Item -ItemType Directory -Path (Join-Path $ml 'config') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026.ini'),'PERSONAL INI')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_library.json'),'PERSONAL BINDS')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_binds.json'),'PERSONAL binds.json')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_notes.json'),'PERSONAL notes.json')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_settings.json'),'PERSONAL settings.json')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_files_pending.json'),'PERSONAL files_pending.json')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_binds.json.bak'),'PERSONAL binds.json.bak')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_notes.json.rollback'),'PERSONAL notes.json.rollback')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_binds.json.pa26-previous'),'PERSONAL binds.json.pa26-previous')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_notes.json.pa26-next'),'PERSONAL notes.json.pa26-next')
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_knowledge_personal.json'),'PERSONAL knowledge_personal.json')
    [IO.File]::WriteAllText((Join-Path $ml 'unrelated.lua'),'UNRELATED')
    [IO.File]::WriteAllText((Join-Path $ml 'police_assistant_2026.lua'),'PREVIOUS PA')
    if($cef) {
        $hud=Join-Path $base 'cef\assets\hud'
        New-Item -ItemType Directory -Path $hud -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $hud 'index.html'),'<!doctype html><html><head><title>HUD</title></head><body><input id="chatInputField"><div id="chatInput"></div><script src="main.js"></script></body></html>')
        [IO.File]::WriteAllText((Join-Path $hud 'main.js'),'OFFICIAL HUD UNCHANGED')
    }
    return $base
}
$native=Create-Case 'native' $false
$nativeBefore=Snapshot $native
& (Join-Path $paRelease 'install.ps1') -DestinationRoot $native -VerifyOnly | Out-Null
$nativeAfter=Snapshot $native
if($nativeBefore.Count -ne $nativeAfter.Count){throw 'VerifyOnly wrote files'}
foreach($key in $nativeBefore.Keys){if($nativeBefore[$key] -ne $nativeAfter[$key]){throw 'VerifyOnly changed bytes'}}
$nativeOutput=@(& (Join-Path $paRelease 'install.ps1') -DestinationRoot (Join-Path $native 'MoonLoader'))
$nativeBackupLine=$nativeOutput|Where-Object {$_ -is [string] -and $_ -match '^Installed and verified \d+ owned files\..* Backup: (.+)$'}|Select-Object -Last 1
if(-not $nativeBackupLine -or $nativeBackupLine -notmatch ' Backup: (.+)$'){throw 'Installer did not return its backup identity'}
$nativeBackup=Get-Item -LiteralPath $Matches[1]
$personalMap=@((Get-Content -LiteralPath (Join-Path $nativeBackup.FullName 'PERSONAL.json') -Raw|ConvertFrom-Json))
foreach($key in $nativeBefore.Keys|Where-Object {$_ -like '*config\police_assistant_2026*'}){
 $relative=$key.Replace('\MoonLoader\','')
 $entry=@($personalMap|Where-Object relative -CEQ $relative)
 if($entry.Count -ne 1){throw 'Missing personal backup mapping'}
 $saved=Join-Path $nativeBackup.FullName $entry[0].backup_file
 if((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $nativeBefore[$key]){throw 'Personal backup mismatch'}
}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026.ini')) -ne 'PERSONAL INI') { throw 'INI changed' }
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_library.json')) -ne 'PERSONAL BINDS') { throw 'Library changed' }
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_binds.json')) -ne 'PERSONAL binds.json'){throw 'Personal binds.json changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_notes.json')) -ne 'PERSONAL notes.json'){throw 'Personal notes.json changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_settings.json')) -ne 'PERSONAL settings.json'){throw 'Personal settings.json changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_files_pending.json')) -ne 'PERSONAL files_pending.json'){throw 'Personal files_pending.json changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_binds.json.bak')) -ne 'PERSONAL binds.json.bak'){throw 'Personal binds.json.bak changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_notes.json.rollback')) -ne 'PERSONAL notes.json.rollback'){throw 'Personal notes.json.rollback changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_binds.json.pa26-previous')) -ne 'PERSONAL binds.json.pa26-previous'){throw 'Personal binds.json.pa26-previous changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_notes.json.pa26-next')) -ne 'PERSONAL notes.json.pa26-next'){throw 'Personal notes.json.pa26-next changed'}
if([IO.File]::ReadAllText((Join-Path $native 'MoonLoader\config\police_assistant_2026_knowledge_personal.json')) -ne 'PERSONAL knowledge_personal.json'){throw 'Personal knowledge_personal.json changed'}
if(Test-Path -LiteralPath (Join-Path $native 'cef')) { throw 'Native-only install created a launcher HUD' }
$cef=Create-Case 'cef' $true
$original=[IO.File]::ReadAllText((Join-Path $cef 'cef\assets\hud\index.html'))
& (Join-Path $paRelease 'install.ps1') -DestinationRoot (Join-Path $cef 'MoonLoader') | Out-Null
$patched=[IO.File]::ReadAllText((Join-Path $cef 'cef\assets\hud\index.html'))
$tag='<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script>'
if($patched.Replace($tag,'') -ne $original) { throw 'Patch changed other HUD content' }
& (Join-Path $paRelease 'install.ps1') -DestinationRoot (Join-Path $cef 'MoonLoader') | Out-Null
if([IO.File]::ReadAllText((Join-Path $cef 'cef\assets\hud\index.html')) -ne $patched) { throw 'Repeated patch duplicated the tag' }
foreach($failAfter in @(1,37,89,91,92,93,94,97,98,102,103,104)) {
    $case=Create-Case ('rollback-'+$failAfter) $true
    $before=Snapshot $case
    $failed=$false
    try { & (Join-Path $paRelease 'install.ps1') -DestinationRoot (Join-Path $case 'MoonLoader') -TestFailAfter $failAfter | Out-Null }
    catch { if($_.Exception.Message -notlike '*Injected installation failure*') { throw };$failed=$true }
    if(-not $failed) { throw 'Failure injection did not trigger' }
    $after=Snapshot $case
    if($after.Count -ne $before.Count) { throw 'Rollback left created files' }
    foreach($key in $before.Keys) { if($before[$key] -ne $after[$key]) { throw ('Rollback mismatch: '+$key) } }
}
if((Get-FileHash -LiteralPath (Join-Path $paRelease 'INSTALL_MANIFEST.json') -Algorithm SHA256).Hash -ne $paManifestBefore) { throw 'Manifest changed during installer test' }
if((Get-FileHash -LiteralPath (Join-Path $paRelease 'install.ps1') -Algorithm SHA256).Hash -ne $paInstallerBefore) { throw 'Installer changed during test' }
$result=[ordered]@{release=(Get-Content -LiteralPath (Join-Path $paRelease 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json).release;status='passed';native_install=$true;cef_install=$true;idempotent_patch=$true;preserved_personal_files=$true;personal_backups=$true;verify_only_readonly=$true;rollback_after=@(1,37,89,91,92,93,94,97,98,102,103,104);manifest_sha256=$paManifestBefore;installer_sha256=$paInstallerBefore;real_game_written=$false;sandbox=$paRoot}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $paRelease 'tests\INSTALLER_RESULTS.json') -Encoding UTF8
'Installer: native, CEF, repeated patch and twelve rollback points passed.'
