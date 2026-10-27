param([switch]$Render)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'moonloader/resource/pa26/updater/pa26-update.ps1') -Mode Library
$root=Join-Path $PSScriptRoot ('update-sandbox/progress-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null;$script:PaBase=Join-Path $root 'store'
$checks=0;$script:running=$false
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
function Reject([scriptblock]$fn,[string]$why){$bad=$false;try{&$fn|Out-Null}catch{$bad=$true};Check $bad $why}
function Get-PaGameRunning {return $script:running}
function New-Case {
 $ml=Join-Path $root ([guid]::NewGuid().ToString('N')+'/game/MoonLoader');[IO.Directory]::CreateDirectory($ml)|Out-Null
 [IO.File]::WriteAllText((Join-Path $ml 'police_assistant_2026.lua'),"script_version('0.40.1')")
 $job=Join-Path $script:PaBase ('jobs/'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($job)|Out-Null
 Initialize-PaPaths $ml $job;$script:PaPresentation=$true;$script:PaTargetVersion='0.40.2';$script:running=$false
}
function EqualView($v,[string]$heading,[bool]$safe,[bool]$terminal){Check ($v.heading -ceq $heading) $heading;Check ($v.safe -eq $safe) 'safe-to-start flag';Check ($v.terminal -eq $terminal) 'terminal flag'}
New-Case
$v=Get-PaProgressView;EqualView $v 'STARTING' $false $false
Set-PaProgress 'downloading' 27 'Receiving approved archive.';Set-PaStatus 'downloading' 'downloading' @{version='0.40.2'}
$v=Get-PaProgressView;EqualView $v 'DOWNLOADING UPDATE' $false $false;Check ($v.percent -eq 27) 'measured progress shown'
Set-PaProgress 'backup' 63 'Saving your personal data.'
$v=Get-PaProgressView;Check ($v.heading -ceq 'BACKING UP YOUR DATA') 'backup stage'
Set-PaProgress 'finishing' 100 'Not committed yet.'
$v=Get-PaProgressView;Check ($v.percent -eq 99 -and -not $v.safe) '100 cannot be published by progress alone'
$status=Read-PaSharedJson (Join-Path $script:PaJob 'status.json');$status.job='a'*32
Write-PaJson (Join-Path $script:PaJob 'status.json') $status
Reject {Get-PaProgressView} 'different update owner rejected'
Set-PaStatus 'installed' 'update_installed' @{version='0.40.2'}
$v=Get-PaProgressView;EqualView $v 'FINISHING SAFELY' $false $false
[IO.File]::WriteAllText((Join-Path $script:PaML 'police_assistant_2026.lua'),"script_version('0.40.2')")
Write-PaMarker ([IO.Path]::GetFileName($script:PaJob))
$v=Get-PaProgressView;EqualView $v 'FINISHING SAFELY' $false $false
$status=Read-PaSharedJson (Join-Path $script:PaJob 'status.json');$status.utc=[DateTime]::UtcNow.AddSeconds(-20).ToString('o');Write-PaJson (Join-Path $script:PaJob 'status.json') $status
$v=Get-PaProgressView;EqualView $v 'UPDATE INTERRUPTED' $false $true
[IO.File]::Delete($script:PaMarker)
$v=Get-PaProgressView;EqualView $v 'SUCCESS' $true $true;Check ($v.percent -eq 100) 'success is exactly 100'
$success=$v
New-Case;Set-PaStatus 'error' 'network_error';$v=Get-PaProgressView;EqualView $v 'UPDATE NOT INSTALLED' $true $true
Write-PaMarker ([IO.Path]::GetFileName($script:PaJob));$v=Get-PaProgressView;Check (-not $v.safe) 'error with gate forbids restart'
New-Case;Set-PaStatus 'rolled_back' 'update_rolled_back';$v=Get-PaProgressView;EqualView $v 'PREVIOUS VERSION RESTORED' $true $true
Check ($v.heading -cne 'SUCCESS' -and $v.percent -lt 100) 'rollback never looks like successful installation'
New-Case;Set-PaProgress 'installing' 78 'Installing 2 / 3 files.';Set-PaStatus 'waiting' 'close_game_to_continue'
Write-PaMarker ([IO.Path]::GetFileName($script:PaJob));$script:running=$true
$v=Get-PaProgressView;EqualView $v 'GTA REOPENED - PLEASE CLOSE IT' $false $false;Check ($v.percent -eq 78) 'pause keeps real progress'
$paused=$v;$script:running=$false
New-Case;Set-PaStatus 'waiting' 'downloaded_close_game'
$path=Join-Path $script:PaML 'police_assistant_2026.lua'
$journal=@{product='police-assistant-2026';job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;version='0.40.1';phase='applying';touched=1;plan=@(@{path='MoonLoader/police_assistant_2026.lua';sha256=Get-PaHash $path},@{path='MoonLoader/lib/pa26_a.lua'},@{path='MoonLoader/lib/pa26_b.lua'})}
Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
$v=Get-PaProgressView;EqualView $v 'INSTALLING UPDATE' $false $false;Check ($v.percent -gt 70) 'old worker journal provides measured progress'
New-Case;Set-PaStatus 'waiting' 'downloaded_close_game'
$path=Join-Path $script:PaML 'police_assistant_2026.lua'
$journal=@{product='police-assistant-2026';job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;version='0.40.1';phase='committed';touched=1;plan=@(@{path='MoonLoader/police_assistant_2026.lua';sha256=Get-PaHash $path})}
Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
Set-PaStatus 'error' 'receipt_io_error';$v=Get-PaProgressView;EqualView $v 'SUCCESS' $true $true
$journal.job='e'*32;Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
Reject {Get-PaProgressView} 'another journal cannot prove successful installation'
$journal.job=[IO.Path]::GetFileName($script:PaJob);Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
[IO.File]::WriteAllText($path,'DAMAGED AFTER COMMIT');$v=Get-PaProgressView;EqualView $v 'UPDATE NOT INSTALLED' $false $true
New-Case;Set-PaStatus 'waiting' 'downloaded_close_game'
Write-PaJson (Join-Path $script:PaState 'active.json') @{job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;pid=2147483647;started=1}
$v=Get-PaProgressView;EqualView $v 'UPDATE INTERRUPTED' $true $true
Write-PaMarker ([IO.Path]::GetFileName($script:PaJob));$v=Get-PaProgressView;Check (-not $v.safe) 'interrupted install stays protected'
New-Case;Set-PaStatus 'current' 'no_new_version';$v=Get-PaProgressView;EqualView $v 'ALREADY UP TO DATE' $true $true
if($Render){
 $form=New-PaProgressForm
 try{
  $form.Show();[Windows.Forms.Application]::DoEvents();$form.PerformLayout()
  foreach($spec in @(@('success',$success),@('paused',$paused))){
   $v=$spec[1];$form.SetState($v.heading,$v.detail,$v.percent,$v.tone,$v.terminal,$v.safe,$v.version);$form.PerformLayout();$form.Refresh();[Windows.Forms.Application]::DoEvents()
   Check ($form.Done.Enabled -eq $v.terminal) 'real close button follows terminal state'
   $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
   try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path $root ($spec[0]+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
  }
 }finally{$form.Terminal=$true;$form.Dispose()}
 # Exercise the actual responsive observer loop, not just a painted mock.
 New-Case;Set-PaProgress 'backup' 63 'Saving user data.';Set-PaStatus 'downloading' 'downloading'
 $script:AutoForm=New-PaProgressForm;$original=(Get-Command New-PaProgressForm).ScriptBlock
 function New-PaProgressForm {return $script:AutoForm}
 $script:UITicks=0;$script:UIObserved=$false;$script:UISuccess=$false;$watch=New-Object Windows.Forms.Timer;$watch.Interval=150
 $watch.Add_Tick({
  $script:UITicks++
  if($script:AutoForm.LastStage -ceq 'BACKING UP YOUR DATA'){
   $script:UIObserved=$true
   [IO.File]::WriteAllText((Join-Path $script:PaML 'police_assistant_2026.lua'),"script_version('0.40.2')")
   Set-PaStatus 'installed' 'update_installed' @{version='0.40.2'}
  }
  if($script:AutoForm.LastStage -ceq 'SUCCESS'){$script:UISuccess=$true}
  if($script:UISuccess -or $script:UITicks -ge 20){$script:AutoForm.Terminal=$true;$script:AutoForm.Close();$watch.Stop()}
 })
 try{$watch.Start();Show-PaProgressWindow;Check $script:UIObserved 'real timer displayed backup state';Check $script:UISuccess 'real timer reached verified success';Check ([IO.File]::Exists((Join-Path $script:PaJob 'view.ready.json'))) 'observer readiness recorded'}
 finally{$watch.Stop();$watch.Dispose();Set-Item Function:New-PaProgressForm $original}
}
@{status='passed';checks=$checks;native_window_rendered=[bool]$Render;sandbox=$root;real_game_written=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'UPDATE_PROGRESS_RESULTS.json') -Encoding UTF8
Write-Output ('Update progress: '+$checks+' checks passed. Preview folder: '+$root)
