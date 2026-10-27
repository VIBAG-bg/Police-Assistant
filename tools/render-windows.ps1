# Render the actual WinForms controls with fictitious display data for documentation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $release 'moonloader/resource/pa26/updater/pa26-update.ps1') -Mode Library
function Save-Window($Form,[string]$Name){
    try{
        $Form.Show();[Windows.Forms.Application]::DoEvents();$Form.PerformLayout();$Form.Refresh()
        $bitmap=New-Object Drawing.Bitmap($Form.Width,$Form.Height)
        try{$Form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$Form.Width,$Form.Height)));$bitmap.Save((Join-Path $release ('docs/images/'+$Name)),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }finally{$Form.Terminal=$true;$Form.Dispose()}
}
$form=New-PaProgressForm
$form.SetState('INSTALLING UPDATE','Installing 63 / 91 - MoonLoader/lib/pa26_studio.lua',85,'green',$false,$false,'0.40.2')
Save-Window $form 'update-window.png'
$form=New-Object PaSetupWindow
$form.Text='Police Assistant 0.40.2 | Установка'
$form.PathBox.Text='D:\Games\GTA San Andreas'
$form.PathBox.SelectionStart=0;$form.PathBox.SelectionLength=0
$form.Requirements.Text="encoding / iconv: уже есть`nmimgui: уже есть`nSAMP.Lua: будет скачана`nОбычный SA:MP — без замены CEF."
$form.Install.Text='Установить и докачать библиотеки';$form.Install.Enabled=$true
$form.ActiveControl=$form.Browse
Save-Window $form 'installation.png'
