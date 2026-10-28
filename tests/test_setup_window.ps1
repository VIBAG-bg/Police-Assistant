param([switch]$Render)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'tools/pa-start.ps1') -Library
$checks=0
function Check($Value,[string]$Why){$script:checks++;if(-not $Value){throw ('ASSERT: '+$Why)}}
function Reject([scriptblock]$Code,[string]$Why){$failed=$false;try{&$Code|Out-Null}catch{$failed=$true};Check $failed $Why}
foreach($spec in @(@('6.1',1,'5.1',528049),@('10.0',0,'5.1',528372),@('10.0',0,'5.1',533320))){
 Check ((Get-PaCompatibilityIssue ([version]$spec[2]) ([version]$spec[0]) $spec[1] $spec[3]) -ceq '') 'Windows 7 SP1 / 10 / 11 with prerequisites accepted'
}
Check ((Get-PaCompatibilityIssue ([version]'2.0') ([version]'6.1') 1 528049) -ceq 'powershell') 'old Windows 7 PowerShell caught before modern parser'
Check ((Get-PaCompatibilityIssue ([version]'5.0') ([version]'10.0') 0 528049) -ceq 'powershell') 'PowerShell 5.0 refused'
Check ((Get-PaCompatibilityIssue ([version]'5.1') ([version]'6.1') 0 528049) -ceq 'service_pack') 'Windows 7 without SP1 explained'
Check ((Get-PaCompatibilityIssue ([version]'5.1') ([version]'6.1') 1 0) -ceq 'framework') 'missing .NET explained'
Check ((Get-PaCompatibilityIssue ([version]'5.1') ([version]'6.0') 2 528049) -ceq 'windows') 'older Windows refused'
$starter=[IO.File]::ReadAllText((Join-Path $release 'tools/pa-start.ps1'))
Check ($starter -notmatch '\s-(?:c?notin|c?in|shl|shr)\b|\[ordered\]|\[pscustomobject\]|::new\(') 'bootstrap avoids newer PowerShell syntax'
foreach($name in @('Установить PA.cmd','Показать обновление PA.cmd')){
 $cmd=[IO.File]::ReadAllBytes((Join-Path $release $name));Check (@($cmd|Where-Object {$_ -gt 127}).Count -eq 0) 'CMD does not depend on the Windows 7 console codepage'
 Check ([Text.Encoding]::ASCII.GetString($cmd).Contains('tools\pa-start.ps1')) 'all desktop entry points use compatibility check'
}
. (Join-Path $release 'tools/pa-setup-window.ps1') -Library
$root=Join-Path $release ('tests/install-sandbox/window-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$game=Join-Path $root 'Игра и пробелы';[IO.Directory]::CreateDirectory($game)|Out-Null
foreach($name in @('gta_sa.exe','moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $game $name),'FIXTURE ONLY')}
$ml=Join-Path $game 'MoonLoader';[IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
$personal=Join-Path $ml 'config/police_assistant_2026_binds.json';[IO.File]::WriteAllText($personal,'PERSONAL BINDS')
$before=(Get-FileHash -LiteralPath $personal -Algorithm SHA256).Hash
$pre=Get-PaSetupPreflight $game
Check ($pre.missing -eq 3 -and $pre.moonloader -ieq $ml) 'preflight resolves unicode GTA root and three missing libraries'
Check (-not (Test-Path -LiteralPath (Join-Path $ml 'lib'))) 'preflight does not download or write game libraries'
Check ($pre.details.Contains('SA:MP')) 'native client identified'
Reject {Get-PaSetupPreflight (Join-Path $root 'missing-game')} 'invalid folder refused'
Reject {Start-PaSetupChild $ml (Join-Path $root 'escape')} 'child job must be in bounded installation folder'
$progressEscape=Join-Path $root 'outside.json'
Reject {& (Join-Path $release 'install.ps1') -DestinationRoot $ml -ProgressFile $progressEscape} 'installer cannot write arbitrary status file'
Check (-not (Test-Path -LiteralPath $progressEscape)) 'refused progress path stays absent'
function Run-Child([int]$Fault){
 $job=Join-Path $release ('installation-backups/ui-jobs/'+[guid]::NewGuid().ToString('N'))
 $child=Start-PaSetupChild $ml $job '' $Fault
 try{
  Check ($child.WaitForExit(60000)) 'isolated installer child exited'
  $child.Refresh();$result=Read-PaSetupJob $job
  if($Fault){Check ($child.ExitCode -ne 0 -and $result.stage -ceq 'failed' -and $result.safe) 'failure receipt follows completed rollback'}
  else{Check ($child.ExitCode -eq 0 -and $result.stage -ceq 'completed' -and $result.percent -eq 100 -and $result.safe -and $result.version -ceq $paSetupManifest.release) 'success requires verified final receipt'}
  Check ((Get-FileHash -LiteralPath $personal -Algorithm SHA256).Hash -ceq $before) 'child preserves personal binds'
  return $job
 }finally{$child.Dispose()}
}
$failedJob=Run-Child 2
Check (-not (Test-Path -LiteralPath (Join-Path $ml 'police_assistant_2026.lua'))) 'failed fresh install rolls back created program files'
$goodJob=Run-Child 0
$bad=Read-PaSetupJob $goodJob;$bad.job='f'*32;Write-PaJson (Join-Path $goodJob 'progress.json') $bad
Reject {Read-PaSetupJob $goodJob} 'another job cannot report setup success'
if($Render){
 $unused=New-PaProgressForm;$unused.Dispose();$form=New-PaSetupForm
 try{
  $form.PathBox.Text=$ml;$form.Requirements.Text=$pre.details;$form.Install.Enabled=$true
  $form.Show();[Windows.Forms.Application]::DoEvents();$form.PerformLayout()
  foreach($stage in @('setup','installing')){
   if($stage -ceq 'installing'){$form.BeginInstallation();$form.SetState('INSTALLING UPDATE','Устанавливаю и проверяю файлы PA.',82,'green',$false,$false,$paSetupManifest.release)}
   $form.PerformLayout();$form.Refresh();[Windows.Forms.Application]::DoEvents()
   $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
   try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path $root ($stage+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
  }
  Check (-not $form.Done.Enabled -and -not $form.Install.Visible) 'installation cannot be started twice or prematurely closed'
  Check ($form.Percent.Right -le $form.ProgressBox.ClientSize.Width) 'percentage remains within progress grid'
 }finally{$form.Terminal=$true;$form.Dispose()}
 # Exercise the real selector, click and polling loop against the bounded fixture.
 $script:AutoSetupForm=New-PaSetupForm;$original=(Get-Command New-PaSetupForm).ScriptBlock
 function New-PaSetupForm {return $script:AutoSetupForm}
 $InitialPath=$game;$watch=New-Object Windows.Forms.Timer;$watch.Interval=300;$script:ticks=0;$script:uiStarted=$false;$script:uiSuccess=$false;$script:uiInvalidExplained=$false
 $watch.Add_Tick({
  $script:ticks++
  if(-not $script:uiInvalidExplained){
   $script:AutoSetupForm.PathBox.Text=$root
   Check (-not $script:AutoSetupForm.Install.Enabled -and $script:AutoSetupForm.Requirements.Text.Contains('gta_sa.exe')) 'real TextChanged handler resolves error explanation in script scope'
   $script:uiInvalidExplained=$true;$script:AutoSetupForm.PathBox.Text=$game
  }
  if(-not $script:uiStarted -and $script:AutoSetupForm.Install.Enabled){$script:uiStarted=$true;$script:AutoSetupForm.Install.PerformClick()}
  if($script:AutoSetupForm.LastStage -ceq 'SUCCESS'){$script:uiSuccess=$true}
  if($script:uiSuccess -or $script:ticks -ge 120){$script:AutoSetupForm.Terminal=$true;$script:AutoSetupForm.Close();$watch.Stop()}
 })
 try{$watch.Start();Show-PaSetupWindow;Check $script:uiInvalidExplained 'invalid path explained without callback scope errors';Check $script:uiStarted 'real installer button starts child';Check $script:uiSuccess 'real timer reaches verified success'}finally{$watch.Stop();$watch.Dispose();Set-Item Function:New-PaSetupForm $original}
}
@{status='passed';checks=$checks;compatibility_matrix=@('Windows 7 SP1 prerequisites','Windows 10','Windows 11');windows7_vm_tested=$false;rendered=[bool]$Render;real_game_written=$false;sandbox=$root}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'SETUP_WINDOW_RESULTS.json') -Encoding UTF8
Write-Output ('Setup window: '+$checks+' checks passed. Preview: '+$root)
