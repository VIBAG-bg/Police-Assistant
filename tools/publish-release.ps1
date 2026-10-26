[CmdletBinding()]
param(
    [string]$Repository='VIBAG-bg/Police-Assistant',
    [Parameter(Mandatory=$true)][string]$Commit,
    [switch]$VerifyOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $Commit -notmatch '^[0-9a-f]{40}$'){throw 'Invalid repository or commit.'}
$paRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$paManifest=Get-Content -LiteralPath (Join-Path $paRoot 'INSTALL_MANIFEST.json') -Raw | ConvertFrom-Json
$paVersion=$paManifest.release
if($paVersion -notmatch '^\d+\.\d+\.\d+$'){throw 'A stable numeric release is required.'}
$paTag='v'+$paVersion
$paAssets=@(('Police-Assistant-v'+$paVersion+'.zip'),'pa26-update.zip','SHA256SUMS.txt')
$paFiles=@()
foreach($paName in $paAssets){
    $paPath=Join-Path $paRoot ('dist\'+$paName)
    $paFiles+=@{name=$paName;path=$paPath;size=(Get-Item -LiteralPath $paPath).Length;sha256=(Get-FileHash -LiteralPath $paPath -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$paNotes=[IO.File]::ReadAllText((Join-Path $paRoot ('docs\RELEASE-'+$paVersion+'.md')),[Text.Encoding]::UTF8)
if($VerifyOnly){$paFiles | ForEach-Object {[PSCustomObject]$_} | Select-Object name,size,sha256;return}

# Use the normal Git credential helper for this same GitHub host. Never print
# or persist its reply, credentials, Authorization headers or request objects.
$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='Never'
$paReply=@('protocol=https','host=github.com','') -join "`n"
$paCredentials=$paReply | & git -c credential.interactive=never credential fill 2>$null
if($LASTEXITCODE -ne 0){throw 'GitHub authentication unavailable; authenticate Git before publishing.'}
$paToken=$null
foreach($paLine in $paCredentials){if($paLine.StartsWith('password=')){$paToken=$paLine.Substring(9)}}
if(-not $paToken){throw 'GitHub credential helper returned no authentication.'}
$paHeaders=@{Authorization='Bearer '+$paToken;Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28';'User-Agent'='Police-Assistant-release'}
$paApi='https://api.github.com/repos/'+$Repository
try {
    $paHead=Invoke-RestMethod -Uri ($paApi+'/git/ref/heads/main') -Headers $paHeaders
    if($paHead.object.sha -cne $Commit){throw 'Remote main changed; review before publishing.'}
    $paExisting=$null
    try {$paExisting=Invoke-RestMethod -Uri ($paApi+'/releases/tags/'+$paTag) -Headers $paHeaders}
    catch {if([int]$_.Exception.Response.StatusCode -ne 404){throw}}
    if($paExisting){throw 'This release/tag already exists. Published assets are never replaced.'}
    $paBody=@{tag_name=$paTag;target_commitish=$Commit;name='Police Assistant '+$paVersion;body=$paNotes;draft=$true;prerelease=$false}|ConvertTo-Json -Depth 4
    $paRelease=Invoke-RestMethod -Method Post -Uri ($paApi+'/releases') -Headers $paHeaders -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($paBody))
    $paUploaded=@()
    foreach($paFile in $paFiles){
        $paUpload=$paRelease.upload_url.Split('{')[0]+'?name='+[Uri]::EscapeDataString($paFile.name)
        $paType=if($paFile.name.EndsWith('.zip')){'application/zip'}else{'text/plain'}
        $paAsset=Invoke-RestMethod -Method Post -Uri $paUpload -Headers $paHeaders -ContentType $paType -InFile $paFile.path
        if($paAsset.state -ne 'uploaded' -or $paAsset.size -ne $paFile.size -or $paAsset.digest -cne ('sha256:'+$paFile.sha256)){
            throw 'GitHub asset verification failed. The release remains a draft.'
        }
        $paUploaded+=@{name=$paAsset.name;id=$paAsset.id;size=$paAsset.size;digest=$paAsset.digest;url=$paAsset.browser_download_url}
    }
    $paPublished=Invoke-RestMethod -Method Patch -Uri $paRelease.url -Headers $paHeaders -ContentType 'application/json' -Body '{"draft":false,"make_latest":"true"}'
    $paLatest=Invoke-RestMethod -Uri ($paApi+'/releases/latest') -Headers $paHeaders
    if($paPublished.draft -or $paLatest.id -ne $paPublished.id){throw 'Published release is not the latest stable release.'}
    $paResult=@{release=$paVersion;commit=$Commit;status='published';url=$paPublished.html_url;id=$paPublished.id;assets=$paUploaded;game_written=$false}
    $paResult|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $paRoot 'PUBLICATION.json') -Encoding UTF8
    Write-Output ('Published '+$paPublished.html_url)
    $paUploaded|ForEach-Object {Write-Output ($_.name+' '+$_.digest)}
} finally {
    $paToken=$null;$paCredentials=$null;$paHeaders=$null;$paReply=$null
}
