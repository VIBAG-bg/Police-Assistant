Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'moonloader/resource/pa26/updater/pa26-update.ps1') -Mode Library
# Child process only: exercise .NET's legacy MAX_PATH policy independently
# of the developer machine's registry and modern Windows long-path support.
[AppContext]::SetSwitch('Switch.System.IO.UseLegacyPathHandling',$true)
[AppContext]::SetSwitch('Switch.System.IO.BlockLongPaths',$true)
$switches=[IO.Path].Assembly.GetType('System.AppContextSwitches')
if(-not $switches){throw 'Run this regression with Windows PowerShell 5.1.'}
foreach($name in @('_useLegacyPathHandling','_blockLongPaths')){
 $field=$switches.GetField($name,[Reflection.BindingFlags]'NonPublic,Static')
 if(-not $field){throw 'Legacy .NET path switch is unavailable.'}
 $field.SetValue($null,0)
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('pa405-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($root)|Out-Null
$script:PaBase=Join-Path $root 'store';$checks=0
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
function Reject([scriptblock]$fn,[string]$why){$failed=$false;try{&$fn|Out-Null}catch{$failed=$true};Check $failed $why}
function Get-PaGameRunning{return $false}
function New-PathCase([string]$name){
 $ml=Join-Path $root ($name+'/MoonLoader');[IO.Directory]::CreateDirectory((Join-Path $ml 'lib'))|Out-Null
 [IO.File]::WriteAllText((Join-Path $ml 'police_assistant_2026.lua'),"script_version('0.40.4')")
 [IO.File]::WriteAllText((Join-Path $ml 'lib/pa26_core.lua'),'OLD CORE')
 $snapshot=@{}
 foreach($parent in @('config','config/police_assistant_2026_preset_backup_01234567890123456789012345678901','config/police_assistant_2026_backup_abcdefghijklmnopqrstuvwxyz012345')){
  $dir=Join-Path $ml $parent;[IO.Directory]::CreateDirectory($dir)|Out-Null
  foreach($file in @('police_assistant_2026_settings.json.bak','police_assistant_2026_binds.json','police_assistant_2026_notes.json')){
   $path=Join-Path $dir $file;[IO.File]::WriteAllText($path,('PERSONAL '+$parent+'/'+$file));$snapshot[$path]=Get-PaHash $path
  }
 }
 $unicode=Join-Path $ml ('config/police_assistant_2026_'+[char]0x0437+[char]0x0430+[char]0x043C+'.json')
 [IO.File]::WriteAllText($unicode,'UNICODE PERSONAL FILE');$snapshot[$unicode]=Get-PaHash $unicode
 $job=Join-Path $script:PaBase ('jobs/'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($job)|Out-Null
 Initialize-PaPaths $ml $job;$folder=Join-Path $job 'package';$files=@()
 foreach($pair in @(@('MoonLoader/lib/pa26_core.lua','NEW CORE'),@('MoonLoader/police_assistant_2026.lua',"script_version('0.41.0')"))){
  $p=Get-PaPath $folder $pair[0];[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null
  [IO.File]::WriteAllText($p,$pair[1]);$files+=@{path=$pair[0];sha256=Get-PaHash $p;size=(Get-Item -LiteralPath $p).Length}
 }
 return @{ml=$ml;job=$job;folder=$folder;manifest=@{version='0.41.0';files=$files};snapshot=$snapshot}
}
function Verify-Personal($case){foreach($path in $case.snapshot.Keys){Check ((Get-PaHash $path) -ceq $case.snapshot[$path]) 'personal original byte preserved'}}
function Verify-Backup($case,$journal){
 Check ($journal.backup_layout -ceq 'flat-v1') 'explicit backup layout'
 Check ($journal.personal.Count -eq $case.snapshot.Count) 'nested backups included without omissions'
 $names=@{}
 foreach($row in $journal.personal){
  Check ($row.backup_file -cmatch '^personal/[0-9]{6}\.bin$') 'short personal filename'
  Check (-not $names.ContainsKey($row.backup_file)) 'duplicate original basenames never collide';$names[$row.backup_file]=$true
  $copy=Get-PaPath $journal.backup $row.backup_file
  Check ($copy.Length -lt 260) 'legacy-compatible backup path'
  Check ((Get-PaHash $copy) -ceq $row.sha256) 'backup bytes match recorded hash'
  Check ((Get-PaHash (Get-PaLocalPath $script:PaGame $row.path)) -ceq $row.sha256) 'original mapping intact'
 }
 foreach($row in $journal.plan){if($row.existed){Check ((Get-PaHash (Get-PaRuntimeBackup $journal $row)) -ceq $row.before) 'runtime backup intact'}}
}
$case=New-PathCase ('Игра-'+[char]0x044E)
$nested=@($case.snapshot.Keys|Where-Object {$_ -like '*preset_backup*'})[0]
$mirror=Join-Path $script:PaState ('backups/20261027T170000Z-'+('b'*32)+'/personal/'+$nested.Substring($script:PaGame.Length+1))
Check ($mirror.Length -ge 260) 'fixture reproduces old mirrored path overflow'
Reject {Copy-PaVerified $nested $mirror (Get-PaHash $nested)} 'old backup path is rejected by real legacy .NET IO'
Invoke-PaTransaction $case.folder $case.manifest
Check ((Get-PaCurrent) -ceq '0.41.0') 'legacy path update succeeds'
Verify-Personal $case;$journal=Read-PaJson (Join-Path $case.job 'journal.json');Verify-Backup $case $journal
Check (-not [IO.File]::Exists($script:PaMarker)) 'successful installation releases gate'
foreach($after in @(1,2)){
 $case=New-PathCase ('rollback-'+$after);$script:PaFault={param($n)if($n -eq $after){throw 'simulated_write_failure'}}
 Reject {Invoke-PaTransaction $case.folder $case.manifest} 'injected failure rolls back'
 Check ((Get-PaCurrent) -ceq '0.40.4') 'entry restored under legacy limits'
 Check ([IO.File]::ReadAllText((Join-Path $case.ml 'lib/pa26_core.lua')) -ceq 'OLD CORE') 'module restored under legacy limits'
 Check (-not [IO.File]::Exists($script:PaMarker)) 'rollback releases gate'
 Verify-Personal $case;$journal=Read-PaJson (Join-Path $case.job 'journal.json');Verify-Backup $case $journal
}
$script:PaFault=$null
# New helper must recover an old interrupted transaction using its mirrored journal.
$case=New-PathCase 'old-journal'
$script:PaFault={param($n)throw 'simulated_crash'}
Reject {Invoke-PaTransaction $case.folder $case.manifest} 'interruption leaves a recovery journal'
$script:PaFault=$null;$journal=Read-PaJson (Join-Path $case.job 'journal.json')
foreach($entry in $journal.plan){
 if($entry.existed){Copy-PaVerified (Get-PaRuntimeBackup $journal $entry) (Get-PaPath $journal.backup ('runtime/'+$entry.path)) $entry.before}
 $entry.PSObject.Properties.Remove('backup_file')
}
$journal.PSObject.Properties.Remove('backup_layout')
Write-PaJson (Join-Path $case.job 'journal.json') $journal
Restore-PaTransaction $journal
Check ((Get-PaCurrent) -ceq '0.40.4') 'old mirrored journal restored entry'
Check ([IO.File]::ReadAllText((Join-Path $case.ml 'lib/pa26_core.lua')) -ceq 'OLD CORE') 'old mirrored journal restored module'
Verify-Personal $case
Check (-not [IO.File]::Exists($script:PaMarker)) 'old recovery releases gate'
$old=@{backup=(Join-Path $case.job 'old-backup')}
$row=@{path='MoonLoader/lib/pa26_core.lua'}
$expected=Get-PaPath $old.backup ('runtime/'+$row.path)
Check ((Get-PaRuntimeBackup $old $row) -ceq $expected) 'old mirrored journal mapping remains supported'
$old.backup_layout='flat-v1';$row.backup_file='../personal/file.bin'
Reject {Get-PaRuntimeBackup $old $row} 'journal traversal refused'
$row.backup_file='personal/000000.bin';Reject {Get-PaRuntimeBackup $old $row} 'runtime rollback cannot read personal backup'
$old.backup_layout='unknown';Reject {Get-PaRuntimeBackup $old $row} 'unknown journal layout refused'
# A failed output open must not leak the source handle.
$source=Join-Path $root 'source.txt';[IO.File]::WriteAllText($source,'SOURCE')
$occupied=Join-Path $root 'occupied.txt';[IO.File]::WriteAllText($occupied,'KEEP')
Reject {Copy-PaVerified $source $occupied (Get-PaHash $source)} 'existing backup cannot be overwritten'
$exclusive=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$exclusive.Dispose()
Check ([IO.File]::ReadAllText($occupied) -ceq 'KEEP') 'existing backup bytes preserved'
$result=@{status='passed';checks=$checks;legacy_dotnet_path_policy=$true;nested_personal_backups=$true;unicode=$true;rollback=$true;real_game_written=$false;sandbox=$root}
Write-PaJson (Join-Path $PSScriptRoot 'UPDATE_LEGACY_PATH_RESULTS.json') $result
Write-Output ('Legacy Windows paths: '+$checks+' checks passed; no registry or game changes.')
