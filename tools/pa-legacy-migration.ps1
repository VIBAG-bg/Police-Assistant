# Keep the migration identity and directory from the withdrawn 0.45.2 so an
# existing receipt stays valid after renumbering the replacement to 0.45.1.
$script:PaLegacyTargetRelease='0.45.1'
$script:PaLegacyMigrationId='manual_0440_to_0452_author_presets_v1'
$script:PaLegacyRuntimeHash='ff976f6e965e3793e278fa9bf5e80b9b226a0b3932b9da764bffc8e41e6cdb60'

function Get-PaLegacyStateRoot([string]$MoonLoader){
    return Get-PaSetupPath $MoonLoader 'config/police_assistant_2026_legacy_0452'
}

function Get-PaLegacyOffer([string]$Source,[string]$MoonLoader,[string]$Release){
    $state=Get-PaLegacyStateRoot $MoonLoader
    if([IO.File]::Exists((Join-Path $state 'pending.json'))){return 'recover'}
    if($Release -cne $script:PaLegacyTargetRelease -or (Test-Path -LiteralPath (Join-Path $state 'completed.json'))){return 'none'}
    $legacy=Read-PaPresetJson ([IO.File]::ReadAllText((Join-Path $Source 'tools/pa-legacy-0440.json')))
    if($legacy.release -cne '0.44.0' -or $legacy.files.Count -ne 2){throw 'Повреждён каталог версии 0.44.0.'}
    foreach($name in @('police_assistant_2026.lua','lib/pa26_core.lua')){
        $expected=$legacy.files[$name]
        if($expected -cnotmatch '^[a-f0-9]{64}$'){throw 'Повреждены контрольные суммы 0.44.0.'}
        $path=Get-PaSetupPath $MoonLoader $name
        if(-not [IO.File]::Exists($path) -or (Get-Item -LiteralPath $path).Length -gt 1048576 -or (Get-PaHash $path) -cne $expected){return 'none'}
    }
    return 'offer'
}

function Read-PaLegacySnapshot([string]$MoonLoader){
    $paths=@{binds='config/police_assistant_2026_binds.json';settings='config/police_assistant_2026_settings.json';
        notes='config/police_assistant_2026_notes.json';library='config/police_assistant_2026_library.json';
        ini='config/police_assistant_2026.ini'}
    foreach($tail in @('_files_pending.json','_preset_pending.json')){
        foreach($suffix in @('','.bak','.rollback')){
            if(Test-Path -LiteralPath (Get-PaSetupPath $MoonLoader ('config/police_assistant_2026'+$tail+$suffix))){
                throw 'Сначала завершите восстановление личных файлов в прежней версии PA.'
            }
        }
    }
    $data=@{};$hashes=@{};$utf8=New-Object Text.UTF8Encoding($false,$true)
    foreach($kind in $paths.Keys){
        $path=Get-PaSetupPath $MoonLoader $paths[$kind]
        foreach($suffix in @('.rollback','.pa26-next','.pa26-previous')){
            if(Test-Path -LiteralPath ($path+$suffix)){throw 'Найдены файлы незавершённого сохранения PA.'}
        }
        $hashes[$kind]=''
        if(-not [IO.File]::Exists($path)){
            if(Test-Path -LiteralPath ($path+'.bak')){throw 'Отсутствует личный файл, для которого есть резервная копия.'}
            continue
        }
        $before=Get-PaHash $path
        $limit=if($kind -eq 'ini'){32768}else{1048576}
        if((Get-Item -LiteralPath $path).Length -gt $limit){throw 'Личный файл превышает поддерживаемый размер.'}
        $text=$utf8.GetString([IO.File]::ReadAllBytes($path)).TrimStart([char]0xfeff)
        if((Get-PaHash $path) -cne $before){throw 'Личные файлы изменились во время чтения.'}
        $hashes[$kind]=$before
        if($kind -ceq 'ini'){$data[$kind]=$text}
        elseif($kind -cne 'library' -or -not [IO.File]::Exists((Get-PaSetupPath $MoonLoader $paths.binds))){
            $data[$kind]=Read-PaPresetJson $text
            if($data[$kind] -isnot [Collections.IDictionary]){throw 'Личный документ PA должен быть объектом JSON.'}
        }
    }
    return @{paths=$paths;hashes=$hashes;data=$data}
}

