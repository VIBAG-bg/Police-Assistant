# This entry point deliberately uses PowerShell 2 syntax. Do not load modern scripts before the check.
param([string]$Mode = 'Install', [switch]$Library)
$ErrorActionPreference = 'Stop'
function Get-PaCompatibilityIssue([version]$PowerShellVersion, [version]$WindowsVersion, [int]$ServicePack, [int]$FrameworkRelease) {
    if ($WindowsVersion.Major -lt 6 -or ($WindowsVersion.Major -eq 6 -and $WindowsVersion.Minor -lt 1)) { return 'windows' }
    if ($WindowsVersion.Major -eq 6 -and $WindowsVersion.Minor -eq 1 -and $ServicePack -lt 1) { return 'service_pack' }
    if ($PowerShellVersion -lt (New-Object Version('5.1'))) { return 'powershell' }
    if ($FrameworkRelease -lt 379893) { return 'framework' }
    return ''
}
function Show-PaStartupMessage([string]$Text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Text, 'Police Assistant', 'OK', 'Warning') | Out-Null
    } catch { Write-Host $Text }
}
if ($Library) { return }
try {
    $paStartRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $paNetRelease = 0
    try { $paNetRelease = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release).Release } catch {}
    $paOS = [Environment]::OSVersion
    $paIssue = Get-PaCompatibilityIssue $PSVersionTable.PSVersion $paOS.Version $(if($paOS.ServicePack -match '(\d+)'){[int]$matches[1]}else{0}) $paNetRelease
    if ($paIssue) {
        $paGuide = Join-Path $paStartRoot 'docs\WINDOWS-COMPATIBILITY.html'
        $paText = "Для установки PA нужны Windows 7 SP1 / 10 / 11, Windows PowerShell 5.1 и .NET Framework 4.5.2 или новее.`r`n`r`n"
        if ($paIssue -eq 'powershell') { $paText += "Сейчас запущен PowerShell " + $PSVersionTable.PSVersion + ". На Windows 7 установите Windows Management Framework 5.1 с сайта Microsoft, затем перезагрузите компьютер.`r`n`r`n" }
        elseif ($paIssue -eq 'service_pack') { $paText += "На Windows 7 сначала нужен Service Pack 1.`r`n`r`n" }
        elseif ($paIssue -eq 'framework') { $paText += "Сначала установите .NET Framework 4.5.2 или новее; для Windows 7 подходит .NET Framework 4.8.`r`n`r`n" }
        $paText += "Игра и личные данные не изменялись. Запуск от администратора не заменяет эти компоненты.`r`n`r`nОткрыть инструкцию?"
        Add-Type -AssemblyName System.Windows.Forms
        $paAnswer = [System.Windows.Forms.MessageBox]::Show($paText, 'Police Assistant — подготовка Windows', 'YesNo', 'Information')
        if ($paAnswer -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Process -FilePath $paGuide }
        exit 2
    }
    if ($Mode -eq 'Install') { & (Join-Path $paStartRoot 'tools\pa-setup-window.ps1') }
    elseif ($Mode -eq 'Monitor') { & (Join-Path $paStartRoot 'moonloader\resource\pa26\updater\pa26-update.ps1') -Mode Monitor }
    else { throw 'Unknown PA startup mode.' }
} catch {
    Show-PaStartupMessage ("Не удалось запустить PA.`r`n`r`n" + $_.Exception.Message + "`r`n`r`nРаспакуйте весь архив в обычную папку и повторите запуск. При ошибке «Отказано в доступе» проверьте права на выбранную папку.")
    exit 1
}
