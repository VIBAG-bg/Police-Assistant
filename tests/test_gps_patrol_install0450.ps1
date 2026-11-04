Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path $release ('tests/install-sandbox/gps-patrol-'+[guid]::NewGuid().ToString('N'))
$ml=Join-Path $root 'MoonLoader'
[IO.Directory]::CreateDirectory((Join-Path $ml 'config'))|Out-Null
$checks=0
function Check($value,$why){$script:checks++;if(-not $value){throw ('ASSERT: '+$why)}}
$ini=Join-Path $ml 'config/police_assistant_2026.ini'
[IO.File]::WriteAllText($ini,'PERSONAL INI')
$personal=@{}
foreach($name in @('binds','settings','notes')){
 $path=Join-Path $ml ('config/police_assistant_2026_'+$name+'.json')
 [IO.File]::WriteAllText($path,('PERSONAL '+$name));$personal[$path]=(Get-FileHash $path -Algorithm SHA256).Hash
}
$personal[$ini]=(Get-FileHash $ini -Algorithm SHA256).Hash
& (Join-Path $release 'install.ps1') -DestinationRoot $ml -SkipAuthorBinds -SkipAuthorSettings | Out-Null
$manifest=Get-Content (Join-Path $release 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
foreach($row in $manifest.files){
 if($row.path -like 'config\*'){continue}
 $path=Join-Path $ml $row.path
 Check ((Get-FileHash $path -Algorithm SHA256).Hash -ieq $row.sha256) 'installed runtime bytes match manifest'
}
foreach($path in $personal.Keys){Check ((Get-FileHash $path -Algorithm SHA256).Hash -ceq $personal[$path]) 'personal file unchanged'}
Check (Test-Path (Join-Path $ml 'lib/pa26_navigation_roads.lua')) 'new graph module included'
Check (-not(Test-Path (Join-Path $root 'exsellent/gps/roads.bin'))) 'no second copy in launcher-owned folders'
Check ((Get-FileHash (Join-Path $ml 'resource/pa26/roads.bin') -Algorithm SHA256).Hash -ieq 'c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db') 'bundled graph installed intact without launcher files'
Check (-not(Test-Path (Join-Path $root 'cef'))) 'native fixture never receives launcher files'
@{version='0.45.0';status='passed';checks=$checks;game_written=$false;fixture_only=$true;manifest_entries=$manifest.files.Count;
 manifest_sha256=(Get-FileHash (Join-Path $release 'INSTALL_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant();
 installer_sha256=(Get-FileHash (Join-Path $release 'install.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()} |
 ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'GPS_PATROL_INSTALL0450.json') -Encoding UTF8
Write-Output ('GPS/patrol install fixture: '+$checks+' checks passed; no live game changes.')
