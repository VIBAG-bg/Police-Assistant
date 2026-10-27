# JSON dictionaries retain the empty channel name used for ordinary speech on PowerShell 5.1.
Add-Type -AssemblyName System.Web.Extensions
$paPresetJson=New-Object Web.Script.Serialization.JavaScriptSerializer
$paPresetJson.MaxJsonLength=1048576;$paPresetJson.RecursionLimit=64
function Read-PaPresetJson([string]$Text){return ,$paPresetJson.DeserializeObject($Text)}
function Write-PaPresetJson($Value){return $paPresetJson.Serialize($Value)}
function Get-PaPresetKeys($Value){if($Value -is [Collections.IDictionary]){return @($Value.Keys)};return @($Value.PSObject.Properties|ForEach-Object {$_.Name})}
# Author presets are optional personal-data seeds, never program-updater payloads.
function Test-PaPresetEqual($A,$B){
 if($null -eq $A -or $null -eq $B){return $null -eq $A -and $null -eq $B}
 if($A -is [string] -or $B -is [string]){return ($A -is [string]) -and ($B -is [string]) -and $A -ceq $B}
 if($A -is [bool] -or $B -is [bool]){return ($A -is [bool]) -and ($B -is [bool]) -and $A -eq $B}
 if($A -is [ValueType] -and $B -is [ValueType]){return $A -eq $B}
 if($A -is [Array] -or $B -is [Array]){
  if(-not($A -is [Array]) -or -not($B -is [Array]) -or $A.Count -ne $B.Count){return $false}
  for($i=0;$i -lt $A.Count;$i++){if(-not(Test-PaPresetEqual $A[$i] $B[$i])){return $false}};return $true
 }
 $ak=@(Get-PaPresetKeys $A);$bk=@(Get-PaPresetKeys $B)
 if($ak.Count -ne $bk.Count){return $false}
 foreach($key in $ak){if($bk -cnotcontains $key -or -not(Test-PaPresetEqual $A.$key $B.$key)){return $false}};return $true
}
function Read-PaAuthorPresets([string]$Source,$Manifest){
 $allow=@('presets/manifest.json','presets/pa-binds.json','presets/pa-settings.json','presets/baseline.json');$seen=@{}
 if(@($Manifest.preset_files).Count -ne 4){throw 'Invalid preset manifest.'}
 foreach($row in $Manifest.preset_files){
  if($allow -cnotcontains $row.path -or $seen.ContainsKey($row.path)){throw 'Unexpected preset source.'};$seen[$row.path]=$true
  $path=Join-Path $Source $row.path;Assert-PaSetupPlain $path
  if((Get-Item -LiteralPath $path).Length -gt 1048576 -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256){throw 'Preset source integrity failed.'}
 }
 $data=@{};foreach($name in @('pa-binds','pa-settings','baseline')){$data[$name]=Read-PaPresetJson ([IO.File]::ReadAllText((Join-Path $Source ('presets/'+$name+'.json')),[Text.Encoding]::UTF8))}
 if($data['pa-binds'].format -cne 'police-assistant.binds' -or $data['pa-settings'].format -cne 'police-assistant.author-settings' -or @($data.baseline.notes.notes).Count -ne 2){throw 'Invalid preset formats.'}
 return $data
}
function Get-PaPresetIni($Cfg){
 $lines=@('; Police Assistant 2026 | author defaults | UTF-8')
 foreach($section in (Get-PaPresetKeys $Cfg)){$lines+=('['+$section+']');foreach($key in (Get-PaPresetKeys $Cfg[$section])){$value=$Cfg[$section][$key];if($value -is [bool]){$value=$value.ToString().ToLowerInvariant()}elseif($value -is [ValueType]){$value=[Convert]::ToString($value,[Globalization.CultureInfo]::InvariantCulture)};$lines+=($key+'='+$value)};$lines+=''}
 return ($lines -join "`n")+"`n"
}
function Test-PaStockIni([string]$Text,$Default){
 $parsed=@{};$section=''
 foreach($line in ($Text -split '\r?\n')){
  $line=$line.Trim();if(-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
  if($line -cmatch '^\[([A-Za-z_]+)\]$'){$section=$Matches[1];if($parsed.ContainsKey($section)){return $false};$parsed[$section]=@{};continue}
  if(-not $section -or $line -cnotmatch '^([A-Za-z_]+)=(.*)$'){return $false};$key=$Matches[1];$value=$Matches[2];if($parsed[$section].ContainsKey($key)){return $false};$parsed[$section][$key]=$value
 }
 if($parsed.Count -ne @(Get-PaPresetKeys $Default).Count){return $false}
 foreach($group in (Get-PaPresetKeys $Default)){
  if(-not $parsed.ContainsKey($group) -or $parsed[$group].Count -ne @(Get-PaPresetKeys $Default[$group]).Count){return $false}
  foreach($key in (Get-PaPresetKeys $Default[$group])){
   if(-not $parsed[$group].ContainsKey($key)){return $false};$a=$parsed[$group][$key];$b=$Default[$group][$key]
   if($b -is [bool]){if($a.ToLowerInvariant() -cne $b.ToString().ToLowerInvariant()){return $false}}
   elseif($b -is [ValueType]){$n=0.0;if(-not [double]::TryParse($a,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -or $n -ne $b){return $false}}
   elseif($a -cne $b){return $false}
  }
 };return $true
}
function Get-PaPresetSeedPlan([string]$Source,[string]$ML,$Manifest,[bool]$Binds,[bool]$Settings,$IniRow){
 $result=@{plan=@();replace=@{};summary=@{binds='disabled';settings='disabled';notes='preserved'}}
 if(-not $Binds -and -not $Settings){return $result}
 $data=Read-PaAuthorPresets $Source $Manifest;$paths=@{}
 foreach($kind in @('binds','settings','notes')){$paths[$kind]=Join-Path $ML ('config/police_assistant_2026_'+$kind+'.json');Assert-PaSetupPlain $paths[$kind]}
 $base=Join-Path $ML 'config/police_assistant_2026'
 foreach($tail in @('_files_pending.json','_preset_pending.json')){
  foreach($suffix in @('','.bak','.rollback')){if(Test-Path -LiteralPath ($base+$tail+$suffix)){if($Binds){$result.summary.binds='preserved'};if($Settings){$result.summary.settings='preserved'};return $result}}
 }
 $existing=@{};$present=0
 foreach($kind in $paths.Keys){
  foreach($suffix in @('.rollback','.pa26-next','.pa26-previous')){if(Test-Path -LiteralPath ($paths[$kind]+$suffix)){if($Binds){$result.summary.binds='preserved'};if($Settings){$result.summary.settings='preserved'};return $result}}
  if(Test-Path -LiteralPath $paths[$kind]){
   $present++;try{if((Get-Item -LiteralPath $paths[$kind]).Length -gt 1048576){throw 'size'};$existing[$kind]=Read-PaPresetJson ([IO.File]::ReadAllText($paths[$kind],[Text.Encoding]::UTF8))}catch{if($Binds){$result.summary.binds='preserved'};if($Settings){$result.summary.settings='preserved'};return $result}
  }
 }
 if(($present -ne 0 -and $present -ne 3) -or ($IniRow.Existed -and -not(Test-PaStockIni ([IO.File]::ReadAllText($IniRow.Target,[Text.Encoding]::UTF8)) $data.baseline.config))){
  if($Binds){$result.summary.binds='preserved'};if($Settings){$result.summary.settings='preserved'};return $result
 }
 if($present -eq 0 -and ((Test-Path -LiteralPath ($base+'_library.json')) -or @($paths.Values|Where-Object {Test-Path -LiteralPath ($_+'.bak')}).Count)){if($Binds){$result.summary.binds='preserved'};if($Settings){$result.summary.settings='preserved'};return $result}
 $fresh=$present -eq 0;$applyBinds=$Binds -and ($fresh -or (Test-PaPresetEqual $existing.binds $data.baseline.binds))
 $applySettings=$Settings
 if(-not $fresh){
  try{
  $current=Read-PaPresetJson (Write-PaPresetJson $existing.settings)
  $stock=Read-PaPresetJson (Write-PaPresetJson $data.baseline.settings)
  foreach($key in @('profile','partners','next_partner_id','wanted_reminders','filters')){$current.data.$key=$stock.data.$key}
  $current.data.assist.history=$stock.data.assist.history
  $applySettings=$Settings -and (Test-PaPresetEqual $current $stock)
  }catch{if($Binds){$result.summary.binds='preserved'};if($Settings){$result.summary.settings='preserved'};return $result}
 }
 $docs=@{}
 if($fresh){$docs.binds=$data.baseline.binds;$docs.settings=$data.baseline.settings;$docs.notes=$data.baseline.notes;$result.summary.notes='two standard notes'}
 if($applyBinds){$docs.binds=$data['pa-binds'];$result.summary.binds='installed'}elseif($Binds){$result.summary.binds='preserved'}
 if($applySettings){
  $docs.settings=Read-PaPresetJson (Write-PaPresetJson $data['pa-settings'].settings)
  if(-not $fresh){foreach($key in @('profile','partners','next_partner_id','wanted_reminders','filters')){$docs.settings.data.$key=$existing.settings.data.$key};$docs.settings.data.assist.history=$existing.settings.data.assist.history;$docs.settings.data.settings.updates=$existing.settings.data.settings.updates}
  $result.summary.settings='installed'
 }elseif($Settings){$result.summary.settings='preserved'}
 if(-not $docs.Count){return $result}
 $stage=Join-Path $Source ('installation-backups/preset-stage-'+[guid]::NewGuid().ToString('N'));Assert-PaSetupPlain $stage;[IO.Directory]::CreateDirectory($stage)|Out-Null
 foreach($kind in $docs.Keys){
  $from=Join-Path $stage ($kind+'.json');[IO.File]::WriteAllText($from,(Write-PaPresetJson $docs[$kind]),(New-Object Text.UTF8Encoding($false)))
  $to=$paths[$kind];$exists=Test-Path -LiteralPath $to;$hash=(Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash
  $result.plan+=,[PSCustomObject]@{Relative=('config\police_assistant_2026_'+$kind+'.json');Source=$from;Target=$to;SHA256=$hash;Existed=$exists;BeforeHash=$(if($exists){(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash}else{$null});Skip=$false;Root=$ML;BackupRelative=('presets/'+$kind+'.json');Content=$null}
  if($exists){$result.replace[$to]=$hash}
 }
 if($applySettings){
  $from=Join-Path $stage 'config.ini';[IO.File]::WriteAllText($from,(Get-PaPresetIni $data['pa-settings'].config),(New-Object Text.UTF8Encoding($false)))
  $IniRow.Source=$from;$IniRow.SHA256=(Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash;$IniRow.Skip=$false
  if($IniRow.Existed){$result.replace[$IniRow.Target]=$IniRow.SHA256}
 }
 return $result
}
