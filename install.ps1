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
    [switch]$SkipAuthorSettings,
    [switch]$SkipLegacyPresets,
    [switch]$PreviewLegacyPresets,
    [switch]$PreviewCefContract,
    [string]$LegacyPreview = '',
    [switch]$TestInterrupt,
    [switch]$RequireCef
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if($Interactive -and -not $VerifyOnly -and -not $PreviewCefContract){
    & (Join-Path $PSScriptRoot 'tools/pa-start.ps1') -Mode Install
    return
}
$paChanged=@();$paRollbackCompleted=$false;$paRecoveryRequired=$false;$paProgressPath='';$paManifest=$null
if($ProgressFile -and -not $VerifyOnly -and -not $PreviewCefContract){
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
    Set-PaInstallProgress 'failed' 0 $_.Exception.Message $true (-not $paRecoveryRequired -and ($paRollbackCompleted -or $paChanged.Count -eq 0))
    break
}
Set-PaInstallProgress 'checking' 2 'Проверяю установочный архив и выбранную папку.'
$paSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'moonloader'))
$paManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALL_MANIFEST.json') -Raw | ConvertFrom-Json
$paSetupAllow=@('tools/pa-setup.ps1','tools/pa-setup-window.ps1','tools/pa-start.ps1','tools/pa-seed-presets.ps1','DEPENDENCIES.json',
    'tools/pa-legacy-0440.json','tools/pa-legacy-migration.ps1','tools/pa-legacy-lua.ps1','tools/pa-legacy-presets.lua')
