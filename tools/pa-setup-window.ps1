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
. (Join-Path $paSetupSource 'tools/pa-seed-presets.ps1')
. (Join-Path $paSetupSource 'tools/pa-legacy-migration.ps1')
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
function Start-PaSetupChild([string]$Selected,[string]$Job,[string]$Cache='',[int]$FailAfter=0,[bool]$IncludeBinds=$true,[bool]$IncludeSettings=$true,[bool]$Legacy=$true,[string]$Preview=''){
    $jobRoot=[IO.Path]::GetFullPath($Job)
    $base=[IO.Path]::GetFullPath((Join-Path $paSetupSource 'installation-backups/ui-jobs')).TrimEnd('\')
    if(-not $jobRoot.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase) -or $jobRoot.Substring($base.Length+1) -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid setup job.'}
    Assert-PaSetupPlain $jobRoot
    [IO.Directory]::CreateDirectory($jobRoot)|Out-Null
    $quote={param([string]$value) if($value -match '["\r\n]'){throw 'Invalid setup argument.'};return '"'+$value+'"'}
    $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File '+(&$quote (Join-Path $paSetupSource 'install.ps1'))+' -DestinationRoot '+(&$quote $Selected)+' -FetchDependencies -ProgressFile '+(&$quote (Join-Path $jobRoot 'progress.json'))
    if(-not $IncludeBinds){$args+=' -SkipAuthorBinds'}
    if(-not $IncludeSettings){$args+=' -SkipAuthorSettings'}
    if(-not $Legacy){$args+=' -SkipLegacyPresets'}
    if($Preview){$args+=' -LegacyPreview '+(&$quote $Preview)}
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
 $binds=New-Object Windows.Forms.CheckBox;$binds.Text='Авторский бинд-лист при первой установке';$binds.Checked=$true;$binds.AutoSize=$true;$binds.ForeColor=[PaUpdateWindow]::Ink
 $settings=New-Object Windows.Forms.CheckBox;$settings.Text='Авторские настройки при первой установке';$settings.Checked=$true;$settings.AutoSize=$true;$settings.ForeColor=[PaUpdateWindow]::Ink
 $hostPanel.Controls.Add($binds);$hostPanel.Controls.Add($settings)
 $form.Current.Controls.Remove($form.Footer);$form.Current.Controls.Add($hostPanel,0,4)
 $form|Add-Member -NotePropertyName AuthorBinds -NotePropertyValue $binds
 $form|Add-Member -NotePropertyName AuthorSettings -NotePropertyValue $settings
 $form|Add-Member -NotePropertyName AuthorPanel -NotePropertyValue $hostPanel
 $form.Steps.Text='Свои данные сохраняются';$form.Steps.Width=200
 return $form
}
function Get-PaLegacyReviewText($Review){
    $lines=New-Object 'Collections.Generic.List[string]'
    $lines.Add('Обновляются стандартные настройки PA, оба колеса и штатные правила ручных команд.')
    $lines.Add('Сохраняются личные записи, контакты, профиль, пол персонажа, заметки и размеры окон.')
    $lines.Add('')
    foreach($pair in @(@('added','Новые официальные записи'),@('updated','Обновлённые штатные записи'),@('personal','Личные записи в «Свои бинды»'))){
        $lines.Add($pair[1])
        foreach($row in $Review[$pair[0]]){
            $lines.Add(('№ '+$row.id+' · '+$row.name))
            if($row -is [Collections.IDictionary] -and $row.ContainsKey('after')){
                if($row.ContainsKey('before') -and $row.before -cne $row.after){$lines.Add("Было`r`n"+$row.before)}
                $lines.Add("В наборе 0.45.2`r`n"+$row.after)
            }
        }
        $lines.Add('')
    }
    $lines.Add('Сохранённые личные правила команд')
    foreach($item in $Review.personalRules){$lines.Add($item)}
    $lines.Add('Разрешение конфликтов')
    foreach($item in $Review.conflicts){$lines.Add($item)}
    return $lines -join "`r`n"
}
function Show-PaLegacyReview($Owner,$Review){
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='Первичное обновление биндов и настроек PA'
    $dialog.StartPosition='CenterParent';$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false
    $area=[Windows.Forms.Screen]::FromControl($Owner).WorkingArea
    $dialog.ClientSize=New-Object Drawing.Size([Math]::Min(680,$area.Width-36),[Math]::Min(365,$area.Height-72))
    $dialog.Font=New-Object Drawing.Font('Segoe UI',10)
    $dialog.BackColor=[Drawing.Color]::FromArgb(23,33,51);$dialog.ForeColor=[PaUpdateWindow]::Ink
    $panel=New-Object Windows.Forms.TableLayoutPanel
    $panel.Dock='Fill';$panel.Padding=New-Object Windows.Forms.Padding(20);$panel.ColumnCount=1;$panel.RowCount=4
    foreach($style in @('Percent','AutoSize','AutoSize','AutoSize')){
        $row=New-Object Windows.Forms.RowStyle;$row.SizeType=$style;if($style -ceq 'Percent'){$row.Height=100}
        $panel.RowStyles.Add($row)|Out-Null
    }
    $summary=New-Object Windows.Forms.Label;$summary.Dock='Fill'
    $summary.Text="Найдена PA 0.44.0. Набор 0.45.2 заменит штатные бинды и их RP, включая ранее отредактированные. Отдельные личные записи сохранятся.`r`n`r`n"+
        ('Новые бинды · '+$Review.added.Count+'     Обновляемые · '+$Review.updated.Count+'     Личные · '+$Review.personal.Count)+"`r`n"+
        ('Конфликты с приоритетом личных записей · '+$Review.conflicts.Count)+"`r`n`r`n"+
        'Сохранятся профиль, пол персонажа, контакты, заметки и размеры окон. Если снять галочку, установится только программа.'
    $option=New-Object Windows.Forms.CheckBox;$option.AutoSize=$true;$option.Checked=$true
    $option.Text='Обновить авторские бинды и стандартные настройки до 0.45.2'
    $details=New-Object Windows.Forms.Button;$details.AutoSize=$true;$details.Text='Посмотреть изменения'
    $details.Tag=Get-PaLegacyReviewText $Review
    $details.Add_Click({
        $owner=$this.FindForm()
        $view=New-Object Windows.Forms.Form;$view.Text='Предпросмотр набора PA 0.45.2';$view.StartPosition='CenterParent'
        $view.ClientSize=New-Object Drawing.Size($owner.ClientSize.Width,$owner.ClientSize.Height)
        $body=New-Object Windows.Forms.TextBox;$body.Dock='Fill';$body.Multiline=$true;$body.ReadOnly=$true
        $body.WordWrap=$true;$body.ScrollBars='Vertical';$body.Text=[string]$this.Tag
        $view.Controls.Add($body)
        try{$null=$view.ShowDialog($owner)}finally{$view.Dispose()}
    })
    $actions=New-Object Windows.Forms.FlowLayoutPanel;$actions.AutoSize=$true;$actions.FlowDirection='RightToLeft';$actions.Dock='Fill'
    $accept=New-Object Windows.Forms.Button;$accept.Text='Продолжить установку';$accept.AutoSize=$true;$accept.DialogResult='OK'
    $cancel=New-Object Windows.Forms.Button;$cancel.Text='Отмена';$cancel.AutoSize=$true;$cancel.DialogResult='Cancel'
    $actions.Controls.Add($accept);$actions.Controls.Add($cancel)
    $panel.Controls.Add($summary,0,0);$panel.Controls.Add($option,0,1);$panel.Controls.Add($details,0,2);$panel.Controls.Add($actions,0,3)
    $dialog.Controls.Add($panel);$dialog.AcceptButton=$accept;$dialog.CancelButton=$cancel
    try{
        $result=$dialog.ShowDialog($Owner)
        return @{proceed=$result -eq [Windows.Forms.DialogResult]::OK;apply=$option.Checked}
    }finally{$dialog.Dispose()}
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
            $ml=$state.preflight.moonloader
            $offer=Get-PaLegacyOffer $paSetupSource $ml $paSetupManifest.release
            $legacy=$false;$token=''
            if($offer -ceq 'offer'){
                $form.Requirements.Text='Подготавливаю предпросмотр набора. Файлы PA пока сохранены без изменений.'
                $form.Refresh()
                try{$prepared=Get-PaLegacyPresetPlan $paSetupSource $ml $paSetupManifest $DependencyCache $true}
                catch{
                    $answer=[Windows.Forms.MessageBox]::Show($form,($_.Exception.Message+"`r`n`r`nПродолжить установку программы с прежними личными файлами?"),'Предпросмотр набора недоступен','YesNo','Warning')
                    if($answer -ne [Windows.Forms.DialogResult]::Yes){return}
                    $prepared=$null
                }
                if($prepared){
                    $choice=Show-PaLegacyReview $form $prepared.review
                    if(-not $choice.proceed){return}
                    $legacy=$choice.apply
                    if($legacy){$token=$prepared.token}
                }
            }
            $state.job=Join-Path $paSetupSource ('installation-backups/ui-jobs/'+[guid]::NewGuid().ToString('N'))
            $state.child=Start-PaSetupChild $ml $state.job $DependencyCache $TestFailAfter $form.AuthorBinds.Checked $form.AuthorSettings.Checked $legacy $token
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
                if($code -eq 0 -and $row -and (Get-PaField $row 'stage') -cin @('completed','recovered') -and (Get-PaField $row 'version') -ceq $paSetupManifest.release -and (Get-PaField $row 'terminal') -eq $true -and (Get-PaField $row 'safe') -eq $true){
                    $form.SetState('SUCCESS',[string](Get-PaField $row 'detail'),100,'green',$true,$true,$paSetupManifest.release)
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
