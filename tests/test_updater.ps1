Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$paRelease=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $paRelease 'moonloader\resource\pa26\updater\pa26-update.ps1') -Mode Library
$paRoot=Join-Path $PSScriptRoot ('update-sandbox\run-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($paRoot)|Out-Null
$script:PaBase=Join-Path $paRoot 'store'
$checks=0
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
function Reject([scriptblock]$action,[string]$why){$failed=$false;try{&$action|Out-Null}catch{$failed=$true};Check $failed $why}
foreach($row in @(@('1.2.3','1.2.2',1),@('0.38.0','0.38.0-dev',1),@('1.0.0-rc.10','1.0.0-rc.2',1),@('v1.0.0','1.0.0',0),@('1.0.0-1','1.0.0-a',-1))){Check ((Compare-PaVersion $row[0] $row[1]) -eq $row[2]) 'semver order'}
foreach($v in @('01.0.0','1.0','1.2.3/evil','1.0.0-01','1.0.0-9999999','1.2.3+build','1.0.0`n')){Reject {Get-PaVersion $v} ('bad version '+$v)}
foreach($path in @('../x','a/../b','/absolute','C:/x','a\b','a//b','a/CON.txt','a/file.','a:stream','a/%2e%2e/b')){Reject {Get-PaPath $paRoot $path} 'unsafe path'}
foreach($path in @('MoonLoader/config/police_assistant_2026_binds.json','MoonLoader/lib/user.lua','MoonLoader/resource/pa26/user.json','install.ps1','cef/assets/hud/main.js')){Check (-not (Test-PaOwned $path)) 'personal/unowned path'}
foreach($url in @('http://github.com/a/b','https://github.com.evil.test/a','https://u:p@github.com/a','https://127.0.0.1/a','https://github.com:444/a','file:///C:/a')){Reject {Assert-PaUrl $url 'asset'} 'bad network endpoint'}
function New-Case([string]$name) {
    $ml=Join-Path $paRoot ($name+'\game\MoonLoader');[IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $ml 'police_assistant_2026.lua'),"script_version('0.38.0-dev')")
    [IO.Directory]::CreateDirectory((Join-Path $ml 'lib'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $ml 'lib\pa26_core.lua'),'OLD CORE')
    [IO.File]::WriteAllBytes((Join-Path $ml 'config\police_assistant_2026_binds.json'),[byte[]](1,2,0,255,99))
    [IO.File]::WriteAllText((Join-Path $ml 'config\police_assistant_2026_notes.json'),'LATEST USER NOTES')
    $unicode='police_assistant_2026_'+[char]0x0437+[char]0x0430+[char]0x043C+'.json'
    [IO.File]::WriteAllText((Join-Path $ml ('config\'+$unicode)),'UNICODE PERSONAL FILE')
    [IO.File]::WriteAllText((Join-Path $ml 'config\other-mod.json'),'OTHER MOD')
    $job=Join-Path $script:PaBase ('jobs\'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($job)|Out-Null
    Initialize-PaPaths $ml $job
    $folder=Join-Path $job 'package';$files=@()
    foreach($item in @(@('MoonLoader/lib/pa26_core.lua','NEW CORE'),@('MoonLoader/lib/pa26_new.lua','NEW FILE'),@('MoonLoader/police_assistant_2026.lua',"script_version('0.39.0')"))){
        $path=Get-PaPath $folder $item[0];[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))|Out-Null
        [IO.File]::WriteAllText($path,$item[1]);$files+=@{path=$item[0];sha256=Get-PaHash $path;size=(Get-Item $path).Length}
    }
    return @{ml=$ml;job=$job;folder=$folder;manifest=@{version='0.39.0';files=$files};bind=Get-PaHash (Join-Path $ml 'config\police_assistant_2026_binds.json')}
}
$script:running=$false
function Get-PaGameRunning {return $script:running}
function Verify-Old($case){
    Check ((Get-PaCurrent) -eq '0.38.0-dev') 'old entry restored'
    Check ([IO.File]::ReadAllText((Join-Path $case.ml 'lib\pa26_core.lua')) -eq 'OLD CORE') 'old module restored'
    Check (-not [IO.File]::Exists((Join-Path $case.ml 'lib\pa26_new.lua'))) 'new module rolled back'
    Check ((Get-PaHash (Join-Path $case.ml 'config\police_assistant_2026_binds.json')) -eq $case.bind) 'binary personal file unchanged'
    Check ([IO.File]::ReadAllText((Join-Path $case.ml 'config\other-mod.json')) -eq 'OTHER MOD') 'other mod untouched'
}
$case=New-Case 'success'
# Snapshot must include edits after the package was prepared, immediately before install.
[IO.File]::AppendAllText((Join-Path $case.ml 'config\police_assistant_2026_notes.json'),' edited after download')
Invoke-PaTransaction $case.folder $case.manifest
Check ((Get-PaCurrent) -eq '0.39.0') 'new version installed'
Check (-not [IO.File]::Exists($script:PaMarker)) 'completion removes gate'
$journal=Read-PaJson (Join-Path $case.job 'journal.json')
Check ([IO.File]::ReadAllText((Join-Path $journal.backup 'personal\MoonLoader\config\police_assistant_2026_notes.json')) -like '*edited after download') 'latest notes backed up'
Check ((Get-PaHash (Join-Path $case.ml 'config\police_assistant_2026_binds.json')) -eq $case.bind) 'success preserves personal bytes'
Reject {Invoke-PaTransaction $case.folder $case.manifest} 'no same-version replay'
foreach($after in @(1,2,3)){
    $case=New-Case ('failure-'+$after)
    $script:PaFault={param($n)if($n -eq $after){throw 'injected_io_error'}}
    Reject {Invoke-PaTransaction $case.folder $case.manifest} 'write failure rolls back'
    Verify-Old $case;Check (-not [IO.File]::Exists($script:PaMarker)) 'rollback removes gate'
}
$script:PaFault=$null;$case=New-Case 'game-open';$script:running=$true
Reject {Invoke-PaTransaction $case.folder $case.manifest} 'running game refuses writes';Verify-Old $case;$script:running=$false
foreach($after in @(1,2,3)){
    $case=New-Case ('crash-'+$after)
    $script:PaFault={param($n)if($n -eq $after){throw 'simulated_crash'}}
    Reject {Invoke-PaTransaction $case.folder $case.manifest} 'simulated worker termination'
    Check ([IO.File]::Exists($script:PaMarker)) 'interrupted state remains gated'
    $journal=Read-PaJson (Join-Path $case.job 'journal.json')
    $script:PaFault=$null;Restore-PaTransaction $journal;Verify-Old $case
    Check (-not [IO.File]::Exists($script:PaMarker)) 'recovered state ungated'
}
$case=New-Case 'personal-changed'
$script:PaFault={param($n)if($n -eq 1){[IO.File]::WriteAllText((Join-Path $script:PaML 'config\police_assistant_2026_notes.json'),'NEW EXTERNAL EDIT')}}
Reject {Invoke-PaTransaction $case.folder $case.manifest} 'external data mutation stops install';Verify-Old $case
Check ([IO.File]::ReadAllText((Join-Path $case.ml 'config\police_assistant_2026_notes.json')) -eq 'NEW EXTERNAL EDIT') 'recovery never overwrites newer personal edits'
$script:PaFault=$null
$case=New-Case 'damaged-backup';$script:PaFault={param($n)throw 'simulated_crash'}
Reject {Invoke-PaTransaction $case.folder $case.manifest} 'crash before recovery test';$script:PaFault=$null
$journal=Read-PaJson (Join-Path $case.job 'journal.json')
[IO.File]::WriteAllText((Join-Path $journal.backup 'runtime\MoonLoader\lib\pa26_core.lua'),'DAMAGED')
Reject {Restore-PaTransaction $journal} 'damaged backup cannot be restored'
Check ([IO.File]::Exists($script:PaMarker)) 'damaged recovery stays gated'
# Malicious archive entries and wrong hashes are rejected before runtime planning.
Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($bad in @('../escape.lua','MoonLoader/config/police_assistant_2026_binds.json','MoonLoader/lib/pa26_a.lua:stream')){
    $archive=Join-Path $case.job ([guid]::NewGuid().ToString('N')+'.zip')
    $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    $e=$zip.CreateEntry($bad);$st=$e.Open();$st.WriteByte(1);$st.Dispose();$zip.Dispose()
    $candidate=@{sha256=Get-PaHash $archive;size=(Get-Item $archive).Length;version='0.39.0'}
    Reject {Expand-PaPackage $archive (Join-Path $case.job ([guid]::NewGuid().ToString('N'))) $candidate} 'unsafe zip rejected'
}
# A game opened mid-write pauses recovery until it closes; no force-kill/reload.
$case=New-Case 'game-reopened';$script:waitCalls=0
function Wait-PaClosed([bool]$allowCancel=$true){$script:waitCalls++;$script:running=$false}
$script:PaFault={param($n)if($n -eq 1){$script:running=$true}}
Invoke-PaTransaction $case.folder $case.manifest
Check ($script:waitCalls -eq 1) 'installation waits for a reopened game'
Check ((Get-PaCurrent) -eq '0.39.0') 'early restart resumes instead of rolling back'
Check ((Get-PaHash (Join-Path $case.ml 'config\police_assistant_2026_binds.json')) -eq $case.bind) 'resumed install preserves personal data'
Check (-not [IO.File]::Exists($script:PaMarker)) 'resumed install removes gate only when complete';$script:PaFault=$null
# The approved production path also waits for a game that opens at the handoff boundary.
$case=New-Case 'game-open-at-handoff';$script:running=$true;$script:waitCalls=0
Invoke-PaTransaction $case.folder $case.manifest $true
Check ($script:waitCalls -eq 1) 'production handoff waits before creating its safety gate'
Check ((Get-PaCurrent) -eq '0.39.0') 'handoff race finishes the selected version'
Check ((Get-PaHash (Join-Path $case.ml 'config\police_assistant_2026_binds.json')) -eq $case.bind) 'handoff preserves personal data'
# Valid release package round trip: extraction, per-file verification and install.
$case=New-Case 'valid-package'
foreach($rel in @('lib\pa26_update_platform.lua','resource\pa26\updater\pa26-update.ps1')){
    $dest=Join-Path $case.ml $rel;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))|Out-Null
    [IO.File]::Copy((Join-Path $paRelease ('moonloader\'+$rel)),$dest)
    $payload=Get-PaPath $case.folder ('MoonLoader/'+$rel.Replace('\','/'));[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))|Out-Null
    [IO.File]::Copy($dest,$payload)
    $case.manifest.files+=@{path='MoonLoader/'+$rel.Replace('\','/');sha256=Get-PaHash $payload;size=(Get-Item $payload).Length}
}
$core=Get-PaPath $case.folder 'MoonLoader/lib/pa26_core.lua';[IO.File]::WriteAllText($core,"return {VERSION = '0.39.0'}")
$case.manifest.files[0].sha256=Get-PaHash $core;$case.manifest.files[0].size=(Get-Item $core).Length
$case.manifest.product='police-assistant-2026';$case.manifest.protocol=1;$case.manifest.storage='pa26-split-json-1'
Write-PaJson (Join-Path $case.folder 'pa26-update.json') $case.manifest
$archive=Join-Path $case.job 'valid.zip';$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
foreach($file in Get-ChildItem -LiteralPath $case.folder -File -Recurse){$name=$file.FullName.Substring($case.folder.Length+1).Replace('\','/');[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$name)|Out-Null};$zip.Dispose()
$candidate=@{version='0.39.0';sha256=Get-PaHash $archive;size=(Get-Item $archive).Length;asset_id=17}
$unpacked=Join-Path $case.job 'unpacked';$m=Expand-PaPackage $archive $unpacked $candidate
Check ($m.files.Count -eq 5) 'complete payload verified'
$approved=@{approved=$true;candidate=$candidate};Assert-PaApproval $approved $candidate
foreach($patch in @(@{approved=$false},@{approved='true'},@{candidate=@{sha256=('0'*64);version='0.39.0';asset_id=17}},@{candidate=@{sha256=$candidate.sha256;version='0.40.0';asset_id=17}})){
    $request=@{approved=$true;candidate=$candidate};foreach($key in $patch.Keys){$request[$key]=$patch[$key]}
    Reject {Assert-PaApproval $request $candidate} 'changed or unapproved release refused'
}
Invoke-PaTransaction $unpacked $m
Check ((Get-PaCurrent) -eq '0.39.0') 'verified archive installed'
Check ((Get-PaHash (Join-Path $case.ml 'config\police_assistant_2026_binds.json')) -eq $case.bind) 'archive install preserves personal data'
# Metadata validation uses the production parser with a replayed HTTPS response.
$case=New-Case 'metadata';$script:remoteCalls=0
$script:remoteRelease=@{tag_name='v0.39.0';draft=$false;prerelease=$false;body='Changes';assets=@(@{name='pa26-update.zip';state='uploaded';digest=('sha256:'+('a'*64));size=123;id=17;browser_download_url='https://github.com/Owner/Repo/releases/download/v0.39.0/pa26-update.zip'})}
function Get-PaRemote([string]$url,[string]$kind,[long]$limit,[int]$timeout,[string]$out=''){$script:remoteCalls++;return ($script:remoteRelease|ConvertTo-Json -Depth 8)}
$request=@{repository='Owner/Repo';include_prerelease=$false;timeout_seconds=1}
$c=Get-PaCandidate $request;Check ($c.version -eq '0.39.0') 'release metadata parsed'
$script:remoteRelease.assets[0].digest='';Check (-not (Get-PaCandidate $request)) 'missing GitHub digest refused'
$script:remoteRelease.assets[0].digest='sha256:'+('a'*64);$script:remoteRelease.assets[0].browser_download_url='https://github.com/Other/Repo/releases/download/v0.39.0/pa26-update.zip'
Reject {Get-PaCandidate $request} 'cross-repository payload refused'
$case=New-Case 'active-worker';Set-PaStatus 'waiting' 'downloaded_close_game'
Write-PaJson (Join-Path $script:PaState 'active.json') @{moonloader=$script:PaML;job=[IO.Path]::GetFileName($case.job);pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks}
$active=Get-PaActive;Check $active.active_job 'reload discovers active download';Check ($active.phase -eq 'waiting') 'waiting state recovered'
Write-PaJson (Join-Path $script:PaState 'active.json') @{moonloader=$script:PaML;job=[IO.Path]::GetFileName($case.job);pid=2147483647;started=1}
$active=Get-PaActive;Check ($active.message -eq 'worker_interrupted') 'dead preinstall worker is reported safely';Verify-Old $case
$case=New-Case 'physical-lock'
Write-PaMarker ('a'*32);Reject {Invoke-PaTransaction $case.folder $case.manifest} 'existing physical marker refuses another install'
Reject {Write-PaMarker ('b'*32)} 'marker cannot be overwritten through another alias'
Check ([IO.File]::ReadAllText($script:PaMarker) -ceq ('a'*32)) 'first marker owner retained';Verify-Old $case
# Optional launcher files never create or rewrite a different client's CEF HUD.
foreach($environment in @('native','foreign-cef','official-cef','changed-pa-cef')){
 $case=New-Case ('cef-contract-'+$environment)
 foreach($name in @('pa26-chat.js','pa26-chat-endpoint.js')){
  $path=Get-PaPath $case.folder ('cef/assets/hud/'+$name);[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))|Out-Null
  [IO.File]::WriteAllText($path,'NEW PA CEF')
  $case.manifest.files+=@{path='cef/assets/hud/'+$name;sha256=Get-PaHash $path;size=(Get-Item $path).Length}
 }
 $hashTool=[Security.Cryptography.SHA256]::Create()
 try{$case.manifest.cef_main_sha256=[BitConverter]::ToString($hashTool.ComputeHash([Text.Encoding]::UTF8.GetBytes('OFFICIAL HUD'))).Replace('-','').ToLowerInvariant()}finally{$hashTool.Dispose()}
 $hud=Get-PaPath $script:PaGame 'cef/assets/hud'
 if($environment -ne 'native'){
  [IO.Directory]::CreateDirectory($hud)|Out-Null
  $main=Join-Path $hud 'main.js';[IO.File]::WriteAllText($main,$(if($environment -eq 'official-cef'){'OFFICIAL HUD'}else{'FOREIGN OR CHANGED HUD'}))
  $html='<html><body>CLIENT HUD</body></html>'
  if($environment -eq 'changed-pa-cef'){$html='<html><body><!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script></body></html>'}
  [IO.File]::WriteAllText((Join-Path $hud 'index.html'),$html)
 }
 if($environment -eq 'changed-pa-cef'){Reject {Get-PaPlan $case.folder $case.manifest} 'changed existing PA CEF contract refused';continue}
 $plan=@(Get-PaPlan $case.folder $case.manifest)
 Check ($plan[-1].path -ceq 'MoonLoader/police_assistant_2026.lua') 'entry replaced last'
 if($environment -in @('native','foreign-cef')){
  Check (@($plan|Where-Object {$_.path.StartsWith('cef/')}).Count -eq 0) 'native or foreign CEF excluded'
  Invoke-PaTransaction $case.folder $case.manifest
  Check (-not [IO.File]::Exists((Join-Path $hud 'pa26-chat.js'))) 'no adapter added to native client'
  if($environment -eq 'foreign-cef'){Check ([IO.File]::ReadAllText((Join-Path $hud 'index.html')) -ceq $html) 'foreign markup unchanged'}
 }else{
  Check (@($plan|Where-Object {$_.path.StartsWith('cef/')}).Count -eq 3) 'official CEF files and markup prepared'
  Invoke-PaTransaction $case.folder $case.manifest
  Check ((Get-PaHash (Join-Path $hud 'main.js')) -eq $case.manifest.cef_main_sha256) 'official client main unchanged'
  Check ([IO.File]::ReadAllText((Join-Path $hud 'index.html')).Contains('src="pa26-chat-endpoint.js"')) 'official bridge connected'
  Check (@(Get-PaPlan $case.folder $case.manifest).Count -eq 5) 'repeat patch idempotent'
 }
}
Write-PaJson (Join-Path $PSScriptRoot 'UPDATER_WORKER_RESULTS.json') @{status='passed';checks=$checks;real_game_written=$false;gta_started=$false;backup_and_rollback=$true;durable_recovery=$true;personal_edits_preserved=$true;real_package_round_trip=$true;metadata_and_approval=$true;active_job_recovery=$true;physical_marker_lock=$true;unicode_personal_names=$true;native_and_cef=$true;worker_sha256=Get-PaHash (Join-Path $paRelease 'moonloader\resource\pa26\updater\pa26-update.ps1');sandbox=$paRoot}
Write-Output ('Updater worker: '+$checks+' checks passed; all runtime/data tests isolated.')
