param([string]$OfficialCache='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'tools/pa-setup.ps1')
Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Join-Path $PSScriptRoot ('install-sandbox/setup-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$checks=0
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
function Reject([scriptblock]$action,[string]$why){$failed=$false;try{&$action|Out-Null}catch{$failed=$true};Check $failed $why}
function Hash([string]$path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Snapshot([string]$path){$s=@{};if(Test-Path -LiteralPath $path){foreach($f in Get-ChildItem -LiteralPath $path -File -Recurse){$s[$f.FullName]=Hash $f.FullName}};return $s}
function Same($before,[string]$path){$after=Snapshot $path;Check ($before.Count -eq $after.Count) 'no new target files';foreach($k in $before.Keys){Check ($after[$k] -eq $before[$k]) 'target bytes unchanged'}}
$manifest=Read-PaDependencyManifest (Join-Path $release 'DEPENDENCIES.json')
Check ($manifest.packages.Count -eq 3) 'three pinned dependency families'
foreach($bad in @('../x','a/../b','a//b','a\b','C:/x','/x','a/file.','a/CON.txt','a/x:stream','a/','a/%2e/b')){Reject {Get-PaSetupPath $root $bad} 'unsafe relative path'}
foreach($bad in @('','relative\MoonLoader','C:relative','\\server\share\MoonLoader')){Reject {Resolve-PaSetupRoot $bad} 'invalid selected root'}
$game=Join-Path $root ('Custom GTA '+[char]0x0410)
[IO.Directory]::CreateDirectory($game)|Out-Null
Reject {Resolve-PaSetupRoot $game} 'missing game refused'
[IO.File]::WriteAllText((Join-Path $game 'gta_sa.exe'),'fixture')
Reject {Resolve-PaSetupRoot $game} 'missing MoonLoader refused'
foreach($name in @('moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $game $name),'fixture')}
$ml=Resolve-PaSetupRoot $game
Check ($ml -eq (Join-Path $game 'MoonLoader')) 'game folder resolved'
Check ((Resolve-PaSetupRoot $ml) -eq $ml) 'MoonLoader folder resolved'
$cache=Join-Path $root 'cache';[IO.Directory]::CreateDirectory($cache)|Out-Null
$packages=@()
foreach($original in $manifest.packages){
 $p=($original|ConvertTo-Json -Depth 10)|ConvertFrom-Json
 $zipPath=Join-Path $cache ($p.id+'.fixture')
 $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
 foreach($f in $p.files){
  $bytes=[Text.Encoding]::ASCII.GetBytes('FIXTURE '+$f.target)
  $hash=[Security.Cryptography.SHA256]::Create()
  try{$f.sha256=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
  $f.size=$bytes.Length;$entry=$zip.CreateEntry($f.entry);$stream=$entry.Open()
  try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
 }
 $zip.Dispose();$p.sha256=Hash $zipPath;$p.size=(Get-Item $zipPath).Length
 [IO.File]::Move($zipPath,(Join-Path $cache ($p.sha256+'.zip')));$packages+=,$p
}
$synthetic=@{schema=1;packages=$packages}
$before=Snapshot $game
$missing=@(Get-PaMissingDependencies $ml $synthetic)
Check ($missing.Count -eq 3) 'empty client needs all groups'
$plan=@(Get-PaDependencyPlan $ml $missing $cache $false)
Check ($plan.Count -eq 21) 'all pinned library and license files staged'
foreach($row in $plan){Check ((Hash $row.Source) -eq $row.SHA256) 'staged file checked';Check (-not $row.Existed) 'no replacement plan'}
Same $before $game
# Simulate the transaction only in the bounded fixture, then keep custom versions.
foreach($row in $plan){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($row.Target))|Out-Null;[IO.File]::Copy($row.Source,$row.Target)}
Check (@(Get-PaMissingDependencies $ml $synthetic).Count -eq 0) 'complete groups do not download'
$win32=Get-PaSetupPath $ml 'lib/mimgui/win32.lua';[IO.File]::Delete($win32)
$interrupted=@(Get-PaMissingDependencies $ml $synthetic)
Check ($interrupted.Count -eq 1 -and $interrupted[0].id -eq 'mimgui') 'pinned new init requires its win32 module'
$repair=@(Get-PaDependencyPlan $ml $interrupted $cache $false)
Check ($repair.Count -eq 1 -and $repair[0].Target -eq $win32) 'only missing compatible module staged'
[IO.File]::Copy($repair[0].Source,$win32)
$custom=Join-Path $ml 'lib/mimgui/init.lua';[IO.File]::WriteAllText($custom,'CUSTOM COMPATIBLE VERSION')
[IO.File]::Delete($win32)
Check (@(Get-PaMissingDependencies $ml $synthetic).Count -eq 0) 'complete custom library preserved'
$partial=Join-Path $root 'partial/MoonLoader';[IO.Directory]::CreateDirectory((Join-Path $partial 'lib/mimgui'))|Out-Null
[IO.File]::WriteAllText((Join-Path $partial 'lib/mimgui/init.lua'),'DIFFERENT DLL FAMILY')
$before=Snapshot $partial
Reject {Get-PaDependencyPlan $partial @($packages[1]) $cache $false} 'partial mixed version refused'
Same $before $partial
$empty=Join-Path $root 'untouched/MoonLoader';$before=Snapshot $empty
Reject {Get-PaDependencyPlan $empty @($packages[0]) (Join-Path $root 'no-cache') $false} 'offline missing cache refused'
Same $before $empty
function Malformed([string]$kind){
 $p=($packages[0]|ConvertTo-Json -Depth 10)|ConvertFrom-Json
 $path=Join-Path $cache ([guid]::NewGuid().ToString('N')+'.zip')
 $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
 if($kind -eq 'missing'){$entry=$zip.CreateEntry('other.txt')}
 elseif($kind -eq 'traversal'){$entry=$zip.CreateEntry('../escape.lua')}
 elseif($kind -eq 'dos-traversal'){$entry=$zip.CreateEntry('..\escape.lua')}
 elseif($kind -eq 'duplicate'){$null=$zip.CreateEntry('same.lua');$entry=$zip.CreateEntry('SAME.lua')}
 elseif($kind -eq 'dos-duplicate'){$null=$zip.CreateEntry('a/same.lua');$entry=$zip.CreateEntry('a\same.lua')}
 elseif($kind -eq 'link'){$entry=$zip.CreateEntry('link.lua');$entry.ExternalAttributes=([int]0xA000 -shl 16)}
 elseif($kind -eq 'count'){foreach($i in 1..513){$null=$zip.CreateEntry('x'+$i+'.lua')};$entry=$null}
 else{$entry=$zip.CreateEntry($p.files[0].entry)}
 if($entry){$stream=$entry.Open();try{$stream.WriteByte(1)}finally{$stream.Dispose()}}
 $zip.Dispose();$p.sha256=Hash $path;$p.size=(Get-Item $path).Length
 [IO.File]::Move($path,(Join-Path $cache ($p.sha256+'.zip')))
 return $p
}
foreach($kind in @('missing','traversal','dos-traversal','duplicate','dos-duplicate','link','count','bad-file')){
 $bad=Malformed $kind;Reject {Get-PaDependencyPlan $empty @($bad) $cache $false} ('ZIP '+$kind+' refused');Same $before $empty
}
$corruptCache=Join-Path $root 'corrupt';[IO.Directory]::CreateDirectory($corruptCache)|Out-Null
[IO.File]::WriteAllText((Join-Path $corruptCache ($packages[0].sha256+'.zip')),'CORRUPT')
Reject {Get-PaDependencyPlan $empty @($packages[0]) $corruptCache $false} 'corrupt cache refused'
Same $before $empty
$badManifest=($manifest|ConvertTo-Json -Depth 10)|ConvertFrom-Json
foreach($url in @('http://www.blast.hk/file','https://www.blast.hk:444/file','https://evil.example/file','https://a:b@luarocks.org/file')){
 $badManifest.packages[0].url=$url;$path=Join-Path $root 'bad-manifest.json';$badManifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding UTF8
 Reject {Read-PaDependencyManifest $path} 'dependency URL refused'
}
if($OfficialCache){
 $realMissing=@(Get-PaMissingDependencies $empty $manifest)
 $real=@(Get-PaDependencyPlan $empty $realMissing $OfficialCache $false)
 Check ($real.Count -eq 21) 'actual official archives staged'
 foreach($row in $real){Check ((Hash $row.Source) -eq $row.SHA256) 'actual official entry hash'}
 Same $before $empty
}
# Failed downloads can leave only cache material; never write a game target.
function Save-PaDependencyArchive($Package,[string]$Path){[IO.File]::WriteAllText($Path,'SHORT DOWNLOAD');throw 'simulated_network_failure'}
Reject {Get-PaDependencyPlan $empty @($packages[0]) (Join-Path $root 'failed-download') $true} 'network failure refused'
Same $before $empty
@{status='passed';checks=$checks;official_archives=[bool]$OfficialCache;real_game_written=$false;sandbox=$root}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'SETUP_RESULTS.json') -Encoding UTF8
Write-Output ('Setup: '+$checks+' checks passed; target files preserved on every failure.')
