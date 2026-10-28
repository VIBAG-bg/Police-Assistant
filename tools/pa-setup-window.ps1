[CmdletBinding()]
param([switch]$Library,[string]$InitialPath='',[string]$DependencyCache='',[int]$TestFailAfter=0)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$paSetupSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$paSetupManifest=Get-Content -LiteralPath (Join-Path $paSetupSource 'INSTALL_MANIFEST.json') -Raw|ConvertFrom-Json
foreach($row in $paSetupManifest.setup_files){
    $path=Join-Path $paSetupSource $row.path
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256){throw 'Setup integrity failed. Extract the complete release archive again.'}
}
$paSetupWorker=Join-Path $paSetupSource 'moonloader/resource/pa26/updater/pa26-update.ps1'
$workerEntry=@($paSetupManifest.files|Where-Object path -CEQ 'resource\pa26\updater\pa26-update.ps1')
if($workerEntry.Count -ne 1 -or (Get-FileHash -LiteralPath $paSetupWorker -Algorithm SHA256).Hash.ToLowerInvariant() -cne $workerEntry[0].sha256){throw 'Setup window integrity failed.'}
. (Join-Path $paSetupSource 'tools/pa-setup.ps1')
. $paSetupWorker -Mode Library
$paSetupDependencies=Read-PaDependencyManifest (Join-Path $paSetupSource 'DEPENDENCIES.json')

