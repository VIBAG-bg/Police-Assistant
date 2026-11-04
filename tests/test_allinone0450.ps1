Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baseline=Join-Path (Split-Path $release) 'Police-Assistant-2026-v0.44.0-dev'
$box=Join-Path $release ('tests\install-sandbox\aio-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($box)|Out-Null
$expected='c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db'
$checks=0
function Check($value,$why){$script:checks++;if(-not $value){throw ('ASSERT: '+$why)}}
function Personal($ml){
 [IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
 $hashes=@{}
 foreach($name in @('binds','settings','notes')){
  $p=Join-Path $ml ('config\police_assistant_2026_'+$name+'.json')
  [IO.File]::WriteAllText($p,('PERSONAL '+$name));$hashes[$p]=(Get-FileHash $p -Algorithm SHA256).Hash
 }
 $p=Join-Path $ml 'config\custom-roads.bin';[IO.File]::WriteAllText($p,'USER SELECTED GRAPH')
 $hashes[$p]=(Get-FileHash $p -Algorithm SHA256).Hash
 return $hashes
}
function Preserved($hashes){foreach($p in $hashes.Keys){Check ((Get-FileHash $p -Algorithm SHA256).Hash -ceq $hashes[$p]) 'personal/custom graph bytes preserved'}}
foreach($kind in @('standalone','launcher','upgrade0440')){
 $game=Join-Path $box $kind
 if($kind -eq 'launcher'){$game=Join-Path $release ('tests\cef-contract-sandbox\aio-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
 $ml=Join-Path $game 'MoonLoader';[IO.Directory]::CreateDirectory($ml)|Out-Null
 if($kind -eq 'upgrade0440'){
  $old=Get-Content (Join-Path $baseline 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
  foreach($row in $old.files){
   $to=Join-Path $ml $row.path;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))|Out-Null
   Copy-Item -LiteralPath (Join-Path $baseline ('moonloader\'+$row.path)) -Destination $to
  }
 }
 $personal=Personal $ml
 $cefBefore=@{}
 if($kind -eq 'launcher'){
  foreach($name in @('gta_sa.exe','moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $game $name),'fixture, never executed')}
  $deps=Get-Content (Join-Path $release 'DEPENDENCIES.json') -Raw|ConvertFrom-Json
  foreach($package in $deps.packages){foreach($file in $package.files){
   $p=Join-Path $ml $file.target;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null
   [IO.File]::WriteAllText($p,'fixture dependency, never loaded')
  }}
  $hud=Join-Path $game 'cef\assets\hud';[IO.Directory]::CreateDirectory($hud)|Out-Null
  foreach($name in @('main.js','index.html')){
   $p=Join-Path $hud $name
   $text=if($name -eq 'index.html'){'<html><head></head><body><div id="chatInput"><input id="chatInputField"></div><script src="main.js"></script></body></html>'}else{'UNREVIEWED LAUNCHER FILE'}
   [IO.File]::WriteAllText($p,$text);$cefBefore[$p]=(Get-FileHash $p -Algorithm SHA256).Hash
  }
 }
 & (Join-Path $release 'install.ps1') -DestinationRoot $ml -SkipAuthorBinds -SkipAuthorSettings | Out-Null
 Check ((Get-FileHash (Join-Path $ml 'resource\pa26\roads.bin') -Algorithm SHA256).Hash -ieq $expected) 'graph installed in own directory'
 Check (-not(Test-Path (Join-Path $game 'exsellent\gps\roads.bin'))) 'no launcher graph required/created'
 Check (-not(Test-Path (Join-Path $game 'ExsellentGps.asi'))) 'no ASI installed'
 Preserved $personal;Preserved $cefBefore
}
. (Join-Path $release 'moonloader\resource\pa26\updater\pa26-update.ps1') -Mode Library
function Get-PaGameRunning{return $false} # All destinations below are isolated fixture directories.
$script:PaBase=Join-Path $box 'worker-store'
function New-UpdateCase($name){
 $ml=Join-Path $box ($name+'\MoonLoader');[IO.Directory]::CreateDirectory((Join-Path $ml 'lib'))|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $ml 'resource\pa26'))|Out-Null
 [IO.File]::WriteAllText((Join-Path $ml 'police_assistant_2026.lua'),"script_version('0.44.0')")
 [IO.File]::WriteAllText((Join-Path $ml 'lib\pa26_core.lua'),"VERSION='0.44.0'")
 Copy-Item -LiteralPath (Join-Path $release 'moonloader\lib\pa26_update_platform.lua') -Destination (Join-Path $ml 'lib\pa26_update_platform.lua')
 [IO.File]::WriteAllText((Join-Path $ml 'resource\pa26\roads.bin'),'OLD GRAPH')
 $personal=Personal $ml
 $job=Join-Path $script:PaBase ('jobs\'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($job)|Out-Null
 Initialize-PaPaths $ml $job
 return @{ml=$ml;job=$job;personal=$personal}
}
$archive=Join-Path $release 'pa26-update.zip'
$candidate=@{version='0.45.0';sha256=(Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant();size=(Get-Item $archive).Length}
Check (Test-PaOwned 'MoonLoader/resource/pa26/roads.bin') 'only the exact official graph path is permitted'
foreach($p in @('MoonLoader/resource/pa26/other.bin','MoonLoader/resource/pa26/roads.bin.exe','MoonLoader/config/roads.bin')){Check (-not(Test-PaOwned $p)) 'do not broaden worker ownership'}
$case=New-UpdateCase 'update-success';$folder=Join-Path $case.job 'package';$m=Expand-PaPackage $archive $folder $candidate
Invoke-PaTransaction $folder $m
Check ((Get-PaCurrent) -eq '0.45.0') 'new worker installs the all-in-one payload'
Check ((Get-PaHash (Join-Path $case.ml 'resource\pa26\roads.bin')) -ceq $expected) 'update installs verified graph'
Preserved $case.personal
$case=New-UpdateCase 'update-rollback';$folder=Join-Path $case.job 'package';$m=Expand-PaPackage $archive $folder $candidate
$script:graphFault=$false
$script:PaFault={param($n)
 $p=Join-Path $script:PaML 'resource\pa26\roads.bin'
 if((-not $script:graphFault) -and (Get-PaHash $p) -ceq $expected){$script:graphFault=$true;throw 'simulated_crash'}
}
$failed=$false;try{Invoke-PaTransaction $folder $m}catch{$failed=$true}
Check $failed 'interruption after graph replacement is detected';Check $script:graphFault 'fault reached the new resource'
$script:PaFault=$null
$journal=Read-PaJson (Join-Path $case.job 'journal.json');Restore-PaTransaction $journal
Check ((Get-PaCurrent) -eq '0.44.0') 'entry point rolled back'
Check ([IO.File]::ReadAllText((Join-Path $case.ml 'resource\pa26\roads.bin')) -ceq 'OLD GRAPH') 'old graph restored'
Preserved $case.personal
# Demonstrate the transition limit instead of weakening the deployed 0.44 worker.
$case=New-UpdateCase 'old-worker-refusal'
& {
 . (Join-Path $baseline 'moonloader\resource\pa26\updater\pa26-update.ps1') -Mode Library
 $script:PaBase=Join-Path $box 'worker-store'
 Initialize-PaPaths $case.ml $case.job
 $rejected=$false;try{Expand-PaPackage $archive (Join-Path $case.job 'package') $candidate|Out-Null}catch{$rejected=$_.Exception.Message -eq 'unowned_payload_file'}
 Check $rejected 'old 0.44 worker refuses new binary resource before any game write'
 Check ((Get-PaCurrent) -eq '0.44.0') 'safe old-worker refusal preserves old version';Preserved $case.personal
}
$report=@{version='0.45.0';status='passed';checks=$checks;fixture_only=$true;game_started=$false;live_game_written=$false;
 scenarios=@('fresh standalone','fresh launcher unknown CEF preserved','full installer upgrade 0.44.0','new worker all-in-one update','graph replacement crash and recovery','old worker safe refusal');
 archive_sha256=$candidate.sha256;manifest_sha256=(Get-FileHash (Join-Path $release 'INSTALL_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant();
 updater_sha256=(Get-FileHash (Join-Path $release 'moonloader\resource\pa26\updater\pa26-update.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();
 old_worker_direct_update='BLOCKED_USE_FULL_INSTALLER_ONCE'}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'ALLINONE_INSTALL0450.json'),($report|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Output ('All-in-one installer/updater fixtures: '+$checks+' checks passed.')
