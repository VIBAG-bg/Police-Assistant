Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'tools/pa-setup.ps1')
. (Join-Path $release 'tools/pa-seed-presets.ps1')
$manifest=Get-Content (Join-Path $release 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
$data=Read-PaAuthorPresets $release $manifest
$root=Join-Path $release ('tests/install-sandbox/author-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($root)|Out-Null
$checks=0
function Check($value,$why){$script:checks++;if(-not $value){throw ('ASSERT: '+$why)}}
function New-Case([string]$Name,[bool]$Stock=$false){
 $ml=Join-Path $root ($Name+'/MoonLoader');[IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
 $ini=Join-Path $ml 'config/police_assistant_2026.ini'
 if($Stock){
  [IO.File]::WriteAllText($ini,(Get-PaPresetIni $data.baseline.config),(New-Object Text.UTF8Encoding($false)))
  foreach($kind in @('binds','settings','notes')){[IO.File]::WriteAllText((Join-Path $ml ('config/police_assistant_2026_'+$kind+'.json')),(Write-PaPresetJson $data.baseline.$kind),(New-Object Text.UTF8Encoding($false)))}
 }
 return @{ml=$ml;ini=[PSCustomObject]@{Target=$ini;Existed=(Test-Path $ini);Source='';SHA256='';Skip=$true}}
}
foreach($mode in @(@($true,$true),@($true,$false),@($false,$true),@($false,$false))){
 $c=New-Case ([guid]::NewGuid().ToString('N'))
 $plan=Get-PaPresetSeedPlan $release $c.ml $manifest $mode[0] $mode[1] $c.ini
 Check ($plan.plan.Count -eq $(if($mode[0] -or $mode[1]){3}else{0})) 'fresh options create a complete split set or nothing'
 if($plan.plan.Count){
  $bind=@($plan.plan|Where-Object Relative -Like '*_binds.json')[0];$note=@($plan.plan|Where-Object Relative -Like '*_notes.json')[0]
  Check (@((Get-Content $bind.Source -Raw|ConvertFrom-Json).bindings).Count -eq $(if($mode[0]){83}else{6})) 'bind checkbox is independent'
  Check (@((Get-Content $note.Source -Raw|ConvertFrom-Json).notes).Count -eq 2) 'exactly two public notes'
  Check (-not(Test-Path (Join-Path $c.ml 'config/police_assistant_2026_settings.json'))) 'planning does not write game data'
  if($mode[1]){Check ((Get-Content -LiteralPath $c.ini.Source -Raw) -match '(?m)^demo_mode=false$') 'fresh author settings start in real mode'}
 }
}
$c=New-Case 'stock' $true;$p=Get-PaPresetSeedPlan $release $c.ml $manifest $true $true $c.ini
Check ($p.summary.binds -ceq 'installed' -and $p.summary.settings -ceq 'installed') 'untouched defaults can be seeded'
$c=New-Case 'private-profile' $true;$path=Join-Path $c.ml 'config/police_assistant_2026_settings.json';$value=Read-PaPresetJson (Get-Content $path -Raw -Encoding UTF8);$value.data.profile.name='PRIVATE NAME';Write-PaPresetJson $value|Set-Content $path -Encoding UTF8
$p=Get-PaPresetSeedPlan $release $c.ml $manifest $true $true $c.ini
$row=@($p.plan|Where-Object Relative -Like '*_settings.json')[0];Check ((Read-PaPresetJson (Get-Content $row.Source -Raw -Encoding UTF8)).data.profile.name -ceq 'PRIVATE NAME') 'private profile survives default-setting seed'
$value.data.settings.opacity=.63;Write-PaPresetJson $value|Set-Content $path -Encoding UTF8
$p=Get-PaPresetSeedPlan $release $c.ml $manifest $true $true $c.ini
Check ($p.summary.settings -ceq 'preserved' -and $p.summary.binds -ceq 'installed') 'one custom setting protects settings without replacing bind choice'
$bindPath=Join-Path $c.ml 'config/police_assistant_2026_binds.json';$value=Get-Content $bindPath -Raw -Encoding UTF8|ConvertFrom-Json;$value.bindings[0].name='MY BIND';$value|ConvertTo-Json -Depth 64|Set-Content $bindPath -Encoding UTF8
$p=Get-PaPresetSeedPlan $release $c.ml $manifest $true $true $c.ini;Check ($p.plan.Count -eq 0) 'custom binds and settings are both preserved'
$c=New-Case 'partial';[IO.File]::WriteAllText((Join-Path $c.ml 'config/police_assistant_2026_binds.json'),'{}');$p=Get-PaPresetSeedPlan $release $c.ml $manifest $true $true $c.ini;Check ($p.plan.Count -eq 0) 'partial or corrupt personal set is never guessed empty'
$c=New-Case 'custom-ini' $true;[IO.File]::AppendAllText($c.ini.Target,"`n[other]`na=1");$p=Get-PaPresetSeedPlan $release $c.ml $manifest $true $true $c.ini;Check ($p.plan.Count -eq 0) 'custom INI blocks conflicting automatic seeds'
# Run the actual existing installer, not a second copy of its transaction.
$c=New-Case 'real-install'
& (Join-Path $release 'install.ps1') -DestinationRoot $c.ml|Out-Null
$file=Join-Path $c.ml 'config/police_assistant_2026_binds.json'
Check (@((Get-Content $file -Raw|ConvertFrom-Json).bindings).Count -eq 83) 'actual fresh installer installs author binds'
$notes=Join-Path $c.ml 'config/police_assistant_2026_notes.json';Check (@((Get-Content $notes -Raw|ConvertFrom-Json).notes).Count -eq 2) 'actual fresh install has only stock notes'
$saved=@{};foreach($f in Get-ChildItem (Join-Path $c.ml 'config') -File){$saved[$f.FullName]=(Get-FileHash $f.FullName).Hash}
& (Join-Path $release 'install.ps1') -DestinationRoot $c.ml|Out-Null
foreach($key in $saved.Keys){Check ((Get-FileHash $key).Hash -ceq $saved[$key]) 'reinstallation preserves every existing personal byte'}
$c=New-Case 'rollback';$failed=$false;try{& (Join-Path $release 'install.ps1') -DestinationRoot $c.ml -TestFailAfter 5|Out-Null}catch{$failed=$true}
Check $failed 'injected installer fault';Check (@(Get-ChildItem $c.ml -File -Recurse).Count -eq 0) 'fresh failure leaves no partial preset files'
@{status='passed';checks=$checks;source_notes_not_read=$true;real_game_written=$false;sandbox=$root}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'AUTHOR_INSTALL_RESULTS.json') -Encoding UTF8
Write-Output ('Author install: '+$checks+' checks passed.')
