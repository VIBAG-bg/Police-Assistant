[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [string]$DestinationRoot = '',
    [switch]$Interactive,
    [switch]$FetchDependencies,
    [string]$DependencyCache = '',
    [int]$TestFailAfter = 0,
    [string]$ProgressFile = '',
    [switch]$SkipAuthorBinds,
    [switch]$SkipAuthorSettings
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if($Interactive -and -not $VerifyOnly){
    & (Join-Path $PSScriptRoot 'tools/pa-start.ps1') -Mode Install
    return
}
$paChanged=@();$paRollbackCompleted=$false;$paProgressPath='';$paManifest=$null
if($ProgressFile -and -not $VerifyOnly){
    $paProgressPath=[IO.Path]::GetFullPath($ProgressFile)
    $paUIRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'installation-backups/ui-jobs')).TrimEnd('\')
    if(-not $paProgressPath.StartsWith($paUIRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $paProgressPath.Substring($paUIRoot.Length+1) -cnotmatch '^[a-f0-9]{32}\\progress\.json$'){throw 'Invalid installation progress path.'}
    $paAncestor=$paProgressPath
    while($paAncestor){
        if((Test-Path -LiteralPath $paAncestor) -and ((Get-Item -LiteralPath $paAncestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Installation progress path is a link.'}
        $paAncestor=[IO.Path]::GetDirectoryName($paAncestor)
    }
    if(-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($paProgressPath)) -PathType Container)){throw 'Installation progress directory is missing.'}
}
function Set-PaInstallProgress([string]$Stage,[int]$Percent,[string]$Detail,[bool]$Terminal=$false,[bool]$Safe=$false){
    if(-not $paProgressPath){return}
    try{
        $row=@{product='police-assistant-setup';job=[IO.Path]::GetFileName([IO.Path]::GetDirectoryName($paProgressPath));stage=$Stage;percent=$Percent;detail=$Detail;terminal=$Terminal;safe=$Safe;pid=$PID;version=$(if($paManifest){$paManifest.release}else{''})}
        $temp=$paProgressPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        [IO.File]::WriteAllText($temp,($row|ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($paProgressPath)){[IO.File]::Replace($temp,$paProgressPath,[NullString]::Value)}else{[IO.File]::Move($temp,$paProgressPath)}
    }catch{} # Status display must not change the file transaction.
}
trap {
    Set-PaInstallProgress 'failed' 0 $_.Exception.Message $true ($paRollbackCompleted -or $paChanged.Count -eq 0)
    break
}
Set-PaInstallProgress 'checking' 2 'Проверяю установочный архив и выбранную папку.'
$paSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'moonloader'))
$paManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALL_MANIFEST.json') -Raw | ConvertFrom-Json
$paSetupAllow=@('tools/pa-setup.ps1','tools/pa-setup-window.ps1','tools/pa-start.ps1','tools/pa-seed-presets.ps1','DEPENDENCIES.json')
if(@($paManifest.setup_files).Count -ne 5){throw 'Missing setup manifest.'}
$paSetupSeen=@{}
foreach($paRow in $paManifest.setup_files){
 if($paRow.path -cnotin $paSetupAllow -or $paSetupSeen.ContainsKey($paRow.path)){throw 'Unexpected setup file.'}
 $paSetupSeen[$paRow.path]=$true
 $paFile=Join-Path $PSScriptRoot $paRow.path.Replace('/','\')
 if((Get-FileHash -LiteralPath $paFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne $paRow.sha256){throw 'Setup integrity failed.'}
}
. (Join-Path $PSScriptRoot 'tools/pa-setup.ps1')
. (Join-Path $PSScriptRoot 'tools/pa-seed-presets.ps1')
$paDefault=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher\game\MoonLoader'
if(-not $DestinationRoot){$DestinationRoot=$paDefault}
$paTestRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests\install-sandbox')).TrimEnd('\')
$paInput=[IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$paTest=$paInput.StartsWith($paTestRoot+'\',[StringComparison]::OrdinalIgnoreCase)
$paDestination=Resolve-PaSetupRoot $DestinationRoot $paTest
if($TestFailAfter -ne 0 -and -not $paTest){throw 'Failure injection is allowed only in the test sandbox.'}
$paDependencyManifest=Read-PaDependencyManifest (Join-Path $PSScriptRoot 'DEPENDENCIES.json')
$paDependencyPlan=@()
$paOwned = @('lib\pa26_detention_timers.lua','lib\pa26_operational_ui.lua','lib\pa26_operational.lua','lib\pa26_dispatch.lua','lib\pa26_copilot_settings.lua','lib\pa26_colleagues.lua','lib\pa26_copilot.lua','lib\pa26_copilot_ui.lua','lib\pa26_screens.lua','lib\pa26_author_io.lua','lib\pa26_author_presets.lua','lib\pa26_author_store.lua','lib\pa26_author_controller.lua','lib\pa26_startup.lua','lib\pa26_settings_ui.lua','lib\pa26_update_platform.lua','lib\pa26_updater.lua','lib\pa26_update_ui.lua','resource\pa26\updater\pa26-update.ps1','lib\pa26_core.lua','lib\pa26_map_grid.lua','lib\pa26_map_adapter.lua','lib\pa26_map_ui.lua','lib\pa26_nearby.lua','lib\pa26_config.lua','lib\pa26_runtime.lua','lib\pa26_hud.lua','lib\pa26_menu.lua',
    'lib\pa26_chat_bridge.lua','lib\pa26_manual_actions.lua','lib\pa26_cef_assets.lua','lib\pa26_chat_text.lua','lib\pa26_keyboard_layout.lua','lib\pa26_bindings.lua','lib\pa26_binder.lua','lib\pa26_executor.lua','lib\pa26_library.lua','lib\pa26_knowledge.lua','lib\pa26_knowledge_ui.lua',
    'lib\pa26_knowledge_edits.lua','lib\pa26_knowledge_editor_ui.lua','lib\pa26_recovery.lua','pa26_guard.lua',
    'lib\pa26_journal.lua','lib\pa26_studio.lua','lib\pa26_text_editor.lua','lib\pa26_feedback.lua','lib\pa26_workspace.lua','lib\pa26_target.lua','lib\pa26_wheel.lua',
    'lib\pa26_alerts.lua','lib\pa26_input.lua',
    'lib\pa26_preferences.lua','lib\pa26_patrol.lua','lib\pa26_weapons.lua','lib\pa26_taser.lua',
    'lib\pa26_radio_guard.lua','lib\pa26_weapon_warning.lua','lib\pa26_notifications.lua',
    'lib\pa26_patrol_settings.lua','lib\pa26_patrol_session.lua','lib\pa26_patrol_ui.lua',
    'lib\pa26_patrol_event_settings.lua','lib\pa26_patrol_events.lua','lib\pa26_patrol_event_ui.lua',
    'lib\pa26_identity.lua','lib\pa26_identity_ui.lua','lib\pa26_procedure_settings.lua',
    'lib\pa26_case_forms.lua','lib\pa26_case_ui.lua','lib\pa26_wanted_catalog.lua','lib\pa26_wanted_ui.lua','lib\pa26_user_files.lua','lib\pa26_wanted_accounts.lua','lib\pa26_window_layout.lua','lib\pa26_manual_chat.lua','lib\pa26_interface_settings.lua','lib\pa26_wanted_window.lua',
    'lib\pa26_operation_settings.lua','lib\pa26_operations.lua','lib\pa26_operation_ui.lua',
    'lib\pa26_radio_text.lua','lib\pa26_local_life.lua','lib\pa26_sanctions.lua','lib\pa26_procedure_input.lua','lib\pa26_procedure_window.lua','lib\pa26_fine_window.lua','lib\pa26_mark_window.lua','lib\pa26_ground_window.lua','lib\pa26_procedure_flow.lua','lib\pa26_vehicle_types.lua','lib\pa26_vehicle.lua','lib\pa26_vehicle_settings.lua',
    'lib\pa26_vehicle_world.lua','lib\pa26_vehicle_names.lua','lib\pa26_vehicle_palette.lua','lib\pa26_vehicle_ui.lua',
    'lib\pa26_assist_settings.lua','lib\pa26_assist_ui.lua','lib\pa26_training.lua',
    'lib\pa26_evidence.lua','lib\pa26_evidence_files.lua',
    'lib\pa26_rp_settings.lua','lib\pa26_rp_text.lua','lib\pa26_rp_ui.lua','lib\pa26_server_commands.lua',
    'lib\pa26_rp_presets.lua',
    'resource\pa26\banner-bmw-lamborghini.png','resource\pa26\sidebar-police-assistant.png',
    'resource\pa26\knowledge-base.json','resource\pa26\knowledge-policy.json','resource\pa26\wanted-catalog.json',
    'config\police_assistant_2026.ini','police_assistant_2026.lua')
if ($paManifest.files.Count -ne $paOwned.Count) { throw 'Unexpected manifest entries.' }
function Get-PaPath([string]$root,[string]$relative) {
    $paPath = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $paPath.StartsWith($root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped its approved root.' }
    $paAncestor = $paPath
    while ($paAncestor -and $paAncestor.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
        if ((Test-Path -LiteralPath $paAncestor) -and ((Get-Item -LiteralPath $paAncestor).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw ('Reparse-point path is not allowed: ' + $paAncestor)
        }
        $paAncestor = [IO.Path]::GetDirectoryName($paAncestor)
    }
    return $paPath
}
function Assert-PaGameClosed {
    if ($paTest) { return }
    while (@(Get-Process -Name gta_sa,gta-sa -ErrorAction SilentlyContinue).Count) {
        Set-PaInstallProgress 'paused' 55 'Закройте GTA. Установка продолжится после закрытия игры.'
        Start-Sleep -Milliseconds 500
    }
}
if(-not $paTest){
 $paMissing=@(Get-PaMissingDependencies $paDestination $paDependencyManifest)
 if($paMissing.Count){
  if($VerifyOnly){Write-Output ('Missing libraries: '+(($paMissing|ForEach-Object {$_.title}) -join ', '))}
  else{
   Assert-PaGameClosed
   if(-not $FetchDependencies){throw 'Нужны библиотеки. Запустите «Установить PA.cmd» или укажите -FetchDependencies. См. docs/INSTALLATION.md.'}
   if($Interactive){
    $paAnswer=[Windows.Forms.MessageBox]::Show(('Не хватает: '+(($paMissing|ForEach-Object {$_.title}) -join ', ')+'. Скачать проверенные библиотеки? Имеющиеся файлы и настройки не заменяются.'),'Police Assistant',[Windows.Forms.MessageBoxButtons]::OKCancel,[Windows.Forms.MessageBoxIcon]::Information)
    if($paAnswer -ne [Windows.Forms.DialogResult]::OK){throw 'Установка отменена до изменения файлов.'}
   }
   if(-not $DependencyCache){$DependencyCache=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PoliceAssistant2026\setup-cache'}
   Set-PaInstallProgress 'downloading' 15 'Скачиваю и проверяю недостающие библиотеки. Игра пока не изменяется.'
   $paDependencyPlan=@(Get-PaDependencyPlan $paDestination $paMissing $DependencyCache $true)
  }
 }
}
Set-PaInstallProgress 'verifying_package' 40 'Проверяю контрольные суммы файлов PA.'
$paPlan = @($paDependencyPlan)
foreach ($paRelative in $paOwned) {
    $paEntry = @($paManifest.files | Where-Object path -EQ $paRelative)
    if ($paEntry.Count -ne 1) { throw ('Missing or duplicate manifest path: ' + $paRelative) }
    $paFrom = Get-PaPath $paSource $paRelative
    $paTo = Get-PaPath $paDestination $paRelative
    if ((Get-FileHash -LiteralPath $paFrom -Algorithm SHA256).Hash -ne $paEntry[0].sha256) { throw ('Source changed after checks: ' + $paRelative) }
    $paExists = Test-Path -LiteralPath $paTo
    $paSkip = $paExists -and $paRelative -eq 'config\police_assistant_2026.ini'
    $paPlan += [PSCustomObject]@{Relative=$paRelative;Source=$paFrom;Target=$paTo;SHA256=$paEntry[0].sha256;
        Existed=$paExists;BeforeHash=$(if ($paExists) {(Get-FileHash -LiteralPath $paTo -Algorithm SHA256).Hash} else {$null});Skip=$paSkip;Root=$paDestination;BackupRelative=$paRelative;Content=$null}
}

# Optional launcher HUD integration: the official page receives one script tag.
# Its original bytes are backed up and restored on a failed transaction.
function Get-PaByteHash([byte[]]$bytes) {
    $paAlgorithm=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($paAlgorithm.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
    finally { $paAlgorithm.Dispose() }
}
$paGameRoot=[IO.Path]::GetDirectoryName($paDestination)
$paHtml=Get-PaPath $paGameRoot 'cef\assets\hud\index.html'
$paKnownLauncher=$paDestination -ieq [IO.Path]::GetFullPath($paDefault)
$paContract=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'CEF_CONTRACT.json') -Raw | ConvertFrom-Json
$paMain=Get-PaPath $paGameRoot 'cef\assets\hud\main.js'
if((Test-Path -LiteralPath $paMain -PathType Leaf) -and (Get-FileHash -LiteralPath $paMain -Algorithm SHA256).Hash -eq $paContract.hud_main_sha256){$paKnownLauncher=$true}
if ((Test-Path -LiteralPath $paHtml) -and ($paKnownLauncher -or $paTest)) {
    $paCefRoot=[IO.Path]::GetDirectoryName($paHtml)
    $paMain=Get-PaPath $paCefRoot 'main.js'
    $paContract=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'CEF_CONTRACT.json') -Raw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $paMain)) { throw 'Launcher HUD main.js is missing.' }
    if (-not $paTest -and (Get-FileHash -LiteralPath $paMain -Algorithm SHA256).Hash -ne $paContract.hud_main_sha256) {
        throw 'Launcher chat changed. Review its contract before applying the CEF adapter.'
    }
    if ($paManifest.cef_files.Count -ne 2) { throw 'Unexpected CEF manifest.' }
    foreach ($paRelative in @('pa26-chat.js','pa26-chat-endpoint.js')) {
        $paEntry=@($paManifest.cef_files | Where-Object path -EQ $paRelative)
        $paFrom=Get-PaPath ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'cef\assets\hud'))) $paRelative
        $paTo=Get-PaPath $paCefRoot $paRelative
        if ($paEntry.Count -ne 1 -or (Get-FileHash -LiteralPath $paFrom -Algorithm SHA256).Hash -ne $paEntry[0].sha256) { throw 'CEF source integrity failed.' }
        $paExists=Test-Path -LiteralPath $paTo
        $paPlan += [PSCustomObject]@{Relative=$paRelative;Source=$paFrom;Target=$paTo;SHA256=$paEntry[0].sha256;Existed=$paExists;
            BeforeHash=$(if ($paExists) {(Get-FileHash -LiteralPath $paTo -Algorithm SHA256).Hash} else {$null});Skip=$false;
            Root=$paCefRoot;BackupRelative=('cef-hud\'+$paRelative);Content=$null}
    }
    $paOriginal=[IO.File]::ReadAllBytes($paHtml)
    $paText=[Text.Encoding]::UTF8.GetString($paOriginal)
    if (-not $paText.Contains('id="chatInputField"') -or -not $paText.Contains('id="chatInput"')) { throw 'Unexpected launcher chat markup.' }
    $paMarker='<!-- PA26 CEF chat adapter -->'
    if ($paText.Contains($paMarker)) {
        if ([regex]::Matches($paText,[regex]::Escape($paMarker)).Count -ne 1 -or -not $paText.Contains('src="pa26-chat.js"')) { throw 'Existing CEF adapter tag needs review.' }
        $paPatched=$paOriginal
    } else {
        $paHead=[regex]::new('</head>',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($paHead.Matches($paText).Count -ne 1) { throw 'Unexpected HUD head element.' }
        $paPatched=[Text.Encoding]::UTF8.GetBytes($paHead.Replace($paText,$paMarker+'<script src="pa26-chat.js"></script></head>',1))
    }
    $paHash=Get-PaByteHash $paPatched
    $paPlan += [PSCustomObject]@{Relative='index.html';Source=$null;Target=$paHtml;SHA256=$paHash;Existed=$true;
        BeforeHash=(Get-PaByteHash $paOriginal);Skip=($paHash -eq (Get-PaByteHash $paOriginal));
        Root=$paCefRoot;BackupRelative='cef-hud\index.html';Content=$paPatched}
}

$paPreset=@{plan=@();replace=@{};summary=@{binds='disabled';settings='disabled'}}
if(-not $VerifyOnly){
 $paIniRow=@($paPlan|Where-Object Relative -CEQ 'config\police_assistant_2026.ini')[0]
 $paPreset=Get-PaPresetSeedPlan $PSScriptRoot $paDestination $paManifest (-not $SkipAuthorBinds) (-not $SkipAuthorSettings) $paIniRow
 $paPlan+=@($paPreset.plan)
}
$paPlan=@($paPlan|Sort-Object @{Expression={if($_.Relative -ceq 'police_assistant_2026.lua'){1}else{0}}},@{Expression={$_.Target}})
if ($VerifyOnly) {
    $paPlan | Select-Object Relative,@{Name='Action';Expression={if ($_.Skip) {'Preserve existing INI'} elseif ($_.Existed) {'Backup and replace'} else {'Create'}}}
    return
}
Assert-PaGameClosed
Set-PaInstallProgress 'backup' 55 'Создаю резервные копии личных данных и прежних файлов PA.'
$paBackup = Join-Path $PSScriptRoot ('installation-backups\before-' + [Guid]::NewGuid().ToString('N'))
Assert-PaSetupPlain $paBackup
New-Item -ItemType Directory -Path $paBackup -Force | Out-Null
$paBackupIndex=0
foreach($paItem in $paPlan){$paItem.BackupRelative='runtime\'+$paBackupIndex.ToString('D4')+'.bin';$paBackupIndex++}
$paPlan | Select-Object * -ExcludeProperty Content | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $paBackup 'PLAN.json') -Encoding UTF8
$paPersonal=@()
$paConfig=Get-PaPath $paDestination 'config'
$paDirectories=New-Object 'Collections.Generic.Queue[string]'
if(Test-Path -LiteralPath $paConfig){$paDirectories.Enqueue($paConfig)}
$paDirectoryCount=0
while($paDirectories.Count){
 $paDirectory=$paDirectories.Dequeue();Assert-PaSetupPlain $paDirectory
 $paDirectoryCount++;if($paDirectoryCount -gt 10000){throw 'Too many personal directories.'}
 foreach($paPersonalItem in Get-ChildItem -LiteralPath $paDirectory -Force){
  Assert-PaSetupPlain $paPersonalItem.FullName
  if($paPersonalItem.PSIsContainer){$paDirectories.Enqueue($paPersonalItem.FullName)}
  elseif($paPersonalItem.Name -like 'police_assistant_2026*'){
   $paPersonal+=@{path=$paPersonalItem.FullName;relative=$paPersonalItem.FullName.Substring($paDestination.Length+1);sha256=(Get-FileHash -LiteralPath $paPersonalItem.FullName -Algorithm SHA256).Hash}
  }
 }
}
$paPersonalIndex=0
foreach($paPersonalItem in $paPersonal){
 $paPersonalItem.backup_file='personal\'+$paPersonalIndex.ToString('D6')+'.bin';$paPersonalIndex++
 $paPersonalCopy=Get-PaPath $paBackup $paPersonalItem.backup_file
 New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($paPersonalCopy)) -Force|Out-Null
 Copy-Item -LiteralPath $paPersonalItem.path -Destination $paPersonalCopy
 if((Get-FileHash -LiteralPath $paPersonalCopy -Algorithm SHA256).Hash -ne $paPersonalItem.sha256){throw 'Personal backup integrity failed.'}
}
$paPersonal|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $paBackup 'PERSONAL.json') -Encoding UTF8
function Assert-PaPersonalUnchanged {
 foreach($paPersonalItem in $paPersonal){
  Assert-PaSetupPlain $paPersonalItem.path
  $expected=$paPersonalItem.sha256
  if($paPreset.replace.ContainsKey($paPersonalItem.path) -and @($paChanged|Where-Object Target -CEQ $paPersonalItem.path).Count){$expected=$paPreset.replace[$paPersonalItem.path]}
  if(-not (Test-Path -LiteralPath $paPersonalItem.path) -or (Get-FileHash -LiteralPath $paPersonalItem.path -Algorithm SHA256).Hash -ne $expected){throw 'Personal data changed externally; installation stopped.'}
 }
}
Assert-PaPersonalUnchanged
foreach ($paItem in $paPlan) {
    if ($paItem.Existed) {
        $paSaved = Get-PaPath $paBackup $paItem.BackupRelative
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($paSaved)) -Force | Out-Null
        Copy-Item -LiteralPath $paItem.Target -Destination $paSaved
        if ((Get-FileHash -LiteralPath $paSaved -Algorithm SHA256).Hash -ne $paItem.BeforeHash) { throw 'Backup integrity failed.' }
    }
}
$paChanged = @()
$paStage = $null
try {
    foreach ($paItem in $paPlan) {
        Set-PaInstallProgress 'installing' (70+[int](23*$paChanged.Count/[Math]::Max(1,$paPlan.Count))) ('Устанавливаю: '+$paItem.Relative)
        if ($paItem.Skip) { continue }
        Assert-PaGameClosed
        Assert-PaPersonalUnchanged
        Get-PaPath $paItem.Root $paItem.Relative | Out-Null
        $paCurrent = Test-Path -LiteralPath $paItem.Target
        if ($paCurrent -ne $paItem.Existed -or ($paCurrent -and (Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.BeforeHash)) {
            throw ('Target changed during preparation: ' + $paItem.Relative)
        }
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($paItem.Target)) -Force | Out-Null
        $paStage = $paItem.Target + '.pa26-' + [Guid]::NewGuid().ToString('N') + '.tmp'
        if ($null -ne $paItem.Content) { [IO.File]::WriteAllBytes($paStage,$paItem.Content) }
        else { Copy-Item -LiteralPath $paItem.Source -Destination $paStage }
        if ((Get-FileHash -LiteralPath $paStage -Algorithm SHA256).Hash -ne $paItem.SHA256) { throw 'Staged copy integrity failed.' }
        if ($paItem.Existed) { [IO.File]::Replace($paStage,$paItem.Target,[NullString]::Value) }
        else { [IO.File]::Move($paStage,$paItem.Target) }
        $paStage = $null
        $paChanged += $paItem
        if ((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.SHA256) { throw 'Installed file integrity failed.' }
        if ($paTest -and $TestFailAfter -gt 0 -and $paChanged.Count -eq $TestFailAfter) { throw 'Injected installation failure.' }
    }
    Set-PaInstallProgress 'verifying_install' 95 'Проверяю все установленные файлы и сохранность личных данных.'
    Assert-PaGameClosed
    foreach($paItem in $paPlan | Where-Object {-not $_.Skip}){if((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.SHA256){throw 'Final installation verification failed.'}}
    foreach ($paItem in $paPlan | Where-Object Skip) {
        if ((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.BeforeHash) { throw 'Existing settings changed.' }
    }
    Assert-PaPersonalUnchanged
} catch {
    $paFailure = $_
    Set-PaInstallProgress 'rollback' 70 'Восстанавливаю прежние файлы PA после ошибки.'
    Assert-PaGameClosed
    if ($paStage -and (Test-Path -LiteralPath $paStage)) { Remove-Item -LiteralPath $paStage }
    foreach ($paItem in $paChanged) {
        if((Test-Path -LiteralPath $paItem.Target) -and (Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.SHA256){throw ('External edit during rollback; files and backup retained: '+$paBackup)}
        if ($paItem.Existed) { Copy-Item -LiteralPath (Get-PaPath $paBackup $paItem.BackupRelative) -Destination $paItem.Target -Force }
        elseif (Test-Path -LiteralPath $paItem.Target) { Remove-Item -LiteralPath $paItem.Target }
    }
    $paRollbackCompleted=$true
    throw $paFailure
}
if (-not $paTest) {
$paResult=[PSCustomObject]@{release=$paManifest.release;author_presets=$paPreset.summary;backup=$paBackup;changed=$paChanged.Count;cef_adapter_installed=($paKnownLauncher -and (Test-Path -LiteralPath $paHtml));dependencies_added=$paDependencyPlan.Count;destination=$paDestination;native_game_tested=$false}
$paResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALLATION_REPORT.json') -Encoding UTF8
}
Write-Output ('Installed and verified ' + $paChanged.Count + ' owned files. Existing INI preserved. Backup: ' + $paBackup)

Set-PaInstallProgress 'completed' 100 ('PA установлен и проверен. Можно запускать GTA. Резервная копия: '+$paBackup) $true $true