function Get-PaLegacyLuaFile([string]$Source,[string]$MoonLoader,[string]$Cache,[bool]$Download,[string]$Stage){
    $game=[IO.Path]::GetDirectoryName($MoonLoader)
    $installed=Get-PaSetupPath $game 'lua51.dll'
    $target=Join-Path $Stage 'lua51.dll'
    if([IO.File]::Exists($installed) -and (Get-Item -LiteralPath $installed).Length -eq 606208 -and (Get-PaHash $installed) -ceq $script:PaLegacyRuntimeHash){
        [IO.File]::Copy($installed,$target)
        return
    }
    # Same pinned dependency archive already used for encoding. The verified
    # runtime is extracted for this process and stays outside the game.
    $dependencies=Read-PaDependencyManifest (Join-Path $Source 'DEPENDENCIES.json')
    $package=@($dependencies.packages|Where-Object id -CEQ 'encoding')[0]
    if(-not $Cache){$Cache=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PoliceAssistant2026/setup-cache'}
    $archive=Get-PaSetupPath $Cache ($package.sha256+'.zip')
    if(-not [IO.File]::Exists($archive)){
        if(-not $Download){throw 'Для переноса нужен проверенный LuaJIT. Запустите обычное окно установки или пропустите перенос.'}
        $archive=Join-Path $Stage 'runtime.zip'
        Save-PaDependencyArchive $package $archive
    }
    if((Get-Item -LiteralPath $archive).Length -ne $package.size -or (Get-PaHash $archive) -cne $package.sha256){throw 'Архив проверочного LuaJIT не прошёл проверку.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try{
        $entry=$zip.GetEntry('lua51.dll')
        if(-not $entry -or $entry.Length -ne 606208){throw 'В проверенном архиве отсутствует LuaJIT.'}
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target)
    }finally{$zip.Dispose()}
}

function Invoke-PaLegacyMerge([string]$Source,[string]$MoonLoader,$Data,[string]$Cache,[bool]$Download){
    $stage=Join-Path ([IO.Path]::GetTempPath()) ('pa452-'+[Guid]::NewGuid().ToString('N'))
    Assert-PaSetupPlain $stage
    [IO.Directory]::CreateDirectory($stage)|Out-Null
    $json=New-Object Web.Script.Serialization.JavaScriptSerializer
    $json.MaxJsonLength=8388608;$json.RecursionLimit=64
    $child=$null
    try{
        Get-PaLegacyLuaFile $Source $MoonLoader $Cache $Download $stage
        [IO.File]::WriteAllText((Join-Path $stage 'in.json'),$json.Serialize($Data),(New-Object Text.UTF8Encoding($false)))
        $engine=if([Environment]::Is64BitOperatingSystem){'SysWOW64'}else{'System32'}
        $exe=Join-Path $env:WINDIR ($engine+'/WindowsPowerShell/v1.0/powershell.exe')
        $runner=Join-Path $Source 'tools/pa-legacy-lua.ps1'
        foreach($argument in @($runner,$Source,$stage)){if($argument -match '["\r\n]'){throw 'Неверный путь к установщику.'}}
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$runner+'" -Source "'+$Source+'" -Stage "'+$stage+'"'
        $child=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $stage -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $stage 'host.txt')
        $null=$child.Handle
        if(-not $child.WaitForExit(90000)){$child.Kill();$child.WaitForExit();throw 'Истекло время проверки личного набора.'}
        $out=Join-Path $stage 'out.json';$errorPath=Join-Path $stage 'error.txt'
        if($child.ExitCode -ne 0 -or -not [IO.File]::Exists($out)){
            $detail=if([IO.File]::Exists($errorPath)){[IO.File]::ReadAllText($errorPath)}else{[IO.File]::ReadAllText((Join-Path $stage 'host.txt'))}
            throw ('Перенос не подготовлен. '+$detail.Substring(0,[Math]::Min(700,$detail.Length)))
        }
        if((Get-Item -LiteralPath $out).Length -gt 8388608){throw 'Результат переноса превышает допустимый размер.'}
        return ,$json.DeserializeObject([IO.File]::ReadAllText($out))
    }finally{
        if($child){$child.Dispose()}
        foreach($name in @('in.json','out.json','error.txt','host.txt','runtime.zip','lua51.dll')){
            $file=Join-Path $stage $name
            if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
        }
        [IO.Directory]::Delete($stage)
    }
}

