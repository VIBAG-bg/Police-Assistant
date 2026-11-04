# Test-package factory only. Production registries and installer bytes are never
# modified. The synthetic identity proves transaction behavior, not a real HUD.
function New-PaInstallerCefFixture([string]$ReleaseRoot,[string]$FixtureRoot){
 $allowed=[IO.Path]::GetFullPath((Join-Path $ReleaseRoot 'tests/install-sandbox')).TrimEnd('\')+'\'
 $package=[IO.Path]::GetFullPath($FixtureRoot)
 if(-not $package.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture must stay in install-sandbox'}
 $manifest=Get-Content -LiteralPath (Join-Path $ReleaseRoot 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
 $files=@('install.ps1','INSTALL_MANIFEST.json','CEF_CONTRACT.json')
 $files+=@($manifest.files|ForEach-Object {'moonloader/'+$_.path.Replace('\','/')})
 $files+=@($manifest.cef_files|ForEach-Object {'cef/assets/hud/'+$_.path})
 $files+=@($manifest.setup_files|ForEach-Object {$_.path})
 $files+=@($manifest.preset_files|ForEach-Object {$_.path})
 foreach($name in ($files|Select-Object -Unique)){
  $to=[IO.Path]::GetFullPath((Join-Path $package $name))
  if(-not $to.StartsWith($package.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture path'}
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))|Out-Null
  [IO.File]::Copy((Join-Path $ReleaseRoot $name),$to)
 }
 $js='/* Own synthetic reviewed-identity fixture. Never executed. */ function sendMessageToChat(text){cef.emit("HandleHudSendMessage",text);}'
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try{$digest=[BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($js))).Replace('-','').ToLowerInvariant()}finally{$algorithm.Dispose()}
 $registry=Get-Content -LiteralPath (Join-Path $package 'CEF_CONTRACT.json') -Raw|ConvertFrom-Json
 $identity=$registry.known_versions[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json
 $identity.sha256=$digest;$identity.fingerprint='test-only-reviewed-chat-v1'
 $registry.known_versions=@($registry.known_versions)+@($identity)
 $json=$registry|ConvertTo-Json -Depth 30 -Compress
 [IO.File]::WriteAllText((Join-Path $package 'CEF_CONTRACT.json'),$json,(New-Object Text.UTF8Encoding($false)))
 $module=Join-Path $package 'moonloader/lib/pa26_cef_contract.lua'
 $source=[IO.File]::ReadAllText($module)
 $match=[regex]::Match($source,'registry=\[====\[([\s\S]*?)\]====\]')
 if(-not $match.Success){throw 'Fixture registry missing'}
 $part=$match.Groups[1]
 $source=$source.Substring(0,$part.Index)+$json+$source.Substring($part.Index+$part.Length)
 [IO.File]::WriteAllText($module,$source,(New-Object Text.UTF8Encoding($false)))
 $row=@($manifest.files|Where-Object path -EQ 'lib\pa26_cef_contract.lua')
 if($row.Count -ne 1){throw 'Fixture module is not uniquely manifest-owned'}
 $row[0].sha256=(Get-FileHash -LiteralPath $module -Algorithm SHA256).Hash.ToLowerInvariant()
 if($row[0].PSObject.Properties.Name -contains 'size'){$row[0].size=(Get-Item -LiteralPath $module).Length}
 [IO.File]::WriteAllText((Join-Path $package 'INSTALL_MANIFEST.json'),($manifest|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
 if((Get-FileHash (Join-Path $package 'install.ps1')).Hash -cne (Get-FileHash (Join-Path $ReleaseRoot 'install.ps1')).Hash){throw 'Installer fixture changed production code'}
 return @{root=$package;main=$js;kind='synthetic_reviewed_registry_in_sandbox_copy';manifest_sha256=(Get-FileHash (Join-Path $package 'INSTALL_MANIFEST.json')).Hash}
}