if(@($paManifest.setup_files).Count -ne $paSetupAllow.Count){throw 'Missing setup manifest.'}
$paSetupSeen=@{}
foreach($paRow in $paManifest.setup_files){
 if($paRow.path -cnotin $paSetupAllow -or $paSetupSeen.ContainsKey($paRow.path)){throw 'Unexpected setup file.'}
 $paSetupSeen[$paRow.path]=$true
 $paFile=Join-Path $PSScriptRoot $paRow.path.Replace('/','\')
 if((Get-FileHash -LiteralPath $paFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne $paRow.sha256){throw 'Setup integrity failed.'}
}
. (Join-Path $PSScriptRoot 'tools/pa-setup.ps1')
. (Join-Path $PSScriptRoot 'tools/pa-seed-presets.ps1')
. (Join-Path $PSScriptRoot 'tools/pa-legacy-migration.ps1')
$paWorker=Get-PaSetupPath $paSource 'resource/pa26/updater/pa26-update.ps1'
$paWorkerRow=@($paManifest.files|Where-Object path -CEQ 'resource\pa26\updater\pa26-update.ps1')
if($paWorkerRow.Count -ne 1 -or (Get-FileHash -LiteralPath $paWorker -Algorithm SHA256).Hash.ToLowerInvariant() -cne $paWorkerRow[0].sha256){throw 'Installer transaction library integrity failed.'}
. $paWorker -Mode Library
$paDefault=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher\game\MoonLoader'
if(-not $DestinationRoot){$DestinationRoot=$paDefault}
$paTestRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests\install-sandbox')).TrimEnd('\')
$paInput=[IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$paTest=$paInput.StartsWith($paTestRoot+'\',[StringComparison]::OrdinalIgnoreCase)
$paDestination=Resolve-PaSetupRoot $DestinationRoot $paTest
if($PreviewCefContract){
    Get-PaSetupCefContract $PSScriptRoot $paDestination $paManifest|ConvertTo-Json -Depth 8 -Compress
    return
}
if(($TestFailAfter -ne 0 -or $TestInterrupt) -and -not $paTest){throw 'Failure injection is allowed only in the test sandbox.'}
if($TestInterrupt -and $TestFailAfter -lt 1){throw 'Interruption requires a write count.'}
if($LegacyPreview -and $LegacyPreview -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid legacy preview token.'}
$paDependencyManifest=Read-PaDependencyManifest (Join-Path $PSScriptRoot 'DEPENDENCIES.json')
$paDependencyPlan=@()
$paOwned = @(
    'config\police_assistant_2026.ini',
    'lib\pa26_alerts.lua',
    'lib\pa26_assist_settings.lua',
    'lib\pa26_assist_ui.lua',
    'lib\pa26_author_controller.lua',
    'lib\pa26_author_defaults0460.lua',
    'lib\pa26_author_upgrade0460.lua',
    'lib\pa26_author_io.lua',
    'lib\pa26_author_merge.lua',
    'lib\pa26_author_presets.lua',
    'lib\pa26_author_rp.lua',
    'lib\pa26_author_store.lua',
    'lib\pa26_binder.lua',
    'lib\pa26_bindings.lua',
    'lib\pa26_case_forms.lua',
    'lib\pa26_case_ui.lua',
    'lib\pa26_cef_assets.lua',
    'lib\pa26_cef_compat.lua',
    'lib\pa26_cef_contract.lua',
    'lib\pa26_cef_job.lua',
    'lib\pa26_chat_bridge.lua',
    'lib\pa26_chat_perf.lua',
    'lib\pa26_chat_text.lua',
    'lib\pa26_colleagues.lua',
    'lib\pa26_command_policy.lua',
    'lib\pa26_config.lua',
    'lib\pa26_coord_share.lua',
    'lib\pa26_copilot.lua',
    'lib\pa26_copilot_incident.lua',
    'lib\pa26_copilot_settings.lua',
    'lib\pa26_copilot_ui.lua',
    'lib\pa26_core.lua',
    'lib\pa26_cruiser_assist.lua',
    'lib\pa26_custody_reports.lua',
    'lib\pa26_custody_settings.lua',
    'lib\pa26_custody_ui.lua',
    'lib\pa26_detention_timers.lua',
    'lib\pa26_dispatch.lua',
    'lib\pa26_dispatch_followups.lua',
    'lib\pa26_elapsed_clock.lua',
    'lib\pa26_evidence.lua',
    'lib\pa26_evidence_files.lua',
    'lib\pa26_executor.lua',
    'lib\pa26_fast_pt.lua',
    'lib\pa26_feedback.lua',
    'lib\pa26_field_briefings.lua',
    'lib\pa26_field_radio.lua',
    'lib\pa26_field_services.lua',
    'lib\pa26_field_settings.lua',
    'lib\pa26_field_ui.lua',
    'lib\pa26_fine_window.lua',
    'lib\pa26_gender_audit.lua',
    'lib\pa26_gender_catalog.lua',
    'lib\pa26_geometry.lua',
    'lib\pa26_ground_speech.lua',
    'lib\pa26_ground_window.lua',
    'lib\pa26_help.lua',
    'lib\pa26_hud.lua',
    'lib\pa26_icon_font.lua',
    'lib\pa26_icon_glyphs.lua',
    'lib\pa26_icons.lua',
    'lib\pa26_identity.lua',
    'lib\pa26_identity_ui.lua',
    'lib\pa26_important_data.lua',
    'lib\pa26_input.lua',
    'lib\pa26_interface_settings.lua',
    'lib\pa26_journal.lua',
    'lib\pa26_keyboard_layout.lua',
    'lib\pa26_knowledge.lua',
    'lib\pa26_knowledge_editor_ui.lua',
    'lib\pa26_knowledge_edits.lua',
    'lib\pa26_knowledge_important.lua',
    'lib\pa26_knowledge_important_ui.lua',
    'lib\pa26_knowledge_ui.lua',
    'lib\pa26_library.lua',
    'lib\pa26_local_life.lua',
    'lib\pa26_manual_actions.lua',
    'lib\pa26_manual_chat.lua',
    'lib\pa26_map_adapter.lua',
    'lib\pa26_map_grid.lua',
    'lib\pa26_map_ui.lua',
    'lib\pa26_mark_window.lua',
    'lib\pa26_menu.lua',
    'lib\pa26_nearby.lua',
    'lib\pa26_notifications.lua',
    'lib\pa26_operation_settings.lua',
    'lib\pa26_operation_ui.lua',
    'lib\pa26_operational.lua',
    'lib\pa26_operational_ui.lua',
    'lib\pa26_operations.lua',
    'lib\pa26_patrol.lua',
    'lib\pa26_patrol_event_settings.lua',
    'lib\pa26_patrol_event_ui.lua',
    'lib\pa26_patrol_events.lua',
    'lib\pa26_patrol_session.lua',
    'lib\pa26_patrol_settings.lua',
    'lib\pa26_patrol_ui.lua',
    'lib\pa26_pinned_note.lua',
    'lib\pa26_preferences.lua',
    'lib\pa26_procedure_flow.lua',
    'lib\pa26_procedure_input.lua',
    'lib\pa26_procedure_settings.lua',
    'lib\pa26_procedure_window.lua',
    'lib\pa26_radio_guard.lua',
    'lib\pa26_radio_text.lua',
    'lib\pa26_recovery.lua',
    'lib\pa26_report_context.lua',
    'lib\pa26_rp_context.lua',
    'lib\pa26_rp_context_ui.lua',
    'lib\pa26_rp_presets.lua',
    'lib\pa26_rp_settings.lua',
    'lib\pa26_rp_text.lua',
    'lib\pa26_rp_ui.lua',
    'lib\pa26_runtime.lua',
    'lib\pa26_sanctions.lua',
    'lib\pa26_screens.lua',
    'lib\pa26_server_commands.lua',
    'lib\pa26_settings_ui.lua',
    'lib\pa26_sha256.lua',
    'lib\pa26_shutdown.lua',
    'lib\pa26_startup.lua',
    'lib\pa26_stolen_bulletin.lua',
    'lib\pa26_studio.lua',
    'lib\pa26_target.lua',
    'lib\pa26_taser.lua',
    'lib\pa26_text_editor.lua',
    'lib\pa26_tracking_ui.lua',
    'lib\pa26_training.lua',
    'lib\pa26_ui_groups.lua',
    'lib\pa26_update_platform.lua',
    'lib\pa26_update_ui.lua',
    'lib\pa26_updater.lua',
    'lib\pa26_user_files.lua',
    'lib\pa26_vehicle.lua',
    'lib\pa26_vehicle_names.lua',
    'lib\pa26_vehicle_palette.lua',
    'lib\pa26_vehicle_settings.lua',
    'lib\pa26_vehicle_types.lua',
    'lib\pa26_vehicle_ui.lua',
    'lib\pa26_vehicle_world.lua',
    'lib\pa26_wanted_accounts.lua',
    'lib\pa26_wanted_catalog.lua',
    'lib\pa26_wanted_ui.lua',
    'lib\pa26_wanted_window.lua',
    'lib\pa26_weapon_warning.lua',
    'lib\pa26_weapons.lua',
    'lib\pa26_wheel.lua',
    'lib\pa26_wheel_edit.lua',
    'lib\pa26_wheel_order.lua',
    'lib\pa26_wheel_scope.lua',
    'lib\pa26_window_layout.lua',
    'lib\pa26_workspace.lua',
    'lib\pa26_zone_bounds.lua',
    'pa26_guard.lua',
    'police_assistant_2026.lua',
    'resource\pa26\banner-bmw-lamborghini.png',
    'resource\pa26\fonts\LICENSE.txt',
    'resource\pa26\fonts\fa-solid-900.ttf',
    'resource\pa26\fonts\manifest.json',
    'resource\pa26\knowledge-base.json',
    'resource\pa26\knowledge-policy.json',
    'resource\pa26\sidebar-police-assistant.png',
    'resource\pa26\updater\pa26-update.ps1',
    'resource\pa26\wanted-catalog.json'
)
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
$paLegacyOffer=Get-PaLegacyOffer $PSScriptRoot $paDestination $paManifest.release
if($PreviewLegacyPresets){
    $preview=@{state=$paLegacyOffer}
    if($paLegacyOffer -ceq 'offer'){
        $previewPlan=Get-PaLegacyPresetPlan $PSScriptRoot $paDestination $paManifest $DependencyCache ([bool]$FetchDependencies)
        $preview.token=$previewPlan.token;$preview.review=$previewPlan.review
    }
    Write-Output ([PSCustomObject]$preview)
    return
}
$paLock=$null
try {
$paLegacy=$false;$paLegacyJob=''
if(-not $VerifyOnly){
    $paLock=Open-PaManualInstallLock $paDestination $paTest $PSScriptRoot
    $paLegacyOffer=Get-PaLegacyOffer $PSScriptRoot $paDestination $paManifest.release
    $paRecoveryRequired=[IO.File]::Exists((Get-PaLegacyMarker $paDestination)) -or $paLegacyOffer -ceq 'recover'
    if($paLegacyOffer -ceq 'recover'){
        Assert-PaGameClosed
        $committed=Repair-PaLegacyTransaction $paDestination $paManifest $paDependencyManifest
        $paRecoveryRequired=$false
        $detail=if($committed){'Предыдущая установка проверена. Перенос уже завершён. Можно запускать GTA.'}
            else{'Прежняя версия и личные данные восстановлены. Запустите установщик снова, чтобы заново проверить перенос.'}
        Set-PaInstallProgress 'recovered' 100 $detail $true $true
        Write-Output $detail
        return
    }
    if($paRecoveryRequired){throw 'Сначала завершите обычное обновление PA и восстановление его файлов.'}
    $paLegacy=$paLegacyOffer -ceq 'offer' -and -not $SkipLegacyPresets
    if($LegacyPreview -and -not $paLegacy){throw 'Исходная версия изменилась после предпросмотра. Запустите установщик снова.'}
    if($TestInterrupt -and -not $paLegacy){throw 'Interruption is supported only for the legacy migration test.'}
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

# Optional launcher HUD integration. The setup preview uses the same verifier.
$paGameRoot=[IO.Path]::GetDirectoryName($paDestination)
$paKnownLauncher=$paDestination -ieq [IO.Path]::GetFullPath($paDefault)
$paCefCheck=Get-PaSetupCefContract $PSScriptRoot $paDestination $paManifest
$paCefStatus=Get-PaSetupCefStatus $paCefCheck
$paCefReason=switch($paCefStatus){
    'compatible'   {'contract_compatible_pending_runtime'}
    'incompatible' {'incompatible_contract_native_only'}
    'unavailable'  {'native_chat'}
    'failed'       {'verification_failed_native_only'}
}
$paInstallCef=$paCefStatus -ceq 'compatible'
if($paInstallCef){$paKnownLauncher=$true}
if($RequireCef -and -not $paInstallCef){throw ('CEF contract could not be verified: '+$paCefCheck.reason+'. Native-only installation remains available.')}
if($paCefStatus -in @('incompatible','failed')){Write-Output ('CEF unavailable; native PA only. Reason: '+$paCefCheck.reason+'. Original chat preserved.')}
if ($paInstallCef) {
    $paHtml=Get-PaPath $paGameRoot 'cef\assets\hud\index.html'
    $paMain=Get-PaPath $paGameRoot 'cef\assets\hud\main.js'
    $paCefRoot=[IO.Path]::GetDirectoryName($paHtml)
    # A launcher update between analysis and planning is never silently accepted.
    if((Get-FileHash -LiteralPath $paMain -Algorithm SHA256).Hash.ToLowerInvariant() -cne $paCefCheck.sha256){throw 'Launcher changed during CEF verification.'}
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
    $paOriginalHash=Get-PaByteHash $paOriginal
    if($paOriginalHash -cne $paCefCheck.html_sha256){throw 'Launcher HTML changed during CEF verification.'}
    $paUtf8=New-Object Text.UTF8Encoding($false,$true)
    $paText=$paUtf8.GetString($paOriginal)
    $paPatched=$paUtf8.GetBytes([PaCef0452.Contract]::InstallMarkup($paText))
    $paHash=Get-PaByteHash $paPatched
    $paPlan += [PSCustomObject]@{Relative='index.html';Source=$null;Target=$paHtml;SHA256=$paHash;Existed=$true;
        BeforeHash=$paOriginalHash;Skip=($paHash -eq $paOriginalHash);
        Root=$paCefRoot;BackupRelative='cef-hud\index.html';Content=$paPatched}
}

$paPreset=@{plan=@();replace=@{};summary=@{binds='disabled';settings='disabled'}}
if(-not $VerifyOnly){
 $paIniRow=@($paPlan|Where-Object Relative -CEQ 'config\police_assistant_2026.ini')[0]
 if($paLegacy){
    Assert-PaGameClosed
    Set-PaInstallProgress 'checking' 45 'Проверяю и объединяю авторские и личные сценарии PA.'
    $paPreset=Get-PaLegacyPresetPlan $PSScriptRoot $paDestination $paManifest $DependencyCache ([bool]$FetchDependencies)
    if($LegacyPreview -and $LegacyPreview -cne $paPreset.token){throw 'Личные файлы изменились после предпросмотра. Откройте установщик снова.'}
    if(@($paPreset.plan|Where-Object Relative -CEQ $paIniRow.Relative).Count){$paPlan=@($paPlan|Where-Object Relative -CNE $paIniRow.Relative)}
 }else{
    $paPreset=Get-PaPresetSeedPlan $PSScriptRoot $paDestination $paManifest (-not $SkipAuthorBinds) (-not $SkipAuthorSettings) $paIniRow
 }
 $paPlan+=@($paPreset.plan)
}
$paPlan=@($paPlan|Sort-Object @{Expression={if($_.Relative -ceq 'police_assistant_2026.lua'){1}else{0}}},@{Expression={$_.Target}})
if ($VerifyOnly) {
    $paPlan | Select-Object Relative,@{Name='Action';Expression={if ($_.Skip) {'Preserve existing INI'} elseif ($_.Existed) {'Backup and replace'} else {'Create'}}}
    return
}
Assert-PaGameClosed
Set-PaInstallProgress 'backup' 55 'Создаю резервные копии личных данных и прежних файлов PA.'
$paInstallId=[Guid]::NewGuid().ToString('N')
$paBackup=if($paLegacy){Get-PaSetupPath (Get-PaLegacyStateRoot $paDestination) ('backup-'+$paInstallId)}
    else{Join-Path $PSScriptRoot ('installation-backups\before-'+$paInstallId)}
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
 Copy-PaVerified $paPersonalItem.path $paPersonalCopy $paPersonalItem.sha256
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
        Copy-PaVerified $paItem.Target $paSaved $paItem.BeforeHash
    }
}
$paChanged = @()
$paStage = $null
try {
    if($paLegacy){
        Assert-PaGameClosed
        if((Get-PaLegacyOffer $PSScriptRoot $paDestination $paManifest.release) -cne 'offer'){throw 'Исходная версия изменилась перед установкой.'}
        $paLegacyJob='manual-0452-'+$paInstallId
        $paRecoveryRequired=$true
        Start-PaLegacyTransaction $paDestination $paLegacyJob $paPlan
    }
    foreach ($paItem in $paPlan) {
        Set-PaInstallProgress 'installing' (70+[int](23*$paChanged.Count/[Math]::Max(1,$paPlan.Count))) ('Устанавливаю: '+$paItem.Relative)
        if ($paItem.Skip) { continue }
        if($paInstallCef -and $paItem.Relative -in @('index.html','pa26-chat.js','pa26-chat-endpoint.js')){
            if((Get-FileHash -LiteralPath $paMain -Algorithm SHA256).Hash.ToLowerInvariant() -cne $paCefCheck.sha256){throw 'Launcher changed during installation; CEF transaction cancelled.'}
        }
        Assert-PaGameClosed
        Assert-PaPersonalUnchanged
        Get-PaPath $paItem.Root $paItem.Relative | Out-Null
        $paCurrent = Test-Path -LiteralPath $paItem.Target
        if ($paCurrent -ne $paItem.Existed -or ($paCurrent -and (Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.BeforeHash)) {
            throw ('Target changed during preparation: ' + $paItem.Relative)
        }
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($paItem.Target)) -Force | Out-Null
        $paStage = $paItem.Target + '.pa26-' + [Guid]::NewGuid().ToString('N') + '.tmp'
        if ($null -ne $paItem.Content) { Write-PaBytes $paStage $paItem.Content }
        else { Copy-PaVerified $paItem.Source $paStage $paItem.SHA256 }
        if ((Get-FileHash -LiteralPath $paStage -Algorithm SHA256).Hash -ne $paItem.SHA256) { throw 'Staged copy integrity failed.' }
        if ($paItem.Existed) { [IO.File]::Replace($paStage,$paItem.Target,[NullString]::Value) }
        else { [IO.File]::Move($paStage,$paItem.Target) }
        $paStage = $null
        $paChanged += $paItem
        if ((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.SHA256) { throw 'Installed file integrity failed.' }
        if ($paTest -and $TestFailAfter -gt 0 -and $paChanged.Count -eq $TestFailAfter) {
            if($TestInterrupt){throw 'Injected installer interruption; resume with the same manual installer.'}
            throw 'Injected installation failure.'
        }
    }
    Set-PaInstallProgress 'verifying_install' 95 'Проверяю все установленные файлы и сохранность личных данных.'
    Assert-PaGameClosed
    foreach($paItem in $paPlan | Where-Object {-not $_.Skip}){if((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.SHA256){throw 'Final installation verification failed.'}}
    foreach ($paItem in $paPlan | Where-Object Skip) {
        if ((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.BeforeHash) { throw 'Existing settings changed.' }
    }
    Assert-PaPersonalUnchanged
    if($paLegacy){
        Complete-PaLegacyTransaction $paDestination $paLegacyJob
        $paRecoveryRequired=$false
    }
} catch {
    $paFailure = $_
    if($TestInterrupt -and $paFailure.Exception.Message.StartsWith('Injected installer interruption')){throw $paFailure}
    Set-PaInstallProgress 'rollback' 70 'Восстанавливаю прежние файлы PA после ошибки.'
    Assert-PaGameClosed
    if ($paStage -and (Test-Path -LiteralPath $paStage)) { Remove-Item -LiteralPath $paStage }
    if($paLegacyJob){
        if([IO.File]::Exists((Get-PaSetupPath (Get-PaLegacyStateRoot $paDestination) 'pending.json'))){
            $null=Repair-PaLegacyTransaction $paDestination $paManifest $paDependencyManifest
        }
        $paRecoveryRequired=$false
        $paRollbackCompleted=$true
        throw $paFailure
    }
    foreach ($paItem in $paChanged) {
        if((Test-Path -LiteralPath $paItem.Target) -and (Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.SHA256){throw ('External edit during rollback; files and backup retained: '+$paBackup)}
        if ($paItem.Existed) { Copy-Item -LiteralPath (Get-PaPath $paBackup $paItem.BackupRelative) -Destination $paItem.Target -Force }
        elseif (Test-Path -LiteralPath $paItem.Target) { Remove-Item -LiteralPath $paItem.Target }
    }
    $paRollbackCompleted=$true
    throw $paFailure
}
if (-not $paTest) {
$paResult=[PSCustomObject]@{release=$paManifest.release;author_presets=$paPreset.summary;backup=$paBackup;changed=$paChanged.Count;cef_adapter_installed=[bool]$paInstallCef;cef_mode=$paCefReason;cef_diagnostics=$paCefCheck;dependencies_added=$paDependencyPlan.Count;destination=$paDestination;native_game_tested=$false}
$paResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALLATION_REPORT.json') -Encoding UTF8
}
Write-Output ('Installed and verified ' + $paChanged.Count + ' owned files. Backup: ' + $paBackup)

$paCefSummary=switch($paCefStatus){
    'compatible'   {' Контракт CEF совместим. Подтверждение связи ожидается при запуске игры.'}
    'incompatible' {' Контракт CEF несовместим. Установлены нативные модули PA, исходный чат сохранён.'}
    'failed'       {' Не удалось проверить CEF. Установлены нативные модули PA, исходный чат сохранён.'}
    'unavailable'  {''}
}
$paPresetSummary=if($paLegacy){' Штатные бинды и настройки обновлены. Личные записи сохранены.'}else{''}
Set-PaInstallProgress 'completed' 100 ('PA установлен и проверен.'+$paPresetSummary+$paCefSummary+' Можно запускать GTA. Резервная копия: '+$paBackup) $true $true
} finally {
    if($paLock){$paLock.Dispose()}
}
