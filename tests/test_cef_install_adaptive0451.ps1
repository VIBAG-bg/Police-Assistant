param([string]$SourceHud=$env:PA_QA_HUD_SOURCE)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$box=Join-Path $release ('tests/cef-contract-sandbox/clean-'+[guid]::NewGuid().ToString('N'))
$ml=Join-Path $box 'MoonLoader';$hud=Join-Path $box 'cef/assets/hud'
foreach($p in @($ml,$hud,(Join-Path $ml 'config'))){[IO.Directory]::CreateDirectory($p)|Out-Null}
foreach($name in @('gta_sa.exe','moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $box $name),'fixture; never executed')}
$dependencies=Get-Content -LiteralPath (Join-Path $release 'DEPENDENCIES.json') -Raw|ConvertFrom-Json
foreach($package in $dependencies.packages){foreach($row in $package.files){$p=Join-Path $ml $row.target;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null;[IO.File]::WriteAllText($p,'fixture; never loaded')}}
$source=if($SourceHud){[IO.Path]::GetFullPath($SourceHud)}else{'C:\Users\35987\AppData\Local\Exsellent Launcher\game\cef\assets\hud'}
$tag='<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script>'
$main=Join-Path $hud 'main.js';$html=Join-Path $hud 'index.html'
[IO.File]::Copy((Join-Path $source 'main.js'),$main)
$original=[IO.File]::ReadAllText((Join-Path $source 'index.html')).Replace($tag,'')
[IO.File]::WriteAllText($html,$original,(New-Object Text.UTF8Encoding($false)))
$checks=0
function Check($ok,$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
$private=@{}
foreach($name in @('binds','settings','notes','profile')){$p=Join-Path $ml ('config/police_assistant_2026_'+$name+'.json');[IO.File]::WriteAllText($p,'PRIVATE fixture');$private[$p]=(Get-FileHash $p -Algorithm SHA256).Hash}
$mainHash=(Get-FileHash $main -Algorithm SHA256).Hash
function Install{ & (Join-Path $release 'install.ps1') -DestinationRoot $ml -SkipAuthorBinds -SkipAuthorSettings|Out-Null;return (Get-Content -LiteralPath (Join-Path $release 'INSTALLATION_REPORT.json') -Raw|ConvertFrom-Json) }
$fresh=Install
Check $fresh.cef_adapter_installed 'Fresh compatible unknown hash installs CEF automatically'
Check ($fresh.cef_diagnostics.state -eq 'CONTRACT_COMPATIBLE') 'Installation is provisional until runtime handshake'
Check (-not $fresh.cef_diagnostics.known) 'No manually whitelisted current SHA'
Check ($fresh.cef_diagnostics.runtime -eq 'NOT_RUN') 'Installer never pretends runtime verified'
$patched=[IO.File]::ReadAllText($html)
Check (([regex]::Matches($patched,[regex]::Escape($tag))).Count -eq 1) 'One PA script tag'
Check ($patched.IndexOf($tag) -lt $patched.IndexOf('<script src="main.js">')) 'PA installed before incoming event registration'
Check ($patched.Replace($tag,'') -ceq $original) 'All non-PA HTML bytes retained'
Check ((Get-FileHash $main -Algorithm SHA256).Hash -ceq $mainHash) 'Original main unchanged'
Check ((Get-FileHash (Join-Path $hud 'pa26-chat.js') -Algorithm SHA256).Hash -ceq (Get-FileHash (Join-Path $release 'cef/assets/hud/pa26-chat.js') -Algorithm SHA256).Hash) 'Actual final adapter installed'
Install|Out-Null
Check ([IO.File]::ReadAllText($html) -ceq $patched) 'Reinstall idempotent'
# Older installations placed the tag at the end. Upgrade repairs its position.
[IO.File]::WriteAllText($html,$original.Replace('</body>',$tag+'</body>'),(New-Object Text.UTF8Encoding($false)))
Install|Out-Null;Check ([IO.File]::ReadAllText($html) -ceq $patched) 'Upgrade repairs late PA tag without duplicating handlers'
foreach($p in $private.Keys){Check ((Get-FileHash $p -Algorithm SHA256).Hash -ceq $private[$p]) 'Personal data preserved'}
# An unsupported update preserves existing HUD and PA assets exactly.
[IO.File]::AppendAllText($main,"`nthrow new Error('incompatible fixture');")
$unsupportedMain=(Get-FileHash $main -Algorithm SHA256).Hash
$adapter=(Get-FileHash (Join-Path $hud 'pa26-chat.js') -Algorithm SHA256).Hash
$fallback=Install
Check (-not $fallback.cef_adapter_installed) 'Incompatible contract chooses native-only'
Check ($fallback.cef_diagnostics.state -eq 'INCOMPATIBLE') 'Reason is an incompatible profile, not a dangerous hash'
Check ([IO.File]::ReadAllText($html) -ceq $patched) 'Unsupported HTML left untouched'
Check ((Get-FileHash $main -Algorithm SHA256).Hash -ceq $unsupportedMain) 'Unsupported main left untouched'
Check ((Get-FileHash (Join-Path $hud 'pa26-chat.js') -Algorithm SHA256).Hash -ceq $adapter) 'Existing adapter not replaced on unsupported client'
$failed=$false;try{& (Join-Path $release 'install.ps1') -DestinationRoot $ml -VerifyOnly -RequireCef|Out-Null}catch{$failed=$true}
Check $failed 'RequireCef fails before writing on unsupported contract'
@{status='passed';checks=$checks;game_started=$false;live_game_written=$false;
 installer_sha256=(Get-FileHash (Join-Path $release 'install.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();
 manifest_sha256=(Get-FileHash (Join-Path $release 'INSTALL_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant();
 scenarios=@('fresh current launcher','reinstall','late-tag upgrade','private preservation','incompatible native fallback','strict rejection')}|
 ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'CEF_ADAPTIVE_INSTALL0450.json') -Encoding UTF8
Write-Output ('Adaptive CEF install/reinstall/fallback: '+$checks+' checks passed.')