function Get-PaSetupExplanation([string]$Code){
    if($Code -like '*does not contain GTA*'){return 'В этой папке нет gta_sa.exe или gta-sa.exe. Выберите папку GTA San Andreas.'}
    if($Code -like '*Install MoonLoader first*'){return 'Сначала установите MoonLoader для своей сборки: рядом с GTA нужны moonloader.asi и lua51.dll.'}
    if($Code -like '*absolute GTA*'){return 'Укажите полный путь к папке GTA San Andreas или MoonLoader.'}
    if($Code -like '*reparse*' -or $Code -like '*link*'){return 'Путь содержит ссылку или перенаправление. Выберите обычную папку игры.'}
    if($Code -like '*Unauthorized*' -or $Code -like '*denied*' -or $Code -like '*доступ*'){return 'Нет доступа к папке. Распакуйте PA в обычную папку пользователя. Если сама игра защищена Windows, запустите «Установить PA.cmd» от администратора.'}
    if($Code -like '*partial*' -or $Code -like '*Incomplete library*'){return 'Найдена неполная библиотека другой версии. Восстановите её целиком из своей сборки; смешивать Lua и DLL разных версий нельзя.'}
    return $Code
}
function Get-PaSetupPreflight([string]$Selected){
    $ml=Resolve-PaSetupRoot $Selected
    $missing=@(Get-PaMissingDependencies $ml $paSetupDependencies)
    $game=[IO.Path]::GetDirectoryName($ml)
    $contract=Get-Content -LiteralPath (Join-Path $paSetupSource 'CEF_CONTRACT.json') -Raw|ConvertFrom-Json
    $main=Join-Path $game 'cef/assets/hud/main.js'
    Assert-PaSetupPlain $main
    $cef='Обычный SA:MP — без замены CEF.'
    if(Test-Path -LiteralPath $main){
        if((Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $contract.hud_main_sha256){$cef='Лаунчер Exsellent — адаптер CEF будет сохранён.'}
        else{$cef='Другой CEF — его файлы не заменяются.'}
    }
    $lines=@()
    foreach($package in $paSetupDependencies.packages){
        $needs=@($missing|Where-Object id -CEQ $package.id).Count -gt 0
        $lines+=($package.title+': '+$(if($needs){'будет скачана'}else{'уже есть'}))
    }
    return @{moonloader=$ml;missing=$missing.Count;details=($lines -join "`n")+"`n"+$cef;running=(@(Get-Process -Name gta_sa,gta-sa -ErrorAction SilentlyContinue).Count -gt 0)}
}
function Start-PaSetupChild([string]$Selected,[string]$Job,[string]$Cache='',[int]$FailAfter=0,[bool]$IncludeBinds=$true,[bool]$IncludeSettings=$true){
    $jobRoot=[IO.Path]::GetFullPath($Job)
    $base=[IO.Path]::GetFullPath((Join-Path $paSetupSource 'installation-backups/ui-jobs')).TrimEnd('\')
    if(-not $jobRoot.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase) -or $jobRoot.Substring($base.Length+1) -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid setup job.'}
    Assert-PaSetupPlain $jobRoot
    [IO.Directory]::CreateDirectory($jobRoot)|Out-Null
    $quote={param([string]$value) if($value -match '["\r\n]'){throw 'Invalid setup argument.'};return '"'+$value+'"'}
    $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File '+(&$quote (Join-Path $paSetupSource 'install.ps1'))+' -DestinationRoot '+(&$quote $Selected)+' -FetchDependencies -ProgressFile '+(&$quote (Join-Path $jobRoot 'progress.json'))
    if(-not $IncludeBinds){$args+=' -SkipAuthorBinds'}
    if(-not $IncludeSettings){$args+=' -SkipAuthorSettings'}
    if($Cache){$args+=' -DependencyCache '+(&$quote $Cache)}
    if($FailAfter){$args+=' -TestFailAfter '+$FailAfter}
    $exe=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
    $child=Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $paSetupSource -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $jobRoot 'output.log') -RedirectStandardError (Join-Path $jobRoot 'error.log')
    # Cache the handle before exit: Windows PowerShell otherwise may return a null ExitCode.
    $null=$child.Handle
    return $child
}
function Read-PaSetupJob([string]$Job){
    $row=Read-PaSharedJson (Join-Path $Job 'progress.json')
    if($row -and ((Get-PaField $row 'product') -cne 'police-assistant-setup' -or (Get-PaField $row 'job') -cne [IO.Path]::GetFileName($Job))){throw 'Setup status owner mismatch.'}
    return $row
}
function New-PaSetupForm {
 $form=New-Object PaSetupWindow
 $hostPanel=New-Object Windows.Forms.FlowLayoutPanel;$hostPanel.Dock='Fill';$hostPanel.FlowDirection='TopDown';$hostPanel.WrapContents=$false;$hostPanel.Margin=New-Object Windows.Forms.Padding(0)
 $binds=New-Object Windows.Forms.CheckBox;$binds.Text='Установить авторский бинд-лист';$binds.Checked=$true;$binds.AutoSize=$true;$binds.ForeColor=[PaUpdateWindow]::Ink
 $settings=New-Object Windows.Forms.CheckBox;$settings.Text='Установить авторские настройки';$settings.Checked=$true;$settings.AutoSize=$true;$settings.ForeColor=[PaUpdateWindow]::Ink
 $hostPanel.Controls.Add($binds);$hostPanel.Controls.Add($settings)
 $form.Current.Controls.Remove($form.Footer);$form.Current.Controls.Add($hostPanel,0,4)
 $form|Add-Member -NotePropertyName AuthorBinds -NotePropertyValue $binds
 $form|Add-Member -NotePropertyName AuthorSettings -NotePropertyValue $settings
 $form|Add-Member -NotePropertyName AuthorPanel -NotePropertyValue $hostPanel
 $form.Steps.Text='Свои данные сохраняются';$form.Steps.Width=200
 return $form
}
function Show-PaSetupWindow {
    $unused=New-PaProgressForm;$unused.Dispose()
    $form=New-PaSetupForm
    $form.Text='Police Assistant '+$paSetupManifest.release+' | Установка'
    $state=@{child=$null;job='';finished=$false;last=0;preflight=$null}
    # Event scriptblocks keep this script's function scope. GetNewClosure creates
    # a dynamic module which loses these helpers when launched with -File or &.
    $script:PaSetupUi=@{form=$form;state=$state;refresh=$null}
    $refresh={
        $form=$script:PaSetupUi.form;$state=$script:PaSetupUi.state
        if($state.child){return}
        try{
            $info=Get-PaSetupPreflight $form.PathBox.Text;$state.preflight=$info
            $form.Requirements.Text=$info.details
            $form.Install.Enabled=-not $info.running
            $form.Install.Text=if($info.missing){'Установить и докачать библиотеки'}else{'Установить PA'}
            $form.Footer.Text=if($info.running){'Закройте GTA, затем нажмите «Установить». Ни один файл игры пока не изменялся.'}else{'Настройки и бинды сохраняются. Перед записью создаются резервные копии.'}
        }catch{$state.preflight=$null;$form.Install.Enabled=$false;$form.Requirements.Text=Get-PaSetupExplanation $_.Exception.Message}
    }
    $script:PaSetupUi.refresh=$refresh
    $form.PathBox.Add_TextChanged($refresh)
    $form.Browse.Add_Click({
        $form=$script:PaSetupUi.form
        $picker=New-Object Windows.Forms.FolderBrowserDialog
        $picker.Description='Выберите папку GTA San Andreas или MoonLoader.';$picker.ShowNewFolderButton=$false
        if(Test-Path -LiteralPath $form.PathBox.Text){$picker.SelectedPath=$form.PathBox.Text}
        try{if($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$form.PathBox.Text=$picker.SelectedPath}}finally{$picker.Dispose()}
    })
    $form.Install.Add_Click({
        $form=$script:PaSetupUi.form;$state=$script:PaSetupUi.state
        if($state.child){return}
        try{
            & $script:PaSetupUi.refresh
            if(-not $state.preflight -or $state.preflight.running){return}
            $state.job=Join-Path $paSetupSource ('installation-backups/ui-jobs/'+[guid]::NewGuid().ToString('N'))
            $state.child=Start-PaSetupChild $state.preflight.moonloader $state.job $DependencyCache $TestFailAfter $form.AuthorBinds.Checked $form.AuthorSettings.Checked
            $form.Current.Controls.Remove($form.AuthorPanel);$form.Current.Controls.Add($form.Footer,0,4);$form.BeginInstallation();$state.last=2
        }catch{[Windows.Forms.MessageBox]::Show($form,(Get-PaSetupExplanation $_.Exception.Message),'Установка не началась','OK','Error')|Out-Null}
    })
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=400
    $timer.Add_Tick({
        $form=$script:PaSetupUi.form;$state=$script:PaSetupUi.state
        if(-not $state.child){& $script:PaSetupUi.refresh;return}
        if($state.finished){return}
        try{
            $row=Read-PaSetupJob $state.job
            if($row){
                $state.last=[Math]::Max(0,[Math]::Min(99,[int](Get-PaField $row 'percent' 0)))
                $titles=@{checking='CHECKING RELEASE';downloading='DOWNLOADING UPDATE';verifying_package='VERIFYING DOWNLOAD';backup='BACKING UP YOUR DATA';installing='INSTALLING UPDATE';verifying_install='VERIFYING INSTALLATION';paused='GTA REOPENED - PLEASE CLOSE IT';rollback='RESTORING PREVIOUS VERSION';completed='FINISHING SAFELY';failed='UPDATE NOT INSTALLED'}
                $stage=[string](Get-PaField $row 'stage');$heading=if($titles.ContainsKey($stage)){$titles[$stage]}else{'STARTING'}
                $form.SetState($heading,[string](Get-PaField $row 'detail'),$state.last,$(if($stage -in @('paused','rollback')){'amber'}else{'green'}),$false,$false,$paSetupManifest.release)
            }
            $state.child.Refresh()
            if($state.child.HasExited){
                $state.child.WaitForExit();$code=$state.child.ExitCode
                $row=Read-PaSetupJob $state.job
                $state.finished=$true
                if($code -eq 0 -and $row -and (Get-PaField $row 'stage') -ceq 'completed' -and (Get-PaField $row 'version') -ceq $paSetupManifest.release -and (Get-PaField $row 'terminal') -eq $true -and (Get-PaField $row 'safe') -eq $true){
                    $form.SetState('SUCCESS','PA установлен и проверен. Настройки и бинды сохранены. Можно запускать игру.',100,'green',$true,$true,$paSetupManifest.release)
                }else{
                    $safe=$row -and (Get-PaField $row 'stage') -ceq 'failed' -and (Get-PaField $row 'safe') -eq $true
                    $detail=if($row){Get-PaSetupExplanation ([string](Get-PaField $row 'detail'))}else{'Помощник установки завершился без подтверждения. Логи и копии сохранены в папке installation-backups.'}
                    $form.SetState('UPDATE NOT INSTALLED',$detail,$state.last,'red',$true,[bool]$safe,$paSetupManifest.release)
                    [Windows.Forms.MessageBox]::Show($form,($detail+"`n`nЛоги: "+$state.job),'Установка остановлена','OK','Error')|Out-Null
                }
            }
        }catch{
            $form.Detail.Text='Не удаётся прочитать состояние установки. Дождитесь завершения помощника. Код: '+$_.Exception.Message
            if($state.child.HasExited){$state.finished=$true;$form.SetState('UPDATE INTERRUPTED','Помощник завершился без проверенного результата. Сохраните логи из '+$state.job,$state.last,'red',$true,$false,$paSetupManifest.release)}
        }
    })
    if($InitialPath){$form.PathBox.Text=$InitialPath}else{$form.PathBox.Text=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher/game'}
    try{$timer.Start();[Windows.Forms.Application]::Run($form)}finally{$timer.Stop();$timer.Dispose();$form.Dispose();if($state.child){$state.child.Dispose()};$script:PaSetupUi=$null}
}
if(-not $Library){Show-PaSetupWindow}
