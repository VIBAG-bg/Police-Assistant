# Installation support only. No game core, existing library or personal file is replaced.
Set-StrictMode -Version Latest
function Assert-PaSetupPlain([string]$Path) {
    $part=[IO.Path]::GetFullPath($Path)
    while($part){
        if((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'setup_reparse_path'}
        $parent=[IO.Path]::GetDirectoryName($part);if($parent -eq $part){break};$part=$parent
    }
}
function Get-PaSetupPath([string]$Root,[string]$Relative) {
    if($Relative -notmatch '^[A-Za-z0-9_./-]+$' -or $Relative.StartsWith('/') -or $Relative.EndsWith('/') -or
       @($Relative.Split('/')|Where-Object {$_ -in @('','.','..') -or $_.EndsWith('.') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'}).Count){throw 'setup_unsafe_path'}
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\');$result=[IO.Path]::GetFullPath((Join-Path $rootPath $Relative.Replace('/','\')))
    if(-not $result.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'setup_unsafe_path'}
    Assert-PaSetupPlain $result;return $result
}
function Resolve-PaSetupRoot([string]$Selected,[bool]$Test=$false) {
    if([string]::IsNullOrWhiteSpace($Selected) -or $Selected -notmatch '^[A-Za-z]:[/\\]'){throw 'Select an absolute GTA or MoonLoader directory.'}
    $full=[IO.Path]::GetFullPath($Selected).TrimEnd('\');Assert-PaSetupPlain $full
    if([IO.Path]::GetFileName($full) -ine 'MoonLoader'){$full=Join-Path $full 'MoonLoader'}
    $game=[IO.Path]::GetDirectoryName($full);Assert-PaSetupPlain $full
    if(-not $Test){
        if(-not ((Test-Path -LiteralPath (Join-Path $game 'gta_sa.exe') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $game 'gta-sa.exe') -PathType Leaf))){throw 'Selected directory does not contain GTA San Andreas.'}
        foreach($file in @('moonloader.asi','lua51.dll')){if(-not (Test-Path -LiteralPath (Join-Path $game $file) -PathType Leaf)){throw ('Install MoonLoader first: missing '+$file)}}
    }
    return $full
}
function Read-PaDependencyManifest([string]$Path) {
    if((Get-Item -LiteralPath $Path).Length -gt 131072){throw 'setup_manifest_size'}
    $m=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)|ConvertFrom-Json
    if($m.schema -ne 1 -or @($m.packages).Count -ne 3){throw 'setup_manifest_schema'}
    $ids=@{};$targets=@{}
    foreach($p in $m.packages){
        if($p.id -notin @('encoding','mimgui','samp') -or $ids.ContainsKey($p.id)){throw 'setup_manifest_id'};$ids[$p.id]=$true
        $url=[Uri]$p.url
        if($url.Scheme -cne 'https' -or $url.Port -ne 443 -or $url.UserInfo -or $url.Fragment -or $url.Host -notin @('www.blast.hk','blast.hk','luarocks.org','codeload.github.com')){throw 'setup_source_url'}
        if($p.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $p.size -lt 1 -or $p.size -gt 8388608 -or @($p.files).Count -lt 1 -or @($p.files).Count -gt 64){throw 'setup_manifest_bounds'}
        foreach($f in $p.files){
            if($f.target -notmatch '^lib/(encoding\.lua|iconv\.dll|iconv/[A-Za-z0-9_.-]+|mimgui/[A-Za-z0-9_.-]+|samp/[A-Za-z0-9_./-]+)$' -or $targets.ContainsKey($f.target.ToLowerInvariant())){throw 'setup_dependency_target'}
            if($f.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $f.size -lt 1 -or $f.size -gt 4194304 -or $f.required -isnot [bool]){throw 'setup_file_bounds'}
            Get-PaSetupPath ([IO.Path]::GetDirectoryName($Path)) $f.target|Out-Null
            $targets[$f.target.ToLowerInvariant()]=$true
        }
    }
    return $m
}
function Get-PaMissingDependencies([string]$MoonLoader,$Manifest) {
    $missing=@()
    foreach($p in $Manifest.packages){
        $needs=@($p.files|Where-Object {$_.required -and -not (Test-Path -LiteralPath (Get-PaSetupPath $MoonLoader $_.target) -PathType Leaf)}).Count -gt 0
        if(-not $needs -and $p.id -eq 'mimgui'){
            # Older complete mimgui versions have no separate win32 module.
            # The pinned new init does require it: detect interrupted installs
            # without forcing a newer library onto an intact older client.
            $init=@($p.files|Where-Object target -CEQ 'lib/mimgui/init.lua')[0]
            $initPath=Get-PaSetupPath $MoonLoader $init.target
            if((Get-FileHash -LiteralPath $initPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $init.sha256 -and -not (Test-Path -LiteralPath (Get-PaSetupPath $MoonLoader 'lib/mimgui/win32.lua') -PathType Leaf)){$needs=$true}
        }
        if($needs){$missing+=,$p}
    }
    return $missing
}
function Save-PaDependencyArchive($Package,[string]$Path) {
    Add-Type -AssemblyName System.Net.Http
    $tlsBefore=[Net.ServicePointManager]::SecurityProtocol
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $handler=New-Object Net.Http.HttpClientHandler;$handler.AllowAutoRedirect=$false
    $client=New-Object Net.Http.HttpClient($handler);$client.Timeout=[TimeSpan]::FromSeconds(45)
    $response=$null;$output=$null;$inputStream=$null;$cancel=New-Object Threading.CancellationTokenSource;$cancel.CancelAfter(45000)
    try {
        $uri=[Uri]$Package.url
        for($redirect=0;$redirect -lt 5;$redirect++){
            if($uri.Scheme -cne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Host -notin @('www.blast.hk','blast.hk','luarocks.org','codeload.github.com','objects.githubusercontent.com','release-assets.githubusercontent.com')){throw 'setup_redirect_host'}
            $response=$client.GetAsync($uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancel.Token).GetAwaiter().GetResult()
            if([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -lt 400){
                if(-not $response.Headers.Location){throw 'setup_redirect_missing'}
                $uri=New-Object Uri($uri,$response.Headers.Location);$response.Dispose();$response=$null;continue
            }
            $response.EnsureSuccessStatusCode()|Out-Null;break
        }
        if(-not $response -or [int]$response.StatusCode -ge 300){throw 'setup_redirect_limit'}
        if($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -ne $Package.size){throw 'setup_download_size'}
        $inputStream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $output=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536;$total=0
        while(($n=$inputStream.ReadAsync($buffer,0,$buffer.Length,$cancel.Token).GetAwaiter().GetResult()) -gt 0){$total+=$n;if($total -gt $Package.size){throw 'setup_download_limit'};$output.Write($buffer,0,$n)}
        $output.Flush($true);if($total -ne $Package.size){throw 'setup_download_short'}
    } finally {
        if($output){$output.Dispose()};if($inputStream){$inputStream.Dispose()};if($response){$response.Dispose()};$client.Dispose();$handler.Dispose();$cancel.Dispose()
        [Net.ServicePointManager]::SecurityProtocol=$tlsBefore
    }
}
function Get-PaDependencyPlan([string]$MoonLoader,$Packages,[string]$Cache,[bool]$AllowDownload) {
    # All requested archives and file hashes are checked before the installer
    # receives any plan. Existing libraries are never part of a replacement plan.
    Assert-PaSetupPlain $MoonLoader;Assert-PaSetupPlain $Cache
    [IO.Directory]::CreateDirectory($Cache)|Out-Null;$plan=@()
    foreach($p in $Packages){
        $archive=Get-PaSetupPath $Cache ($p.sha256+'.zip')
        if(-not (Test-Path -LiteralPath $archive)){
            if(-not $AllowDownload){throw 'setup_dependency_cache_missing'}
            $temp=$archive+'.download-'+[guid]::NewGuid().ToString('N');Save-PaDependencyArchive $p $temp
            if((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant() -cne $p.sha256){throw 'setup_archive_hash'}
            [IO.File]::Move($temp,$archive)
        }
        if((Get-Item -LiteralPath $archive).Length -ne $p.size -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $p.sha256){throw 'setup_archive_hash'}
        Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try {
            if($zip.Entries.Count -gt 512){throw 'setup_zip_count'}
            $entries=@{};$expanded=0
            foreach($e in $zip.Entries){
                # The original MoonLoader ZIP uses DOS separators on .NET.
                # Normalize before validation AND duplicate detection.
                $key=$e.FullName.Replace('\','/').TrimEnd('/')
                if(-not $key){continue}
                Get-PaSetupPath $Cache $key|Out-Null
                if($entries.ContainsKey($key.ToLowerInvariant()) -or (($e.ExternalAttributes -shr 16) -band 61440) -eq 40960){throw 'setup_zip_duplicate_or_link'}
                $entries[$key.ToLowerInvariant()]=$e;$expanded+=$e.Length
                if($expanded -gt 67108864 -or $e.Length -gt 8388608){throw 'setup_zip_expansion'}
            }
            $stage=Get-PaSetupPath $Cache ('stage-'+[guid]::NewGuid().ToString('N'))
            foreach($f in $p.files){
                $target=Get-PaSetupPath $MoonLoader $f.target
                if(Test-Path -LiteralPath $target){
                    if([IO.Path]::GetExtension($target) -in @('.lua','.dll') -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $f.sha256){throw ('Incomplete library differs from the pinned version; restore its own complete version: '+$p.id)}
                    continue
                }
                $e=$entries[$f.entry.ToLowerInvariant()];if(-not $e -or $e.Length -ne $f.size){throw 'setup_zip_missing_file'}
                $source=Get-PaSetupPath $stage $f.target;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($source))|Out-Null
                $entryInput=$e.Open();$entryOutput=[IO.File]::Open($source,[IO.FileMode]::CreateNew)
                try{
                    $count=0;$buffer=New-Object byte[] 65536
                    while(($n=$entryInput.Read($buffer,0,$buffer.Length)) -gt 0){$count+=$n;if($count -gt $f.size){throw 'setup_entry_expansion'};$entryOutput.Write($buffer,0,$n)}
                    if($count -ne $f.size){throw 'setup_entry_short'}
                }finally{$entryInput.Dispose();$entryOutput.Dispose()}
                if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $f.sha256){throw 'setup_dependency_hash'}
                $plan+=[PSCustomObject]@{Relative=$f.target.Replace('/','\');Source=$source;Target=$target;SHA256=$f.sha256;Existed=$false;BeforeHash=$null;Skip=$false;Root=$MoonLoader;BackupRelative=('dependencies\'+$f.target.Replace('/','\'));Content=$null}
            }
        } finally {$zip.Dispose()}
    }
    return $plan
}
