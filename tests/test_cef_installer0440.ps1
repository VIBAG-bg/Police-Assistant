Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
# Outside install-sandbox: exercise the real hash decision, not its old fixture shortcut.
$root=Join-Path $release ('tests/cef-contract-sandbox/'+[guid]::NewGuid().ToString('N'))
$ml=Join-Path $root 'MoonLoader';$hud=Join-Path $root 'cef/assets/hud'
foreach($p in @($ml,$hud)){[IO.Directory]::CreateDirectory($p)|Out-Null}
foreach($name in @('gta_sa.exe','moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $root $name),'fixture, never executed')}
$main=Join-Path $hud 'main.js';$html=Join-Path $hud 'index.html'
[IO.File]::WriteAllText($main,'unknown launcher version')
[IO.File]::WriteAllText($html,'<html><body>existing CEF<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script></body></html>')
$beforeMain=(Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
$beforeHtml=(Get-FileHash -LiteralPath $html -Algorithm SHA256).Hash
$checks=0
function Check($ok,$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
$plan=@(& (Join-Path $release 'install.ps1') -DestinationRoot $ml -VerifyOnly)
Check (@($plan|Where-Object {$_.PSObject.Properties.Name -contains 'Relative' -and $_.Relative -in @('index.html','pa26-chat.js','pa26-chat-endpoint.js')}).Count -eq 0) 'unknown CEF excluded from real installer plan'
Check (@($plan|Where-Object {$_.PSObject.Properties.Name -contains 'Relative' -and $_.Relative -eq 'police_assistant_2026.lua'}).Count -eq 1) 'native script remains installable'
$failed=$false;try{& (Join-Path $release 'install.ps1') -DestinationRoot $ml -VerifyOnly -RequireCef|Out-Null}catch{$failed=$true}
Check $failed 'strict CEF requirement still rejects unknown SHA'
Check ((Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash -eq $beforeMain) 'launcher main unchanged'
Check ((Get-FileHash -LiteralPath $html -Algorithm SHA256).Hash -eq $beforeHtml) 'existing tag and HTML unchanged'
Check (-not(Test-Path -LiteralPath (Join-Path $ml 'police_assistant_2026.lua'))) 'VerifyOnly wrote no runtime files'
# A complete fake dependency set exercises a real transaction without loading any DLL.
$dependencies=Get-Content -LiteralPath (Join-Path $release 'DEPENDENCIES.json') -Raw|ConvertFrom-Json
foreach($package in $dependencies.packages){foreach($file in $package.files){
 $target=Join-Path $ml $file.target;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
 [IO.File]::WriteAllText($target,'fixture dependency, never executed')
}}
[IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
$personal=Join-Path $ml 'config/police_assistant_2026_notes.json';[IO.File]::WriteAllText($personal,'PRIVATE fixture notes')
$privateHash=(Get-FileHash -LiteralPath $personal -Algorithm SHA256).Hash
& (Join-Path $release 'install.ps1') -DestinationRoot $ml -SkipAuthorBinds -SkipAuthorSettings|Out-Null
Check (Test-Path -LiteralPath (Join-Path $ml 'police_assistant_2026.lua')) 'native program actually installed in fixture'
Check ((Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash -eq $beforeMain) 'transaction preserved unknown launcher main'
Check ((Get-FileHash -LiteralPath $html -Algorithm SHA256).Hash -eq $beforeHtml) 'transaction preserved old PA tag and HTML'
Check ((Get-FileHash -LiteralPath $personal -Algorithm SHA256).Hash -eq $privateHash) 'transaction preserved private notes'
Check (-not(Test-Path -LiteralPath (Join-Path $hud 'pa26-chat-endpoint.js'))) 'no adapter assets added to unknown CEF'
$result=@{status='passed';checks=$checks;live_game_written=$false;scenario='production hash gate: unknown CEF with old PA tag; real native fixture installation; strict mode rejects'}
$result|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'CEF_INSTALLER0440.json') -Encoding UTF8
Write-Output ('CEF installer checks: '+$checks)
