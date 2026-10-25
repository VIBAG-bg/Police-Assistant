[CmdletBinding()]
param([string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$paRelease=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $OutputPath){$OutputPath=Join-Path $paRelease 'pa26-update.zip'}
$paOutput=[IO.Path]::GetFullPath($OutputPath)
if(-not $paOutput.StartsWith($paRelease+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must remain within this release.'}
. (Join-Path $paRelease 'moonloader\resource\pa26\updater\pa26-update.ps1') -Mode Library
$paInstall=Read-PaJson (Join-Path $paRelease 'INSTALL_MANIFEST.json')
$paFiles=@();$paSources=@{}
foreach($row in $paInstall.files){
    if($row.path.StartsWith('config\')){continue}
    $path='MoonLoader/'+$row.path.Replace('\','/');if(-not (Test-PaOwned $path)){throw ('Unowned runtime entry: '+$path)}
    $source=Join-Path $paRelease ('moonloader\'+$row.path)
    if((Get-PaHash $source) -ne $row.sha256){throw 'Manifest changed after release verification'}
    $paFiles+=@{path=$path;sha256=$row.sha256;size=(Get-Item -LiteralPath $source).Length};$paSources[$path]=$source
}
foreach($row in $paInstall.cef_files){
    $path='cef/assets/hud/'+$row.path;$source=Join-Path $paRelease ('cef\assets\hud\'+$row.path)
    if(-not (Test-PaOwned $path) -or (Get-PaHash $source) -ne $row.sha256){throw 'Invalid CEF release entry'}
    $paFiles+=@{path=$path;sha256=$row.sha256;size=(Get-Item -LiteralPath $source).Length};$paSources[$path]=$source
}
$paContract=Read-PaJson (Join-Path $paRelease 'CEF_CONTRACT.json')
$paManifest=@{product='police-assistant-2026';protocol=1;storage='pa26-split-json-1';version=$paInstall.release;cef_main_sha256=$paContract.hud_main_sha256;files=$paFiles}
$paTemp=$paOutput+'.new-'+[guid]::NewGuid().ToString('N')
Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
$paStream=[IO.File]::Open($paTemp,[IO.FileMode]::CreateNew)
$paZip=New-Object IO.Compression.ZipArchive($paStream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($path in $paSources.Keys){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($paZip,$paSources[$path],$path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}
    $entry=$paZip.CreateEntry('pa26-update.json');$entryStream=$entry.Open()
    $bytes=[Text.Encoding]::UTF8.GetBytes(($paManifest|ConvertTo-Json -Depth 10 -Compress))
    try{$entryStream.Write($bytes,0,$bytes.Length)}finally{$entryStream.Dispose()}
}finally{$paZip.Dispose();$paStream.Dispose()}
if([IO.File]::Exists($paOutput)){[IO.File]::Replace($paTemp,$paOutput,[NullString]::Value)}else{[IO.File]::Move($paTemp,$paOutput)}
Write-PaJson (Join-Path $paRelease 'UPDATE_PACKAGE.json') @{version=$paInstall.release;asset='pa26-update.zip';sha256=Get-PaHash $paOutput;size=(Get-Item -LiteralPath $paOutput).Length;files=$paFiles.Count;personal_files_included=$false}
Write-Output ('Update package: '+$paOutput+'; '+$paFiles.Count+' runtime files; no personal data.')
