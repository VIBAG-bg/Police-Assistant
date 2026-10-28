Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
[AppContext]::SetSwitch('Switch.System.IO.UseLegacyPathHandling',$true)
[AppContext]::SetSwitch('Switch.System.IO.BlockLongPaths',$true)
$switches=[IO.Path].Assembly.GetType('System.AppContextSwitches')
if(-not $switches){throw 'Run with Windows PowerShell 5.1.'}
foreach($name in @('_useLegacyPathHandling','_blockLongPaths')){
 $field=$switches.GetField($name,[Reflection.BindingFlags]'NonPublic,Static');if(-not $field){throw 'Legacy path policy unavailable'};$field.SetValue($null,0)
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('pa41i-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$package=Join-Path $root 'release';[IO.Directory]::CreateDirectory($package)|Out-Null
$manifest=Get-Content -LiteralPath (Join-Path $release 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
$files=@('install.ps1','INSTALL_MANIFEST.json','CEF_CONTRACT.json')
$files+=@($manifest.files|ForEach-Object {'moonloader/'+$_.path.Replace('\','/')})
$files+=@($manifest.cef_files|ForEach-Object {'cef/assets/hud/'+$_.path})
$files+=@($manifest.setup_files|ForEach-Object {$_.path})
$files+=@($manifest.preset_files|ForEach-Object {$_.path})
foreach($relative in $files){
 $target=Join-Path $package $relative;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
 [IO.File]::Copy((Join-Path $release $relative),$target)
}
$checks=0
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
foreach($kind in @('success','rollback')){
 $ml=Join-Path $package ('tests/install-sandbox/'+$kind+'/MoonLoader');$config=Join-Path $ml 'config'
 [IO.Directory]::CreateDirectory($config)|Out-Null
 [IO.File]::WriteAllText((Join-Path $ml 'police_assistant_2026.lua'),'OLD ENTRY')
 $snapshot=@{}
 foreach($parent in @($config,(Join-Path $config ('police_assistant_2026_preset_backup_'+('a'*32))))){
  [IO.Directory]::CreateDirectory($parent)|Out-Null
  foreach($name in @('police_assistant_2026_binds.json','police_assistant_2026_settings.json.bak','police_assistant_2026_notes.json')){
   $path=Join-Path $parent $name;[IO.File]::WriteAllText($path,('PERSONAL '+$parent+'/'+$name));$snapshot[$path]=(Get-FileHash -LiteralPath $path).Hash
  }
 }
 $args=@{DestinationRoot=$ml;SkipAuthorBinds=$true;SkipAuthorSettings=$true}
 if($kind -eq 'rollback'){$args.TestFailAfter=3}
 $failed=$false
 try{$output=@(& (Join-Path $package 'install.ps1') @args)}catch{if($kind -ne 'rollback' -or $_.Exception.Message -notlike '*Injected installation failure*'){throw};$failed=$true}
 foreach($path in $snapshot.Keys){Check ((Get-FileHash -LiteralPath $path).Hash -ceq $snapshot[$path]) 'legacy installer preserves original personal bytes'}
 if($kind -eq 'rollback'){
  Check $failed 'injected installer failure'
  Check ([IO.File]::ReadAllText((Join-Path $ml 'police_assistant_2026.lua')) -ceq 'OLD ENTRY') 'legacy installer restores original entry'
 }else{
  $expectedRelease=(Get-Content -LiteralPath (Join-Path $package 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json).release
  Check ([IO.File]::ReadAllText((Join-Path $ml 'police_assistant_2026.lua')).Contains("script_version('$expectedRelease')")) 'legacy installer installs current version'
  $line=$output|Where-Object {$_ -is [string] -and $_ -match ' Backup: (.+)$'}|Select-Object -Last 1
  Check ($line -match ' Backup: (.+)$') 'installer reports exact backup identity'
  $backup=$Matches[1];$map=@((Get-Content -LiteralPath (Join-Path $backup 'PERSONAL.json') -Raw|ConvertFrom-Json))
  Check ($map.Count -eq $snapshot.Count) 'nested personal backups all mapped'
  $destinations=@{}
  foreach($row in $map){
   Check ($row.backup_file -cmatch '^personal\\[0-9]{6}\.bin$') 'short installer backup name'
   Check (-not $destinations.ContainsKey($row.backup_file)) 'duplicate basenames cannot collide';$destinations[$row.backup_file]=$true
   Check ((Get-FileHash -LiteralPath (Join-Path $backup $row.backup_file)).Hash -ceq $row.sha256) 'legacy installer backup bytes verified'
  }
 }
}
@{status='passed';checks=$checks;legacy_dotnet_path_policy=$true;nested_backups=$true;rollback=$true;real_game_written=$false;sandbox=$root}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'INSTALLER_LEGACY_PATH_RESULTS.json') -Encoding UTF8
Write-Output ('Legacy installer paths: '+$checks+' checks passed; no game or registry changes.')
