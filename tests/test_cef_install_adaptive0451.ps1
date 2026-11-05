param([string]$SourceHud=$env:PA_QA_HUD_SOURCE,[string]$BaselineInstaller,
    [ValidatePattern('^CEF_[A-Z0-9_]+\.json$')][string]$ReportName='CEF_ADAPTIVE_INSTALL0450.json')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'tools/pa-setup-window.ps1') -Library
$box=Join-Path $release ('tests/cef-contract-sandbox/clean-'+[guid]::NewGuid().ToString('N'))
$dependencies=Get-Content -LiteralPath (Join-Path $release 'DEPENDENCIES.json') -Raw|ConvertFrom-Json
$source=if($SourceHud){[IO.Path]::GetFullPath($SourceHud)}else{'C:\Users\35987\AppData\Local\Exsellent Launcher\game\cef\assets\hud'}
$tag='<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script>'
$original=[IO.File]::ReadAllText((Join-Path $source 'index.html')).Replace($tag,'')
function New-LauncherFixture([string]$Root) {
 $loader=Join-Path $Root 'MoonLoader';$page=Join-Path $Root 'cef/assets/hud'
 foreach($p in @($loader,$page,(Join-Path $loader 'config'))){[IO.Directory]::CreateDirectory($p)|Out-Null}
 foreach($name in @('gta_sa.exe','moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $Root $name),'fixture; never executed')}
 foreach($package in $dependencies.packages){foreach($row in $package.files){$p=Join-Path $loader $row.target;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null;[IO.File]::WriteAllText($p,'fixture; never loaded')}}
 [IO.File]::Copy((Join-Path $source 'main.js'),(Join-Path $page 'main.js'))
 [IO.File]::WriteAllText((Join-Path $page 'index.html'),$original,(New-Object Text.UTF8Encoding($false)))
}
New-LauncherFixture $box
$ml=Join-Path $box 'MoonLoader';$hud=Join-Path $box 'cef/assets/hud'
$main=Join-Path $hud 'main.js';$html=Join-Path $hud 'index.html'
$checks=0
function Check($ok,$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
$scenarios=@('fresh current launcher','reinstall','late-tag upgrade','private preservation','incompatible native fallback','strict rejection')
function Write-PrivateFixture([string]$Loader) {
 $files=@{}
 foreach($name in @('binds','settings','notes','profile')){
  $p=Join-Path $Loader ('config/police_assistant_2026_'+$name+'.json')
  [IO.File]::WriteAllText($p,'{"synthetic":"personal '+$name+'"}')
  $files[$p]=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
 }
 return $files
}
function Check-Preserved($Files) {
 foreach($p in $Files.Keys){Check ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ceq $Files[$p]) 'Personal data preserved'}
}
$mainHash=(Get-FileHash $main -Algorithm SHA256).Hash
function Install([string]$Installer=(Join-Path $release 'install.ps1'),[string]$Loader=$ml,[switch]$AuthorDefaults) {
 & $Installer -DestinationRoot $Loader -SkipAuthorBinds:(-not $AuthorDefaults) -SkipAuthorSettings:(-not $AuthorDefaults)|Out-Null
 return (Get-Content -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($Installer)) 'INSTALLATION_REPORT.json') -Raw|ConvertFrom-Json)
}
$preflight=Get-PaSetupPreflight $box
Check ($preflight.details.Contains('CEF совместим') -and $preflight.cef.runtime -ceq 'NOT_RUN') 'Preflight shows compatible with runtime pending'
$fresh=Install -AuthorDefaults
Check $fresh.cef_adapter_installed 'Fresh compatible unknown hash installs CEF automatically'
Check ($fresh.cef_diagnostics.state -eq 'CONTRACT_COMPATIBLE') 'Installation is provisional until runtime handshake'
Check ($fresh.cef_diagnostics.known -eq ($fresh.cef_diagnostics.sha256 -ceq 'c458636ad5201c00aaf1e21e80bbf7fa74670734fcd0f66c812d495c893bd410')) 'Reviewed old identity or verified structural profile'
Check ($fresh.cef_diagnostics.fingerprint -ceq $preflight.cef.fingerprint -and $fresh.cef_diagnostics.html_sha256 -ceq $preflight.cef.html_sha256) 'Installer and preflight agree on the reviewed files'
Check ($fresh.cef_diagnostics.runtime -eq 'NOT_RUN') 'Installer never pretends runtime verified'
$settings=Read-PaPresetJson ([IO.File]::ReadAllText((Join-Path $ml 'config/police_assistant_2026_settings.json')))
Check ($settings.data.settings.cef_chat_support -eq $true) 'Fresh author settings enable the chat bridge'
$patched=[IO.File]::ReadAllText($html)
Check (([regex]::Matches($patched,[regex]::Escape($tag))).Count -eq 1) 'One PA script tag'
Check ($patched.IndexOf($tag) -lt $patched.IndexOf('<script src="main.js">')) 'PA installed before incoming event registration'
Check ($patched.Replace($tag,'') -ceq $original) 'All non-PA HTML bytes retained'
Check ((Get-FileHash $main -Algorithm SHA256).Hash -ceq $mainHash) 'Original main unchanged'
Check ((Get-FileHash (Join-Path $hud 'pa26-chat.js') -Algorithm SHA256).Hash -ceq (Get-FileHash (Join-Path $release 'cef/assets/hud/pa26-chat.js') -Algorithm SHA256).Hash) 'Actual final adapter installed'
Check ((Get-FileHash (Join-Path $hud 'pa26-chat-endpoint.js') -Algorithm SHA256).Hash -ceq (Get-FileHash (Join-Path $release 'cef/assets/hud/pa26-chat-endpoint.js') -Algorithm SHA256).Hash) 'Actual endpoint script installed'
$private=Write-PrivateFixture $ml
Install|Out-Null
Check ([IO.File]::ReadAllText($html) -ceq $patched) 'Reinstall idempotent'
# Older installations placed the tag at the end. Upgrade repairs its position.
[IO.File]::WriteAllText($html,$original.Replace('</body>',$tag+'</body>'),(New-Object Text.UTF8Encoding($false)))
Install|Out-Null;Check ([IO.File]::ReadAllText($html) -ceq $patched) 'Upgrade repairs late PA tag without duplicating handlers'
Check-Preserved $private
# An unsupported update preserves existing HUD and PA assets exactly.
[IO.File]::AppendAllText($main,"`nthrow new Error('incompatible fixture');")
$unsupportedMain=(Get-FileHash $main -Algorithm SHA256).Hash
$adapter=(Get-FileHash (Join-Path $hud 'pa26-chat.js') -Algorithm SHA256).Hash
$preflight=Get-PaSetupPreflight $box
Check ($preflight.details.Contains('CEF несовместим') -and -not $preflight.cef.allowed) 'Preflight rejects the incompatible contract'
$fallback=Install
Check (-not $fallback.cef_adapter_installed) 'Incompatible contract chooses native-only'
Check ($fallback.cef_diagnostics.state -eq 'INCOMPATIBLE') 'Reason is an incompatible profile, not a dangerous hash'
Check ($fallback.cef_diagnostics.reason -ceq $preflight.cef.reason) 'Installer and preflight report the same refusal'
Check ([IO.File]::ReadAllText($html) -ceq $patched) 'Unsupported HTML left untouched'
Check ((Get-FileHash $main -Algorithm SHA256).Hash -ceq $unsupportedMain) 'Unsupported main left untouched'
Check ((Get-FileHash (Join-Path $hud 'pa26-chat.js') -Algorithm SHA256).Hash -ceq $adapter) 'Existing adapter not replaced on unsupported client'
$failed=$false;try{& (Join-Path $release 'install.ps1') -DestinationRoot $ml -VerifyOnly -RequireCef|Out-Null}catch{$failed=$true}
Check $failed 'RequireCef fails before writing on unsupported contract'
if($BaselineInstaller){
 Check ($fresh.cef_diagnostics.sha256 -like 'f6122*') 'The upgrade fixture is the reported launcher'
 $oldBox=Join-Path $box 'upgrade'
 New-LauncherFixture $oldBox
 $oldMl=Join-Path $oldBox 'MoonLoader';$oldHud=Join-Path $oldBox 'cef/assets/hud'
 $before=Install ([IO.Path]::GetFullPath($BaselineInstaller)) $oldMl
 Check ($before.release -ceq '0.45.2' -and -not $before.cef_adapter_installed) 'Real 0.45.2 installs in native-only mode'
 Check (-not (Test-Path -LiteralPath (Join-Path $oldHud 'pa26-chat.js'))) 'The old installation never wrote an adapter'
 $oldPrivate=Write-PrivateFixture $oldMl
 $after=Install -Loader $oldMl
 Check ($after.release -ceq $paSetupManifest.release -and $after.cef_adapter_installed) 'A full reinstall repairs a native-only 0.45.2 installation'
 Check ([IO.File]::ReadAllText((Join-Path $oldHud 'index.html')) -ceq $patched) 'Upgrade installs the same single tag as a clean install'
 Check ((Get-FileHash -LiteralPath (Join-Path $oldHud 'main.js') -Algorithm SHA256).Hash -ceq $mainHash) 'Upgrade preserves launcher main.js'
 Check-Preserved $oldPrivate
 $scenarios+= 'published 0.45.2 native-only to corrected local package with adapter'

 $missingBox=Join-Path $box 'missing'
 New-LauncherFixture $missingBox
 $missingHud=Join-Path $missingBox 'cef/assets/hud'
 [IO.File]::Delete((Join-Path $missingHud 'index.html'))
 $preflight=Get-PaSetupPreflight $missingBox
 Check ($preflight.details.Contains('CEF недоступен') -and $preflight.cef.reason -ceq 'files_unavailable') 'Missing page is reported separately'
 $missing=Install -Loader (Join-Path $missingBox 'MoonLoader')
 Check ($missing.cef_mode -ceq 'native_chat' -and -not $missing.cef_adapter_installed) 'Missing page permits native-only installation'
 Check (-not (Test-Path -LiteralPath (Join-Path $missingHud 'pa26-chat.js'))) 'Missing HUD is not patched'
 $scenarios+= 'missing HUD file falls back without modifying launcher files'

 $rollbackBox=Join-Path $release ('tests/install-sandbox/cef-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 New-LauncherFixture $rollbackBox
 $rollbackMl=Join-Path $rollbackBox 'MoonLoader';$rollbackHud=Join-Path $rollbackBox 'cef/assets/hud'
 $rollbackPrivate=Write-PrivateFixture $rollbackMl
 $failure=$null
 try {
  & (Join-Path $release 'install.ps1') -DestinationRoot $rollbackMl -RequireCef -SkipAuthorBinds -SkipAuthorSettings -TestFailAfter 3|Out-Null
 } catch { $failure=$_.Exception.Message }
 Check ($failure -eq 'Injected installation failure.') 'Failure injection reached the compatible CEF installation'
 Check ([IO.File]::ReadAllText((Join-Path $rollbackHud 'index.html')) -ceq $original) 'Rollback restores the original HTML'
 foreach($name in @('pa26-chat.js','pa26-chat-endpoint.js')) {
  Check (-not (Test-Path -LiteralPath (Join-Path $rollbackHud $name))) 'Rollback removes only newly installed PA assets'
 }
 Check ((Get-FileHash -LiteralPath (Join-Path $rollbackHud 'main.js') -Algorithm SHA256).Hash -ceq $mainHash) 'Rollback preserves launcher main.js'
 Check-Preserved $rollbackPrivate
 $scenarios+= 'injected CEF install failure and rollback'
}
@{status='passed';checks=$checks;game_started=$false;live_game_written=$false;
 installer_sha256=(Get-FileHash (Join-Path $release 'install.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();
 manifest_sha256=(Get-FileHash (Join-Path $release 'INSTALL_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant();
 hud_main_sha256=$fresh.cef_diagnostics.sha256;scenarios=$scenarios}|
 ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot $ReportName) -Encoding UTF8
Write-Output ('Adaptive CEF install/reinstall/fallback: '+$checks+' checks passed.')
