[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [string]$DestinationRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher\game\MoonLoader'),
    [int]$TestFailAfter = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$paSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'moonloader'))
$paManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALL_MANIFEST.json') -Raw | ConvertFrom-Json
$paDestination = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$paReal = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher\game\MoonLoader'))
$paTestRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tests\install-sandbox')).TrimEnd('\')
$paTest = $paDestination.StartsWith($paTestRoot + '\',[StringComparison]::OrdinalIgnoreCase)
if ($paDestination -ne $paReal -and -not $paTest) { throw 'Destination must be the selected launcher or the bounded test sandbox.' }
if ($TestFailAfter -ne 0 -and -not $paTest) { throw 'Failure injection is allowed only in the test sandbox.' }
$paOwned = @('lib\pa26_startup.lua','lib\pa26_settings_ui.lua','lib\pa26_update_platform.lua','lib\pa26_updater.lua','lib\pa26_update_ui.lua','resource\pa26\updater\pa26-update.ps1','lib\pa26_core.lua','lib\pa26_map_grid.lua','lib\pa26_map_adapter.lua','lib\pa26_map_ui.lua','lib\pa26_nearby.lua','lib\pa26_config.lua','lib\pa26_runtime.lua','lib\pa26_hud.lua','lib\pa26_menu.lua',
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
    'lib\pa26_radio_text.lua','lib\pa26_vehicle.lua','lib\pa26_vehicle_settings.lua',
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
    if (@(Get-Process -Name gta_sa,gta-sa -ErrorAction SilentlyContinue).Count) { throw 'Close GTA before installation.' }
}
if (-not $paTest) {
    foreach ($paDependency in @('lib\mimgui\init.lua','lib\mimgui\imgui.lua','lib\encoding.lua')) {
        if (-not (Test-Path -LiteralPath (Get-PaPath $paDestination $paDependency))) { throw ('Missing existing dependency: ' + $paDependency) }
    }
}
$paPlan = @()
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
if (Test-Path -LiteralPath $paHtml) {
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

if ($VerifyOnly) {
    $paPlan | Select-Object Relative,@{Name='Action';Expression={if ($_.Skip) {'Preserve existing INI'} elseif ($_.Existed) {'Backup and replace'} else {'Create'}}}
    return
}
Assert-PaGameClosed
$paBackup = Join-Path $PSScriptRoot ('installation-backups\before-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $paBackup -Force | Out-Null
$paPlan | Select-Object * -ExcludeProperty Content | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $paBackup 'PLAN.json') -Encoding UTF8
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
        if ($paItem.Skip) { continue }
        Assert-PaGameClosed
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
    foreach ($paItem in $paPlan | Where-Object Skip) {
        if ((Get-FileHash -LiteralPath $paItem.Target -Algorithm SHA256).Hash -ne $paItem.BeforeHash) { throw 'Existing settings changed.' }
    }
} catch {
    $paFailure = $_
    if (-not $paTest -and @(Get-Process -Name gta_sa,gta-sa -ErrorAction SilentlyContinue).Count) { throw 'GTA started during installation. No more files were written; close GTA and rerun the installer. Backup: '+$paBackup }
    if ($paStage -and (Test-Path -LiteralPath $paStage)) { Remove-Item -LiteralPath $paStage }
    foreach ($paItem in $paChanged) {
        if ($paItem.Existed) { Copy-Item -LiteralPath (Get-PaPath $paBackup $paItem.BackupRelative) -Destination $paItem.Target -Force }
        elseif (Test-Path -LiteralPath $paItem.Target) { Remove-Item -LiteralPath $paItem.Target }
    }
    throw $paFailure
}
if (-not $paTest) {
$paResult=[PSCustomObject]@{release='0.38.0-dev';backup=$paBackup;changed=$paChanged.Count;cef_adapter_installed=(Test-Path -LiteralPath $paHtml);native_game_tested=$false}
$paResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALLATION_REPORT.json') -Encoding UTF8
}
Write-Output ('Installed and verified ' + $paChanged.Count + ' owned files. Existing INI preserved. Backup: ' + $paBackup)