function Get-PaLegacyPresetPlan([string]$Source,[string]$MoonLoader,$Manifest,[string]$Cache,[bool]$Download){
    if((Get-PaLegacyOffer $Source $MoonLoader $Manifest.release) -cne 'offer'){throw 'Исходная версия для переноса больше не подтверждается.'}
    $presets=Read-PaAuthorPresets $Source $Manifest
    $snapshot=Read-PaLegacySnapshot $MoonLoader
    $data=$snapshot.data
    $data.legacy=Read-PaPresetJson ([IO.File]::ReadAllText((Join-Path $Source 'tools/pa-legacy-0440.json')))
    $data.official_binds=$presets['pa-binds'];$data.official_settings=$presets['pa-settings']
    $merged=Invoke-PaLegacyMerge $Source $MoonLoader $data $Cache $Download
    foreach($field in @('added','updated','personal','conflicts','personalRules')){
        $items=$merged.review[$field]
        if($items -is [Collections.IDictionary] -and $items.Count -eq 0){$merged.review[$field]=[object[]]@()}
        elseif($items -isnot [Array]){throw 'Предпросмотр переноса не прошёл проверку.'}
    }
    $current=Read-PaLegacySnapshot $MoonLoader
    if(-not (Test-PaPresetEqual $snapshot.hashes $current.hashes)){throw 'Личные файлы изменились во время предпросмотра.'}
    $lines=@($Manifest.release)
    foreach($key in @('binds','settings','notes','library','ini')){$lines+=($key+'='+$snapshot.hashes[$key])}
    foreach($row in $Manifest.preset_files){$lines+=($row.path+'='+$row.sha256)}
    $replace=@{};$plan=@();$utf8=New-Object Text.UTF8Encoding($false)
    foreach($kind in @('binds','settings','notes','ini')){
        if(-not $merged.ContainsKey($kind)){continue}
        $relative=$snapshot.paths[$kind].Replace('/','\')
        $target=Get-PaSetupPath $MoonLoader $snapshot.paths[$kind]
        $serialized=if($kind -ceq 'ini'){$merged[$kind]}else{Write-PaPresetJson $merged[$kind]}
        $bytes=$utf8.GetBytes($serialized)
        if($bytes.Length -gt $(if($kind -ceq 'ini'){32768}else{1048576})){throw 'Личный документ после переноса превышает допустимый размер.'}
        $hash=Get-PaLegacyByteHash $bytes
        $existed=[bool]$snapshot.hashes[$kind]
        $plan+=,[PSCustomObject]@{Relative=$relative;Source=$null;Target=$target;SHA256=$hash;Existed=$existed;
            BeforeHash=$snapshot.hashes[$kind];Skip=$false;Root=$MoonLoader;BackupRelative='';Content=$bytes}
        if($existed){$replace[$target]=$hash}
    }
    return @{plan=$plan;replace=$replace;summary=@{binds='migrated';settings='migrated';notes='preserved';migration=$script:PaLegacyMigrationId};
        token=(Get-PaKey ($lines -join "`n"));review=$merged.review}
}

function Get-PaLegacyByteHash([byte[]]$Bytes){
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}
    finally{$hash.Dispose()}
}

function Get-PaLegacyReceipt([string]$State){
    $receipt=Get-PaSetupPath $State 'completed.json'
    if(-not [IO.File]::Exists($receipt)){return $null}
    $row=Read-PaJson $receipt 4096
    if($row.schema -ne 1 -or $row.migration -cne $script:PaLegacyMigrationId -or $row.job -cnotmatch '^manual-0452-[0-9a-f]{32}$'){
        throw 'Отметка переноса повреждена. Повторное применение набора остановлено.'
    }
    return $row
}

