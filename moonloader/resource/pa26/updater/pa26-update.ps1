[CmdletBinding()]
param([ValidateSet('Check','Prepare','Status','Recover','Library')][string]$Mode='Check',[string]$MoonLoader,[string]$JobRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:PaProtocol=1
$script:PaBase=[IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'),'PoliceAssistant2026','updates')
$script:PaFault=$null
$script:PaJob=$null;$script:PaML=$null;$script:PaState=$null
function Get-PaHash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-PaKey([string]$value) {
    $h=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($value.ToLowerInvariant())))).Replace('-','').ToLowerInvariant() } finally {$h.Dispose()}
}
function Assert-PaPlain([string]$path) {
    $part=[IO.Path]::GetFullPath($path)
    while($part) {
        if(Test-Path -LiteralPath $part) { if((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'reparse_path'} }
        $parent=[IO.Path]::GetDirectoryName($part);if($parent -eq $part){break};$part=$parent
    }
}
function Get-PaPath([string]$root,[string]$relative) {
    if($relative -notmatch '^[A-Za-z0-9_./-]+$' -or $relative.Contains('\') -or $relative.StartsWith('/') -or $relative.EndsWith('/') -or
       @($relative.Split('/') | Where-Object {$_ -in @('','.','..') -or $_.EndsWith('.') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'}).Count){throw 'unsafe_path'}
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/','\')))
    if(-not $path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'unsafe_path'}
    Assert-PaPlain $path;return $path
}
function Get-PaLocalPath([string]$root,[string]$relative) {
    # Only local enumerated personal filenames use Unicode. Remote archive
    # entries retain the stricter ASCII/ownership validator above.
    if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative.Contains([char]0)){throw 'unsafe_path'}
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/','\')))
    if(-not $path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'unsafe_path'}
    Assert-PaPlain $path;return $path
}
function Write-PaMarker([string]$job) {
    Assert-PaClosed;Assert-PaPlain $script:PaMarker
    $bytes=[Text.Encoding]::ASCII.GetBytes($job)
    $stream=New-Object IO.FileStream($script:PaMarker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read,4096,[IO.FileOptions]::WriteThrough)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Assert-PaMarkerOwner([string]$job) {
    if(-not [IO.File]::Exists($script:PaMarker) -or [IO.File]::ReadAllText($script:PaMarker) -cne $job){throw 'journal_owner_mismatch'}
}
function Test-PaOwned([string]$path) {
    return $path -cmatch '^MoonLoader/(police_assistant_2026\.lua|pa26_guard\.lua|lib/pa26_[a-z0-9_]+\.lua|resource/pa26/(knowledge-base\.json|knowledge-policy\.json|wanted-catalog\.json|banner-bmw-lamborghini\.png|sidebar-police-assistant\.png|updater/pa26-update\.ps1))$' -or
           $path -cmatch '^cef/assets/hud/pa26-chat(-endpoint)?\.js$'
}
function Read-PaJson([string]$path,[long]$limit=1048576) {
    Assert-PaPlain $path
    if((Get-Item -LiteralPath $path).Length -gt $limit){throw 'oversize_json'}
    return [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) | ConvertFrom-Json
}
function Write-PaBytes([string]$path,[byte[]]$bytes) {
    Assert-PaPlain $path
    $parent=[IO.Path]::GetDirectoryName($path);[IO.Directory]::CreateDirectory($parent)|Out-Null
    $temp=$path+'.new-'+[guid]::NewGuid().ToString('N')
    $stream=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    try { if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)} }
    finally {if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function Write-PaJson([string]$path,$value) {Write-PaBytes $path ([Text.Encoding]::UTF8.GetBytes(($value|ConvertTo-Json -Depth 20 -Compress)))}
function Copy-PaVerified([string]$from,[string]$to,[string]$expected) {
    Assert-PaPlain $from;Assert-PaPlain $to
    if((Get-PaHash $from) -ne $expected){throw 'source_hash_changed'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))|Out-Null
    $input=[IO.File]::OpenRead($from)
    $output=New-Object IO.FileStream($to,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
    try {$input.CopyTo($output);$output.Flush($true)}finally{$input.Dispose();$output.Dispose()}
    if((Get-PaHash $to) -ne $expected){throw 'backup_hash_mismatch'}
}
function Get-PaVersion([string]$text) {
    if($text -cnotmatch '^v?(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'){throw 'invalid_version'}
    $major=[int]$Matches[1];$minor=[int]$Matches[2];$patch=[int]$Matches[3]
    $pre=[string]$Matches[4];if($pre.Length -gt 80){throw 'invalid_version'}
    foreach($part in $pre.Split('.')){if(($part -match '^[0-9]+$') -and (($part.Length -gt 6) -or (($part.Length -gt 1) -and $part.StartsWith('0')))){throw 'invalid_version'}}
    return @{major=$major;minor=$minor;patch=$patch;pre=$pre;text=$text.TrimStart('v')}
}
function Compare-PaVersion([string]$a,[string]$b) {
    $x=Get-PaVersion $a;$y=Get-PaVersion $b
    foreach($key in @('major','minor','patch')){if($x[$key] -ne $y[$key]){return [Math]::Sign($x[$key]-$y[$key])}}
    if($x.pre -eq $y.pre){return 0};if(-not $x.pre){return 1};if(-not $y.pre){return -1}
    $xp=$x.pre.Split('.');$yp=$y.pre.Split('.')
    for($i=0;$i -lt [Math]::Min($xp.Length,$yp.Length);$i++) {
        if($xp[$i] -ceq $yp[$i]){continue};$xn=$xp[$i] -match '^[0-9]+$';$yn=$yp[$i] -match '^[0-9]+$'
        if($xn -and $yn){return [Math]::Sign([int]$xp[$i]-[int]$yp[$i])};if($xn){return -1};if($yn){return 1}
        return [Math]::Sign([string]::CompareOrdinal($xp[$i],$yp[$i]))
    }
    return [Math]::Sign($xp.Length-$yp.Length)
}
function Initialize-PaPaths([string]$ml,[string]$job) {
    $script:PaML=[IO.Path]::GetFullPath($ml).TrimEnd('\')
    if($script:PaML -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFileName($script:PaML) -ine 'MoonLoader'){throw 'invalid_game_root'}
    Assert-PaPlain $script:PaML
    $script:PaGame=[IO.Path]::GetDirectoryName($script:PaML)
    $script:PaJob=[IO.Path]::GetFullPath($job).TrimEnd('\');Assert-PaPlain $script:PaJob
    $jobs=Join-Path $script:PaBase 'jobs'
    if([IO.Path]::GetDirectoryName($script:PaJob) -ine $jobs -or [IO.Path]::GetFileName($script:PaJob) -notmatch '^[0-9a-f]{32}$'){throw 'invalid_job_root'}
    $script:PaState=Join-Path $script:PaBase ('games\'+(Get-PaKey $script:PaML))
    Assert-PaPlain $script:PaState;[IO.Directory]::CreateDirectory($script:PaState)|Out-Null
    $script:PaMarker=Join-Path $script:PaML 'pa26-update.pending'
}
function Set-PaStatus([string]$phase,[string]$message,$details=$null) {
    $value=[ordered]@{product='police-assistant-2026';phase=$phase;message=$message;job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;utc=[DateTime]::UtcNow.ToString('o')}
    if($details){$value.details=$details}
    Write-PaJson (Join-Path $script:PaJob 'status.json') $value
    $active=Join-Path $script:PaState 'active.json'
    if($phase -in @('installed','rolled_back','error','cancelled')){
        Write-PaJson (Join-Path $script:PaState 'result.json') $value
        if([IO.File]::Exists($active) -and (Read-PaJson $active).job -ceq $value.job){[IO.File]::Delete($active)}
    }elseif($Mode -in @('Prepare','Recover')){
        Write-PaJson $active @{job=$value.job;moonloader=$script:PaML;pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks}
    }
}
function Get-PaActive {
    $active=Join-Path $script:PaState 'active.json'
    if(-not [IO.File]::Exists($active)){return $null}
    $v=Read-PaJson $active
    if($v.moonloader -ine $script:PaML -or $v.job -cnotmatch '^[0-9a-f]{32}$'){throw 'invalid_request'}
    $process=Get-Process -Id $v.pid -ErrorAction SilentlyContinue
    if($process -and $process.StartTime.ToUniversalTime().Ticks -eq $v.started){
        $row=Read-PaJson (Join-Path $script:PaBase ('jobs\'+$v.job+'\status.json'))
        $row|Add-Member -NotePropertyName active_job -NotePropertyValue $true -Force
        return $row
    }
    # A dead worker before the runtime marker cannot have replaced game files.
    # Report interruption; a fresh explicitly requested download can retry.
    if([IO.File]::Exists($script:PaMarker)){throw 'recovery_required'}
    [IO.File]::Delete($active)
    return @{product='police-assistant-2026';phase='error';message='worker_interrupted';job=$v.job;moonloader=$script:PaML}
}
function Get-PaGameRunning { return @(Get-Process -Name gta_sa,gta-sa -ErrorAction SilentlyContinue).Count -gt 0 }
function Assert-PaClosed {if(Get-PaGameRunning){throw 'game_running'}}
function Wait-PaClosed([bool]$allowCancel=$true) {
    $start=[DateTime]::UtcNow;$quiet=$null
    while($true) {
        if($allowCancel -and [IO.File]::Exists((Join-Path $script:PaJob 'cancel'))){throw 'cancelled'}
        if(([DateTime]::UtcNow-$start).TotalHours -gt 24){throw 'close_wait_expired'}
        if(Get-PaGameRunning){$quiet=$null}else{
            if(-not $quiet){$quiet=[DateTime]::UtcNow}
            if(([DateTime]::UtcNow-$quiet).TotalSeconds -ge 2){return}
        }
        Start-Sleep -Milliseconds 500
    }
}
function Get-PaCurrent {
    $path=Join-Path $script:PaML 'police_assistant_2026.lua'
    if(-not [IO.File]::Exists($path)){throw 'missing_installed_version'}
    $text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    if($text -notmatch "script_version\('([^']+)'\)"){throw 'missing_installed_version'}
    return (Get-PaVersion $Matches[1]).text
}
function Assert-PaUrl([string]$url,[string]$kind) {
    $uri=$null
    if($url.Length -gt 8192 -or -not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Fragment){throw 'unsafe_download_url'}
    $hosts=if($kind -eq 'api'){@('api.github.com')}else{@('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')}
    if($uri.DnsSafeHost -notin $hosts){throw 'unsafe_download_url'}
    return $uri
}
function Get-PaRemote([string]$url,[string]$kind,[long]$limit,[int]$timeout,[string]$out='') {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    for($redirect=0;$redirect -le 5;$redirect++) {
        $uri=Assert-PaUrl $url $kind
        $request=[Net.HttpWebRequest]::Create($uri);$request.AllowAutoRedirect=$false;$request.Timeout=$timeout*1000;$request.ReadWriteTimeout=$timeout*1000
        $request.UserAgent='Police-Assistant-Updater/1';$request.Accept='application/vnd.github+json'
        $request.Headers['X-GitHub-Api-Version']='2026-03-10'
        $response=$null
        try {
            try {$response=$request.GetResponse()}catch [Net.WebException]{
                if($_.Exception.Response){$code=[int]$_.Exception.Response.StatusCode;$_.Exception.Response.Close();throw ('http_'+$code)}
                throw 'network_error'
            }
            if([int]$response.StatusCode -in @(301,302,303,307,308)) {
                if($kind -eq 'api'){throw 'unsafe_download_url'}
                $url=([Uri]::new($uri,$response.Headers['Location'])).AbsoluteUri;continue
            }
            if($response.ContentLength -gt $limit){throw 'download_too_large'}
            $input=$response.GetResponseStream();$target=if($out){[IO.File]::Open($out,[IO.FileMode]::CreateNew)}else{New-Object IO.MemoryStream}
            $count=0L;$buffer=New-Object byte[] 65536;$began=[DateTime]::UtcNow
            try {
                while(($n=$input.Read($buffer,0,$buffer.Length)) -gt 0){
                    $count+=$n;if($count -gt $limit){throw 'download_too_large'}
                    if(([DateTime]::UtcNow-$began).TotalSeconds -gt $timeout){throw 'network_timeout'}
                    $target.Write($buffer,0,$n)
                }
                if(-not $out){return [Text.Encoding]::UTF8.GetString($target.ToArray())}
            }finally{$input.Dispose();$target.Dispose()}
            return
        }finally{if($response){$response.Close()}}
    }
    throw 'too_many_redirects'
}
function Get-PaCandidate($request) {
    if($request.repository -cnotmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$' -or $request.repository.EndsWith('.git')){throw 'invalid_repository'}
    if($request.timeout_seconds -isnot [int] -or $request.timeout_seconds -lt 1 -or $request.timeout_seconds -gt 120 -or $request.include_prerelease -isnot [bool]){throw 'invalid_request'}
    $api='https://api.github.com/repos/'+$request.repository+'/releases'
    $url=if($request.include_prerelease){$api+'?per_page=20'}else{$api+'/latest'}
    $data=Get-PaRemote $url 'api' 1048576 $request.timeout_seconds
    $releases=@($data|ConvertFrom-Json);$found=$null
    foreach($release in $releases) {
        if(($release.draft -isnot [bool]) -or $release.draft -ne $false -or ($release.prerelease -isnot [bool]) -or (-not $request.include_prerelease -and $release.prerelease)){continue}
        try {$version=(Get-PaVersion $release.tag_name).text}catch{continue}
        if(-not $request.include_prerelease -and (Get-PaVersion $version).pre){continue}
        if((Compare-PaVersion $version (Get-PaCurrent)) -le 0){continue}
        $assets=@($release.assets|Where-Object {$_.name -ceq 'pa26-update.zip' -and $_.state -eq 'uploaded'})
        if($assets.Count -ne 1){continue};$a=$assets[0]
        if($a.digest -cnotmatch '^sha256:[0-9a-f]{64}$' -or $a.size -le 0 -or $a.size -gt 67108864 -or (($a.id -isnot [long]) -and ($a.id -isnot [int]))){continue}
        $uri=Assert-PaUrl $a.browser_download_url 'asset'
        $expected='https://github.com/'+$request.repository+'/releases/download/'+[Uri]::EscapeDataString($release.tag_name)+'/pa26-update.zip'
        if($uri.AbsoluteUri -ine $expected){throw 'unsafe_download_url'}
        $candidate=@{version=$version;tag=$release.tag_name;asset_id=$a.id;size=$a.size;sha256=$a.digest.Substring(7);url=$expected;
            notes=([string]$release.body).Substring(0,[Math]::Min(8000,([string]$release.body).Length));repository=$request.repository}
        if(-not $found -or (Compare-PaVersion $version $found.version) -gt 0){$found=$candidate}
    }
    return $found
}
function Assert-PaApproval($request,$candidate) {
    if(($request.approved -isnot [bool]) -or $request.approved -ne $true -or $request.candidate.sha256 -cne $candidate.sha256 -or
       $request.candidate.asset_id -ne $candidate.asset_id -or $request.candidate.version -cne $candidate.version){throw 'release_changed'}
}
function Expand-PaPackage([string]$archive,[string]$folder,$candidate) {
    if((Get-PaHash $archive) -ne $candidate.sha256 -or (Get-Item -LiteralPath $archive).Length -ne $candidate.size){throw 'archive_hash_mismatch'}
    Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
    Assert-PaPlain $folder;[IO.Directory]::CreateDirectory($folder)|Out-Null
    $zip=[IO.Compression.ZipFile]::OpenRead($archive);$seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);$total=0L
    try {
        if($zip.Entries.Count -gt 512){throw 'too_many_files'}
        foreach($e in $zip.Entries){
            $name=$e.FullName;$directory=$name.EndsWith('/');$clean=if($directory){$name.TrimEnd('/')}else{$name}
            $path=Get-PaPath $folder $clean
            if(-not $seen.Add($name) -or ($e.ExternalAttributes -band 0xF0000000L) -eq 0xA0000000L){throw 'unsafe_archive_entry'}
            if($directory){continue}
            if($name -cne 'pa26-update.json' -and -not (Test-PaOwned $name)){throw 'unowned_payload_file'}
            $total+=$e.Length;if($e.Length -gt 67108864 -or $total -gt 268435456){throw 'expanded_too_large'}
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))|Out-Null
            $input=$e.Open();$output=[IO.File]::Open($path,[IO.FileMode]::CreateNew);$count=0L;$buffer=New-Object byte[] 65536
            try {while(($n=$input.Read($buffer,0,$buffer.Length)) -gt 0){$count+=$n;if($count -gt $e.Length){throw 'expanded_too_large'};$output.Write($buffer,0,$n)}}finally{$input.Dispose();$output.Dispose()}
            if($count -ne $e.Length){throw 'truncated_archive'}
        }
    }finally{$zip.Dispose()}
    $m=Read-PaJson (Join-Path $folder 'pa26-update.json')
    if($m.product -cne 'police-assistant-2026' -or $m.protocol -ne 1 -or $m.storage -cne 'pa26-split-json-1' -or $m.version -cne $candidate.version -or $m.files.Count -gt 256){throw 'incompatible_package'}
    $files=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $m.files) {
        if(-not (Test-PaOwned $row.path) -or -not $files.Add($row.path) -or $row.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'unsafe_manifest'}
        $p=Get-PaPath $folder $row.path
        if((Get-Item -LiteralPath $p).Length -ne $row.size -or (Get-PaHash $p) -ne $row.sha256){throw 'payload_hash_mismatch'}
    }
    if($seen.Count -ne $files.Count+1){throw 'archive_manifest_mismatch'}
    foreach($required in @('MoonLoader/police_assistant_2026.lua','MoonLoader/lib/pa26_core.lua','MoonLoader/lib/pa26_update_platform.lua','MoonLoader/resource/pa26/updater/pa26-update.ps1')){if(-not $files.Contains($required)){throw 'missing_payload_file'}}
    $platform='MoonLoader/lib/pa26_update_platform.lua'
    if((Get-PaHash (Get-PaPath $folder $platform)) -ne (Get-PaHash (Get-PaPath $script:PaGame $platform))){throw 'bootstrap_update_requires_manual_install'}
    $main=[IO.File]::ReadAllText((Get-PaPath $folder 'MoonLoader/police_assistant_2026.lua'),[Text.Encoding]::UTF8)
    if($main -notmatch "script_version\('([^']+)'\)" -or $Matches[1] -cne $m.version){throw 'payload_version_mismatch'}
    $core=[IO.File]::ReadAllText((Get-PaPath $folder 'MoonLoader/lib/pa26_core.lua'),[Text.Encoding]::UTF8)
    if($core -notmatch "VERSION\s*=\s*'([^']+)'" -or $Matches[1] -cne $m.version){throw 'payload_version_mismatch'}
    return $m
}
function Get-PaPersonal {
    $config=Join-Path $script:PaML 'config';Assert-PaPlain $config;$out=@()
    $folders=New-Object 'Collections.Generic.Queue[string]';if(Test-Path -LiteralPath $config){$folders.Enqueue($config)};$count=0
    while($folders.Count){
        $directory=$folders.Dequeue();Assert-PaPlain $directory;$count++;if($count -gt 10000){throw 'too_many_personal_directories'}
        foreach($p in Get-ChildItem -LiteralPath $directory -Force){
            Assert-PaPlain $p.FullName
            if($p.PSIsContainer){$folders.Enqueue($p.FullName)}elseif($p.Name -like 'police_assistant_2026*'){
                $out+=@{path=$p.FullName.Substring($script:PaGame.Length+1).Replace('\','/');sha256=Get-PaHash $p.FullName}
            }
        }
    }
    return $out
}
function Assert-PaPersonal($snapshot) {
    $current=@(Get-PaPersonal);if($current.Count -ne @($snapshot).Count){throw 'personal_data_changed'}
    $old=@{};foreach($row in $snapshot){$old[$row.path]=$row.sha256}
    foreach($row in $current){if(-not $old.ContainsKey($row.path) -or $old[$row.path] -ne $row.sha256){throw 'personal_data_changed'}}
}
function Get-PaPlan([string]$folder,$m) {
    $cef=@($m.files|Where-Object {$_.path.StartsWith('cef/')})
    $native=$true
    if($cef.Count){
        if($cef.Count -ne 2 -or $m.cef_main_sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'cef_incompatible'}
        $hudMain=Get-PaPath $script:PaGame 'cef/assets/hud/main.js'
        $hudIndex=Get-PaPath $script:PaGame 'cef/assets/hud/index.html'
        if([IO.File]::Exists($hudMain) -and (Get-PaHash $hudMain) -eq $m.cef_main_sha256){$native=$false}
        elseif([IO.File]::Exists($hudIndex) -and [IO.File]::ReadAllText($hudIndex).Contains('<!-- PA26 CEF chat adapter -->')){throw 'cef_incompatible'}
    }
    $plan=@();foreach($row in $m.files){if($native -and $row.path.StartsWith('cef/')){continue};$plan+=@{path=$row.path;source=Get-PaPath $folder $row.path;sha256=$row.sha256}}
    if($cef.Count -and -not $native) {
        if($cef.Count -ne 2 -or $m.cef_main_sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'cef_incompatible'}
        $main=Get-PaPath $script:PaGame 'cef/assets/hud/main.js';if((Get-PaHash $main) -ne $m.cef_main_sha256){throw 'cef_incompatible'}
        $index=Get-PaPath $script:PaGame 'cef/assets/hud/index.html';$bytes=[IO.File]::ReadAllBytes($index)
        $enc=New-Object Text.UTF8Encoding($false,$true);$text=$enc.GetString($bytes)
        $mark='<!-- PA26 CEF chat adapter -->';$count=[regex]::Matches($text,[regex]::Escape($mark)).Count
        if($count -gt 1){throw 'cef_incompatible'}
        if($count -eq 0) {
            if([regex]::Matches($text,'(?i)</body>').Count -ne 1 -or $text -match 'pa26-chat(?:-endpoint)?\.js'){throw 'cef_incompatible'}
            $insert=$mark+'<script src="pa26-chat-endpoint.js"></script><script src="pa26-chat.js"></script>'
            $text=[regex]::Replace($text,'(?i)</body>',($insert+'</body>'));$p=Join-Path $folder 'cef-index-prepared.html'
            Write-PaBytes $p ($enc.GetBytes($text));$plan+=@{path='cef/assets/hud/index.html';source=$p;sha256=Get-PaHash $p}
        }
    }
    # Main entry is replaced last. Both old/new entries gate mixed module loads.
    return @($plan|Sort-Object @{Expression={if($_.path -ceq 'MoonLoader/police_assistant_2026.lua'){1}else{0}}},@{Expression={$_.path}})
}
function Restore-PaTransaction($journal) {
    if($journal.moonloader -ine $script:PaML -or $journal.job -cne [IO.Path]::GetFileName($script:PaJob)){throw 'journal_owner_mismatch'}
    Assert-PaMarkerOwner $journal.job
    if($journal.plan.Count -gt 256 -or $journal.touched -lt 0 -or $journal.touched -gt $journal.plan.Count -or
       -not ([IO.Path]::GetFullPath($journal.backup)).StartsWith((Join-Path $script:PaState 'backups\'),[StringComparison]::OrdinalIgnoreCase)){throw 'unsafe_journal'}
    foreach($row in @($journal.plan|Select-Object -First $journal.touched|Sort-Object order -Descending)) {
        if(-not (Test-PaOwned $row.path) -and $row.path -cne 'cef/assets/hud/index.html'){throw 'unsafe_journal'}
        Assert-PaClosed;$target=Get-PaPath $script:PaGame $row.path
        $actual=if([IO.File]::Exists($target)){Get-PaHash $target}else{''}
        if($row.existed -and $actual -eq $row.before){continue}
        if($actual -and $actual -ne $row.sha256){throw 'runtime_changed_during_recovery'}
        if($row.existed){
            $backup=Get-PaPath $journal.backup ('runtime/'+$row.path)
            if((Get-PaHash $backup) -ne $row.before){throw 'damaged_backup'}
            $temp=$target+'.pa26-restore-'+[guid]::NewGuid().ToString('N');Copy-PaVerified $backup $temp $row.before;Assert-PaClosed
            if([IO.File]::Exists($target)){[IO.File]::Replace($temp,$target,[NullString]::Value)}else{[IO.File]::Move($temp,$target)}
        }elseif([IO.File]::Exists($target)){[IO.File]::Delete($target)}
    }
    $journal.phase='rolled_back';Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
    Assert-PaClosed;Assert-PaMarkerOwner $journal.job;[IO.File]::Delete($script:PaMarker)
    Set-PaStatus 'rolled_back' 'update_rolled_back' @{backup=$journal.backup}
}
function Invoke-PaTransaction([string]$folder,$m) {
    Assert-PaClosed
    if([IO.File]::Exists($script:PaMarker)){throw 'recovery_required'}
    if((Compare-PaVersion $m.version (Get-PaCurrent)) -le 0){throw 'version_changed'}
    $plan=@(Get-PaPlan $folder $m);$personal=@(Get-PaPersonal)
    $backup=Join-Path $script:PaState ('backups\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[IO.Path]::GetFileName($script:PaJob));Assert-PaPlain $backup
    $order=0;foreach($row in $plan) {
        $target=Get-PaPath $script:PaGame $row.path;$row.order=$order;$order++;$row.existed=[IO.File]::Exists($target);$row.before=''
        if($row.existed){$row.before=Get-PaHash $target;Copy-PaVerified $target (Get-PaPath $backup ('runtime/'+$row.path)) $row.before}
    }
    foreach($row in $personal){Assert-PaClosed;Copy-PaVerified (Get-PaLocalPath $script:PaGame $row.path) (Get-PaLocalPath $backup ('personal/'+$row.path)) $row.sha256}
    Assert-PaPersonal $personal
    $journal=@{product='police-assistant-2026';phase='applying';job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;
        version=$m.version;backup=$backup;personal=$personal;plan=$plan;touched=0}
    Write-PaJson (Join-Path $backup 'BACKUP.json') $journal
    Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
    Write-PaMarker $journal.job
    try {
        # The physical marker also serializes aliases of the same directory.
        # Reject changes made during backup before touching any program file.
        foreach($row in $plan){
            $target=Get-PaPath $script:PaGame $row.path
            if([IO.File]::Exists($target) -ne $row.existed -or ($row.existed -and (Get-PaHash $target) -ne $row.before)){throw 'runtime_changed'}
        }
        if(@($plan|Where-Object {$_.path.StartsWith('cef/')}).Count -and (Get-PaHash (Get-PaPath $script:PaGame 'cef/assets/hud/main.js')) -ne $m.cef_main_sha256){throw 'cef_incompatible'}
        foreach($row in $plan) {
            Assert-PaClosed;Assert-PaPersonal $personal
            $target=Get-PaPath $script:PaGame $row.path;$temp=$target+'.pa26-new-'+$journal.job
            Copy-PaVerified $row.source $temp $row.sha256
            $journal.touched++;Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
            Assert-PaClosed
            if($row.existed){if((Get-PaHash $target) -ne $row.before){throw 'runtime_changed'};[IO.File]::Replace($temp,$target,[NullString]::Value)}else{[IO.File]::Move($temp,$target)}
            if($script:PaFault){&$script:PaFault $journal.touched}
        }
        foreach($row in $plan){if((Get-PaHash (Get-PaPath $script:PaGame $row.path)) -ne $row.sha256){throw 'installed_hash_mismatch'}}
        Assert-PaPersonal $personal;$journal.phase='committed';Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
        Set-PaStatus 'installed' 'update_installed' @{version=$m.version;backup=$backup;personal_files=$personal.Count}
        Assert-PaClosed;Assert-PaMarkerOwner $journal.job;[IO.File]::Delete($script:PaMarker)
    }catch {
        $failure=$_
        if($Mode -eq 'Library' -and $failure.Exception.Message -eq 'simulated_crash'){throw}
        if(Get-PaGameRunning){Set-PaStatus 'waiting' 'close_game_to_recover';Wait-PaClosed $false}
        Restore-PaTransaction $journal
        throw $failure
    }
}
if($Mode -eq 'Library'){return}
$paLock=$null
try {
    Initialize-PaPaths $MoonLoader $JobRoot
    if($Mode -eq 'Status') {
        $active=Get-PaActive
        if($active){Write-PaJson (Join-Path $script:PaJob 'status.json') $active;exit 0}
        $result=Join-Path $script:PaState 'result.json'
        if([IO.File]::Exists($result)){
            $value=Read-PaJson $result
            $seen=if($value.job -cmatch '^[0-9a-f]{32}$'){[IO.File]::Exists((Join-Path $script:PaBase ('jobs\'+$value.job+'\receipt.seen')))}else{$false}
            $value|Add-Member -NotePropertyName receipt_seen -NotePropertyValue $seen -Force
            Write-PaJson (Join-Path $script:PaJob 'status.json') $value
        }else{Set-PaStatus 'idle' 'ready'}
        exit 0
    }
    try{$paLock=[IO.File]::Open((Join-Path $script:PaState 'worker.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'update_busy'}
    if($Mode -eq 'Recover') {
        if(-not [IO.File]::Exists($script:PaMarker)){Set-PaStatus 'idle' 'ready';exit 0}
        if([IO.File]::ReadAllText($script:PaMarker) -cne [IO.Path]::GetFileName($script:PaJob)){throw 'journal_owner_mismatch'}
        $journal=Read-PaJson (Join-Path $script:PaJob 'journal.json') 4194304
        Set-PaStatus 'waiting' 'close_game_to_recover';Wait-PaClosed $false
        if($journal.phase -eq 'committed'){
            foreach($row in $journal.plan){if((Get-PaHash (Get-PaPath $script:PaGame $row.path)) -ne $row.sha256){throw 'installed_hash_mismatch'}}
            Assert-PaClosed;[IO.File]::Delete($script:PaMarker);Set-PaStatus 'installed' 'update_installed' @{version=$journal.version;backup=$journal.backup}
        }else{Restore-PaTransaction $journal};exit 0
    }
    if([IO.File]::Exists($script:PaMarker)){throw 'recovery_required'}
    $request=Read-PaJson (Join-Path $script:PaJob 'request.json')
    if($request.product -cne 'police-assistant-2026' -or $request.moonloader -ine $script:PaML){throw 'invalid_request'}
    Set-PaStatus 'checking' 'checking'
    $candidate=Get-PaCandidate $request
    if(-not $candidate){Set-PaStatus 'current' 'no_new_version';exit 0}
    if($Mode -eq 'Check'){Set-PaStatus 'available' 'new_version' $candidate;exit 0}
    Assert-PaApproval $request $candidate
    Set-PaStatus 'downloading' 'downloading' @{version=$candidate.version}
    $archive=Join-Path $script:PaJob 'package.zip'
    Get-PaRemote $candidate.url 'asset' 67108864 $request.timeout_seconds $archive
    $folder=Join-Path $script:PaJob 'package';$manifest=Expand-PaPackage $archive $folder $candidate
    Set-PaStatus 'waiting' 'downloaded_close_game' @{version=$candidate.version}
    Wait-PaClosed
    Invoke-PaTransaction $folder $manifest
}catch {
    $code=$_.Exception.Message
    if($Mode -eq 'Recover' -and $code -eq 'update_busy'){exit 1}
    if($script:PaJob -and [IO.Directory]::Exists($script:PaJob)) {
        try{
            $journalPath=Join-Path $script:PaJob 'journal.json'
            if([IO.File]::Exists($journalPath) -and (Read-PaJson $journalPath 4194304).phase -eq 'rolled_back'){
                Set-PaStatus 'rolled_back' 'update_rolled_back' @{cause=$code}
            }else{Set-PaStatus $(if($code -eq 'cancelled'){'cancelled'}else{'error'}) $code}
        }catch{}
    }
    exit 1
}finally{if($paLock){$paLock.Dispose()}}
