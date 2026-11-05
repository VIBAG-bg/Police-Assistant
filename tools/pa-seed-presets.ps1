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
function Set-PaFreshLayout($Settings,$Cfg,$Manifest){
 # Only a fresh installation reaches this path. Shared presets and all existing
 # custom files remain untouched; geometry is a separate sanitized program seed.
 $layout=$Manifest.responsive_layout
 if($null -eq $layout){return}
 $Settings.data.settings.window_layout.default_style='author'
 $Settings.data.settings.window_layout.windows=@{}
 foreach($key in @('main','assist','wanted','fine','mark','ground','quick','tips')){
  $ref=$layout.windows.$key;if($null -eq $ref){throw 'Missing responsive layout reference.'}
  $row=@{displayW=2560;displayH=1440}
  foreach($field in @('width','height','x','y')){
   $n=$ref.$field
   if(-not($n -is [ValueType]) -or [double]::IsNaN([double]$n) -or [double]::IsInfinity([double]$n) -or $n -lt 0 -or $n -gt 32768){throw 'Invalid responsive layout reference.'}
   $row[$field]=$n
  }
  # Keep the seed empty: runtime content floors adapt this reference before
  # the first draw. It becomes a saved user rectangle only after that draw.
 }
 foreach($key in @('x','y','scale','reference_width','reference_height','responsive')){$Cfg.widget[$key]=$layout.widget.$key}
}
function Get-PaPresetSeedPlan([string]$Source,[string]$ML,$Manifest,[bool]$Binds,[bool]$Settings,$IniRow){
 $result=@{plan=@();replace=@{};summary=@{binds='preserved';settings='preserved';notes='preserved'}}
 # An incomplete, older or edited personal set is still an existing installation.
 if($IniRow.Existed){return $result}
 foreach($file in @('police_assistant_2026.lua','pa26_guard.lua','lib/pa26_core.lua','pa26-update.pending')){
  if(Test-Path -LiteralPath (Get-PaSetupPath $ML $file)){return $result}
 }
 $config=Get-PaSetupPath $ML 'config'
 if([IO.Directory]::Exists($config) -and @(Get-ChildItem -LiteralPath $config -Force -Filter 'police_assistant_2026*').Count){return $result}

 $data=Read-PaAuthorPresets $Source $Manifest
 $docs=@{binds=$data.baseline.binds;settings=$data.baseline.settings;notes=$data.baseline.notes}
 if($Binds){$docs.binds=$data['pa-binds']}
 if($Settings){$docs.settings=$data['pa-settings'].settings}
 $cfg=if($Settings){$data['pa-settings'].config}else{$data.baseline.config}
 $docs.settings.data.settings.help=@{welcome=$true;visible=$true;opacity=.74;scale=1.0}
 Set-PaFreshLayout $docs.settings $cfg $Manifest
 $result.summary=@{binds=$(if($Binds){'installed'}else{'standard'});settings=$(if($Settings){'installed'}else{'standard'});notes='two standard notes'}
 $utf8=New-Object Text.UTF8Encoding($false)
 foreach($kind in @('binds','settings','notes')){
  $relative='config/police_assistant_2026_'+$kind+'.json'
  $bytes=$utf8.GetBytes((Write-PaPresetJson $docs[$kind]))
  $result.plan+=,[PSCustomObject]@{Relative=$relative.Replace('/','\');Source=$null;Target=(Get-PaSetupPath $ML $relative);
   SHA256=(Get-PaLegacyByteHash $bytes);Existed=$false;BeforeHash=$null;Skip=$false;Root=$ML;BackupRelative='';Content=$bytes}
 }
 $IniRow.Content=$utf8.GetBytes((Get-PaPresetIni $cfg))
 $IniRow.Source=$null
 $IniRow.SHA256=Get-PaLegacyByteHash $IniRow.Content
 $IniRow.Skip=$false
 return $result
}