function Open-PaManualInstallLock([string]$MoonLoader,[bool]$Test,[string]$Source){
    # The real updater uses the same worker.lock. Setup must serialize with it.
    $lockRoot=if($Test){Join-Path $Source ('installation-backups/test-locks/'+(Get-PaKey $MoonLoader))}
        else{Join-Path $script:PaBase ('games\'+(Get-PaKey $MoonLoader))}
    Assert-PaSetupPlain $lockRoot
    [IO.Directory]::CreateDirectory($lockRoot)|Out-Null
    $lock=Get-PaSetupPath $lockRoot 'worker.lock'
    try{return [IO.File]::Open($lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch{throw 'Для этой папки уже идёт установка или обновление PA.'}
}

function Get-PaLegacyMarker([string]$MoonLoader){
    return Get-PaSetupPath $MoonLoader 'pa26-update.pending'
}

function Get-PaLegacyAllowedRows($Manifest,$Dependencies){
    $allowed=@{}
    foreach($row in $Manifest.files){$allowed['MoonLoader/'+$row.path.Replace('\','/')]=$row.sha256}
    foreach($pack in $Dependencies.packages){
        foreach($row in $pack.files){$allowed['MoonLoader/'+$row.target]=$row.sha256}
    }
    foreach($kind in @('binds','settings','notes')){
        $allowed['MoonLoader/config/police_assistant_2026_'+$kind+'.json']=''
    }
    foreach($row in $Manifest.cef_files){$allowed['cef/assets/hud/'+$row.path]=$row.sha256}
    $allowed['cef/assets/hud/index.html']=''
    # The validated merged INI is part of the same file transaction.
    $allowed['MoonLoader/config/police_assistant_2026.ini']=''
    return $allowed
}

function Start-PaLegacyTransaction([string]$MoonLoader,[string]$Job,$Plan){
    $state=Get-PaLegacyStateRoot $MoonLoader
    $pending=Get-PaSetupPath $state 'pending.json'
    $marker=Get-PaLegacyMarker $MoonLoader
    if([IO.File]::Exists($pending) -or [IO.File]::Exists($marker) -or (Get-PaLegacyReceipt $state)){throw 'Ожидается восстановление предыдущей установки PA.'}
    $game=[IO.Path]::GetDirectoryName($MoonLoader)
    $rows=@(foreach($row in $Plan){
        if($row.Skip){continue}
        if(-not $row.Target.StartsWith($game+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected migration target.'}
        @{
            path=$row.Target.Substring($game.Length+1).Replace('\','/'); backup=$row.BackupRelative.Replace('\','/')
            before=([string]$row.BeforeHash).ToLowerInvariant(); after=$row.SHA256.ToLowerInvariant()
        }
    })
    Write-PaJson $pending @{schema=1;migration=$script:PaLegacyMigrationId;job=$Job;source='0.44.0';destination=$script:PaLegacyTargetRelease;rows=$rows}
    # The manual prefix keeps the old automatic worker from trying to open
    # this setup-only journal. The bootstrap still pauses PA while it exists.
    Write-PaBytes $marker ([Text.Encoding]::ASCII.GetBytes($Job))
}

function Get-PaLegacyJournal([string]$MoonLoader,$Manifest,$Dependencies){
    $state=Get-PaLegacyStateRoot $MoonLoader
    $pending=Get-PaSetupPath $state 'pending.json'
    if(-not [IO.File]::Exists($pending)){return $null}
    $journal=Read-PaJson $pending 262144
    $rows=@($journal.rows)
    if($journal.schema -ne 1 -or $journal.migration -cne $script:PaLegacyMigrationId -or
        $journal.source -cne '0.44.0' -or $journal.destination -cnotin @($script:PaLegacyTargetRelease,'0.45.2') -or
        $journal.job -cnotmatch '^manual-0452-[0-9a-f]{32}$' -or $rows.Count -lt 1 -or $rows.Count -gt 512){
        throw 'Журнал переноса PA повреждён.'
    }
    $receipt=Get-PaLegacyReceipt $state
    if($receipt -and $receipt.job -cne $journal.job){throw 'Отметка завершения относится к другой установке.'}
    $marker=Get-PaLegacyMarker $MoonLoader
    $hasMarker=[IO.File]::Exists($marker)
    if($hasMarker -and ((Get-Item -LiteralPath $marker).Length -gt 128 -or [IO.File]::ReadAllText($marker) -cne $journal.job)){
        throw 'Папка PA занята другой операцией обновления.'
    }
    $backup=Get-PaSetupPath $state ('backup-'+$journal.job.Substring('manual-0452-'.Length))
    $allow=Get-PaLegacyAllowedRows $Manifest $Dependencies
    $previous=@{}
    if($journal.destination -ceq '0.45.2'){
        # Only the reviewed old destination bytes may be restored from an
        # interrupted install. Unchanged paths still use the current manifest.
        $previous=@{
            'moonloader/police_assistant_2026.lua'=@('8300d6172e1c646e2a23def5810cd2476bdde3d52a8125f04e196b5521edc866')
            'moonloader/lib/pa26_core.lua'=@('bbc37eda15c32f0ea59bed1895f7a64ba1cad2c6a7deaff1d9598478eafeeb65')
            'moonloader/lib/pa26_cef_contract.lua'=@('76a96be5bc45120eda4e20d299e1e89a78674e6fea3ab33b9b447207b10df01a','a5972c3fbe90d3e6559d412fcac49fa66fa7fa9b94a30f039ab90c765d36565f')
            'moonloader/lib/pa26_help.lua'=@('0085208881fb4e45f973a9f27a32df9257c79fa6f521568815c49a09b8ad54f0','5710b591a7f039837d52523956e1ad07572a5dc7eabfacf9c21c2c43c6415870')
        }
    }
    $game=[IO.Path]::GetDirectoryName($MoonLoader)
    $seen=@{};$saved=@{}
    $restore=@(foreach($row in $rows){
        $relative=([string]$row.path).ToLowerInvariant()
        $expected=if($previous.ContainsKey($relative)){$previous[$relative]}else{$allow[$relative]}
        if($relative -cnotmatch '^[a-z0-9_./-]+$' -or -not $allow.ContainsKey($relative) -or
            $seen.ContainsKey($relative) -or $row.backup -cnotmatch '^runtime/[0-9]{4}\.bin$' -or $saved.ContainsKey($row.backup) -or
            $row.before -cnotmatch '^([a-f0-9]{64})?$' -or $row.after -cnotmatch '^[a-f0-9]{64}$' -or
            ($expected -and $row.after -cnotin @($expected))){
            throw 'Журнал содержит неподтверждённый файл.'
        }
        $seen[$relative]=$true;$saved[$row.backup]=$true
        $target=Get-PaSetupPath $game $row.path
        if($row.path.StartsWith('MoonLoader/',[StringComparison]::OrdinalIgnoreCase)){
            $target=Get-PaSetupPath $MoonLoader $row.path.Substring('MoonLoader/'.Length)
        }
        $actual=if([IO.File]::Exists($target)){Get-PaHash $target}else{''}
        if(($actual -cne $row.before -and $actual -cne $row.after) -or
            ($receipt -and $actual -cne $row.after) -or
            (-not $receipt -and -not $hasMarker -and $actual -cne $row.before)){
            throw ('Файл изменился после подготовки. Резервные копии сохранены. '+$row.path)
        }
        $copy=Get-PaSetupPath $backup $row.backup
        if($row.before -and ((-not [IO.File]::Exists($copy)) -or (Get-PaHash $copy) -cne $row.before)){
            throw ('Резервная копия не прошла проверку. '+$row.path)
        }
        @{target=$target;backup=$copy;actual=$actual;before=$row.before;after=$row.after}
    })
    return @{job=$journal.job;pending=$pending;marker=$marker;hasMarker=$hasMarker;receipt=$receipt;restore=$restore}
}

function Complete-PaLegacyTransaction([string]$MoonLoader,[string]$Job){
    $state=Get-PaLegacyStateRoot $MoonLoader
    $marker=Get-PaLegacyMarker $MoonLoader
    if([IO.File]::ReadAllText($marker) -cne $Job){throw 'Журнал установки не совпал с активной операцией.'}
    Write-PaJson (Get-PaSetupPath $state 'completed.json') @{
        schema=1;migration=$script:PaLegacyMigrationId;job=$Job;committed=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::Delete($marker)
    [IO.File]::Delete((Get-PaSetupPath $state 'pending.json'))
}

function Repair-PaLegacyTransaction([string]$MoonLoader,$Manifest,$Dependencies){
    $journal=Get-PaLegacyJournal $MoonLoader $Manifest $Dependencies
    if(-not $journal){throw 'Журнал переноса отсутствует.'}
    if(-not $journal.receipt){
        # Validate the entire journal and every backup before restoring a byte.
        foreach($row in $journal.restore){
            if($row.actual -ceq $row.before){continue}
            if(-not [IO.File]::Exists($row.target) -or (Get-PaHash $row.target) -cne $row.after){throw 'Во время восстановления файл был изменён.'}
            if($row.before){
                Write-PaBytes $row.target ([IO.File]::ReadAllBytes($row.backup))
                if((Get-PaHash $row.target) -cne $row.before){throw 'Восстановленный файл не прошёл проверку.'}
            }else{[IO.File]::Delete($row.target)}
        }
    }
    if($journal.hasMarker){
        if([IO.File]::ReadAllText($journal.marker) -cne $journal.job){throw 'Владелец операции изменился.'}
        [IO.File]::Delete($journal.marker)
    }
    [IO.File]::Delete($journal.pending)
    return [bool]$journal.receipt
}
