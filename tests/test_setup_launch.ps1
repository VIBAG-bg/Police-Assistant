# Exercise the NORMAL script invocation, not functions imported into test scope.
# The callback-scope bug was hidden by library-only checks. No installation here.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path $release ('tests/install-sandbox/launch-'+[guid]::NewGuid().ToString('N'))
$game=Join-Path $root ('Game '+[char]0x0418+' with spaces')
$ml=Join-Path $game 'MoonLoader'
[IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
foreach($name in @('gta_sa.exe','moonloader.asi','lua51.dll')){[IO.File]::WriteAllText((Join-Path $game $name),'SYNTHETIC TEST ONLY')}
$personal=Join-Path $ml 'config/police_assistant_2026_binds.json'
[IO.File]::WriteAllText($personal,'PERSONAL BINDS - MUST NOT CHANGE')
$before=(Get-FileHash -LiteralPath $personal -Algorithm SHA256).Hash
$launchContext=@{checks=0;steps=0;error=$null;ticks=0}
$assertLaunch={param($value,[string]$why)$launchContext.checks++;if(-not $value){throw ('ASSERT: '+$why)}}.GetNewClosure()
Add-Type -AssemblyName System.Windows.Forms
$watch=New-Object Windows.Forms.Timer;$watch.Interval=300
$watch.Add_Tick({
 $launchContext.ticks++
 $forms=[Windows.Forms.Application]::OpenForms;$window=$null
 for($index=0;$index -lt $forms.Count;$index++){
  $candidate=$forms.Item($index)
  if($candidate.GetType().Name -ceq 'PaSetupWindow'){$window=$candidate;break}
 }
 if($launchContext.ticks -ge 30){$launchContext.error='Normal-entry UI timed out';[Windows.Forms.Application]::ExitThread();$watch.Stop();return}
 if(-not $window){return}
 try{
  if($launchContext.steps -eq 0){
   & $assertLaunch $window.Install.Enabled 'real -File/& entry resolves preflight helpers'
   & $assertLaunch $window.Requirements.Text.Contains('SA:MP') 'preflight status reaches normal entry window'
   $window.PathBox.Text=$root
   & $assertLaunch (-not $window.Install.Enabled) 'invalid game cannot be installed'
   & $assertLaunch $window.Requirements.Text.Contains('gta_sa.exe') 'error formatter resolves in actual TextChanged callback'
   $window.PathBox.Text=$game
   & $assertLaunch $window.Install.Enabled 'correct path recovers without restarting'
   $launchContext.steps=1
  }elseif($launchContext.steps -eq 1){
   & $assertLaunch $window.Requirements.Text.Contains('SA:MP') 'polling timer retains helper access after callback returns'
   $launchContext.steps=2;$window.Terminal=$true;$window.Close();$watch.Stop()
  }
 }catch{$launchContext.error=$_.Exception.Message;$window.Terminal=$true;$window.Close();$watch.Stop()}
 if($launchContext.ticks -ge 30){$launchContext.error='Normal-entry UI timed out';$window.Terminal=$true;$window.Close();$watch.Stop()}
}.GetNewClosure())
function Invoke-PaInstallerEntry {
 Write-Output 'Normal-entry test: invoking original setup script.'
 & (Join-Path $release 'tools/pa-setup-window.ps1') -InitialPath $game
 Write-Output 'Normal-entry test: original setup script returned.'
}
try{$watch.Start();Invoke-PaInstallerEntry}finally{$watch.Stop();$watch.Dispose()}
if($launchContext.error){throw $launchContext.error}
& $assertLaunch ($launchContext.steps -eq 2) 'actual script window completed both event cycles'
& $assertLaunch ((Get-FileHash -LiteralPath $personal -Algorithm SHA256).Hash -ceq $before) 'normal-entry preflight preserves personal bytes'
& $assertLaunch (-not (Test-Path -LiteralPath (Join-Path $ml 'police_assistant_2026.lua'))) 'no install without user consent'
@{status='passed';checks=$launchContext.checks;normal_script_entry=$true;window_event_cycles=2;real_game_written=$false;windows7_vm_tested=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'SETUP_LAUNCH_RESULTS.json') -Encoding UTF8
'Normal installer launch: '+$launchContext.checks+' checks passed; original script scope, actual events, no game writes.'
