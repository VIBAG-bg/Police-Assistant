[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Baseline,
 [string]$OfficialHudPath=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previous=[IO.Path]::GetFullPath($Baseline)
$root=Join-Path $release ('tests/update-sandbox/previous-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$archive=Join-Path $release 'pa26-update.zip'
$oldManifest=Get-Content -LiteralPath (Join-Path $previous 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
$current=Get-Content -LiteralPath (Join-Path $release 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
$contract=Get-Content -LiteralPath (Join-Path $release 'CEF_CONTRACT.json') -Raw|ConvertFrom-Json
$worker=Join-Path $previous 'moonloader/resource/pa26/updater/pa26-update.ps1'
. $worker -Mode Library
$script:PaBase=Join-Path $root 'store'
function Get-PaGameRunning {return $false}
$candidate=@{sha256=Get-PaHash $archive;size=(Get-Item -LiteralPath $archive).Length;version=$current.release}
$environments=@('native')
if($OfficialHudPath){
 if((Get-PaHash $OfficialHudPath) -cne $contract.hud_main_sha256){throw 'Read-only official HUD reference differs from the reviewed contract.'}
 $environments+=@('launcher')
}
$cases=@();$checks=0
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
foreach($environment in $environments){
 $game=Join-Path $root ($environment+'/game');$ml=Join-Path $game 'MoonLoader'
 foreach($row in $oldManifest.files){
  $to=Join-Path $ml $row.path
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))|Out-Null
  [IO.File]::Copy((Join-Path $previous ('moonloader/'+$row.path)),$to)
 }
 foreach($name in @('binds','notes','settings','knowledge_personal','files_pending')){
  [IO.File]::WriteAllText((Join-Path $ml ('config/police_assistant_2026_'+$name+'.json')),('PERSONAL '+$name))
 }
 $protected=@{}
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $ml 'config') -File){$protected[$file.FullName]=Get-PaHash $file.FullName}
 if($environment -eq 'launcher'){
  $hud=Join-Path $game 'cef/assets/hud';[IO.Directory]::CreateDirectory($hud)|Out-Null
  [IO.File]::Copy($OfficialHudPath,(Join-Path $hud 'main.js'))
  foreach($row in $oldManifest.cef_files){[IO.File]::Copy((Join-Path $previous ('cef/assets/hud/'+$row.path)),(Join-Path $hud $row.path))}
  [IO.File]::WriteAllText((Join-Path $hud 'index.html'),'<html><body>CLIENT HUD<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script><script src="pa26-chat-endpoint.js"></script></body></html>')
  $protected[(Join-Path $hud 'main.js')]=Get-PaHash (Join-Path $hud 'main.js')
 }
 $job=Join-Path $script:PaBase ('jobs/'+[guid]::NewGuid().ToString('N'))
 [IO.Directory]::CreateDirectory($job)|Out-Null
 Initialize-PaPaths $ml $job
 $folder=Join-Path $job 'package';$manifest=Expand-PaPackage $archive $folder $candidate
 Check ($manifest.version -ceq $current.release) 'actual ZIP version'
 $plan=@(Get-PaPlan $folder $manifest)
 Check ($plan[-1].path -ceq 'MoonLoader/police_assistant_2026.lua') 'entry replaced last'
 Check (@($plan|Where-Object {$_.path -ceq 'MoonLoader/lib/pa26_vehicle_types.lua'}).Count -eq 1) 'new module owned by old worker'
 foreach($name in @('fine_window','mark_window','ground_window','procedure_flow','procedure_input','procedure_window','sanctions')){
  Check (@($plan|Where-Object {$_.path -ceq ('MoonLoader/lib/pa26_'+$name+'.lua')}).Count -eq 1) 'new procedure module owned by previous worker'
 }
 Invoke-PaTransaction $folder $manifest
 Check ((Get-PaCurrent) -ceq $current.release) 'old worker installs actual new package'
 foreach($row in $plan){Check ((Get-PaHash (Join-Path $game $row.path)) -ceq $row.sha256) 'installed bytes'}
 foreach($path in $protected.Keys){Check ((Get-PaHash $path) -ceq $protected[$path]) 'personal data and official HUD preserved'}
 if($environment -eq 'native'){
  Check (-not(Test-Path -LiteralPath (Join-Path $game 'cef'))) 'native update never creates launcher assets'
 }else{
  foreach($row in $current.cef_files){Check ((Get-PaHash (Join-Path $hud $row.path)) -ceq $row.sha256) 'new adapter copied under official HUD contract'}
  $html=[IO.File]::ReadAllText((Join-Path $hud 'index.html'))
  Check ($html.Contains('CLIENT HUD')) 'foreign markup retained'
  Check ([regex]::Matches($html,'src="pa26-chat.js"').Count -eq 1) 'adapter tag remains unique'
 }
 $journal=Read-PaJson (Join-Path $job 'journal.json')
 Check ($journal.personal.Count -ge 6) 'personal backup recorded'
 foreach($row in $journal.personal){
  $copy=Get-PaPath $journal.backup $row.backup_file
  Check ((Get-PaHash $copy) -ceq $row.sha256) 'personal backup verified'
 }
 $cases+=@{environment=$environment;installed_files=$plan.Count;protected_files=$protected.Count}
 Write-Output ('Previous worker '+$oldManifest.release+' -> '+$current.release+': '+$environment+' passed.')
}
@{status='passed';checks=$checks;release=$current.release;baseline=$oldManifest.release;
 previous_worker_sha256=Get-PaHash $worker;package_sha256=$candidate.sha256;cases=$cases;
 real_game_written=$false;official_hud_read_only=[bool]$OfficialHudPath}|ConvertTo-Json -Depth 5|
 Set-Content -LiteralPath (Join-Path $release 'tests/PREVIOUS_WORKER0422.json') -Encoding UTF8
