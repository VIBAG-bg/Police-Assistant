[CmdletBinding()]
param([ValidateSet('Check','Prepare','Status','Recover','Progress','Monitor','Library')][string]$Mode='Check',[string]$MoonLoader,[string]$JobRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:PaProtocol=1
$script:PaBase=[IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'),'PoliceAssistant2026','updates')
$script:PaFault=$null
$script:PaJob=$null;$script:PaML=$null;$script:PaState=$null
$script:PaPresentation=$false;$script:PaProgressPercent=0;$script:PaTargetVersion='';$script:PaViewProcess=$null
$script:PaWorkerPath=$PSCommandPath
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
function Get-PaField($value,[string]$key,$fallback=$null) {
    if($null -eq $value){return $fallback}
    if($value -is [Collections.IDictionary]){if($value.Contains($key)){return $value[$key]}}
    elseif($value.PSObject.Properties[$key]){return $value.PSObject.Properties[$key].Value}
    return $fallback
}
function Read-PaSharedJson([string]$path) {
    Assert-PaPlain $path
    if(-not [IO.File]::Exists($path)){return $null}
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if($stream.Length -gt 4194304){throw 'oversize_json'}
        $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8)
        try{return ($reader.ReadToEnd()|ConvertFrom-Json)}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}
function Set-PaProgress([string]$stage,[int]$percent,[string]$detail='') {
    if(-not $script:PaPresentation -or -not $script:PaJob){return}
    $script:PaProgressPercent=[Math]::Max(0,[Math]::Min(99,$percent))
    try {
        Write-PaJson (Join-Path $script:PaJob 'progress.json') @{product='police-assistant-2026';job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;
            stage=$stage;percent=$script:PaProgressPercent;detail=$detail;version=$script:PaTargetVersion;pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks}
    }catch{} # Presentation failures must never change the installation result.
}
function Get-PaProgressView {
    $v=@{heading='STARTING';detail='Preparing update status...';percent=0;terminal=$false;safe=$false;tone='green';version='';step=0}
    $status=Read-PaSharedJson (Join-Path $script:PaJob 'status.json')
    $progress=Read-PaSharedJson (Join-Path $script:PaJob 'progress.json')
    foreach($row in @($status,$progress)){
        if($row -and ((Get-PaField $row 'product') -cne 'police-assistant-2026' -or (Get-PaField $row 'job') -cne [IO.Path]::GetFileName($script:PaJob) -or (Get-PaField $row 'moonloader') -ine $script:PaML)){throw 'progress_owner_mismatch'}
    }
    $titles=@{checking='CHECKING RELEASE';downloading='DOWNLOADING UPDATE';verifying_package='VERIFYING DOWNLOAD';waiting='CLOSE GTA TO CONTINUE';
        backup='BACKING UP YOUR DATA';installing='INSTALLING UPDATE';verifying_install='VERIFYING INSTALLATION';finishing='FINISHING SAFELY';
        paused='GTA REOPENED - PLEASE CLOSE IT';rollback='RESTORING PREVIOUS VERSION';recovering='RECOVERING UPDATE'}
    if($progress){
        $stage=[string](Get-PaField $progress 'stage' '')
        if($titles.ContainsKey($stage)){$v.heading=$titles[$stage]}
        $v.percent=[Math]::Max(0,[Math]::Min(99,[int](Get-PaField $progress 'percent' 0)))
        $v.detail=[string](Get-PaField $progress 'detail' '');$v.version=[string](Get-PaField $progress 'version' '')
        if($stage -in @('paused','waiting','rollback','recovering')){$v.tone='amber'}
    }
    $phase=[string](Get-PaField $status 'phase' '')
    $details=Get-PaField $status 'details'
    if(-not $v.version){$v.version=[string](Get-PaField $details 'version' '')}
    $marker=[IO.File]::Exists($script:PaMarker)
    if($phase -eq 'installed'){
        $matches=$false;try{$matches=$v.version -and (Get-PaCurrent) -ceq $v.version}catch{}
        if(-not $marker -and $matches){$v.heading='SUCCESS';$v.detail='Update installed and verified. YOU CAN START GTA NOW.';$v.percent=100;$v.terminal=$true;$v.safe=$true;return $v}
        $v.heading='FINISHING SAFELY';$v.detail='Waiting for the installation safety gate to be released.'
        # Older workers wrote their receipt just before removing the gate. Give
        # them time to finish, then report interruption instead of waiting forever.
        $stamp=[DateTime]::MinValue
        if([DateTime]::TryParse([string](Get-PaField $status 'utc' ''),[ref]$stamp) -and ([DateTime]::UtcNow-$stamp.ToUniversalTime()).TotalSeconds -gt 15){
            $v.heading='UPDATE INTERRUPTED';$v.detail='Keep GTA closed. Open PA recovery before using the game.';$v.terminal=$true;$v.tone='red'
        }
        return $v
    }
    $journal=Read-PaSharedJson (Join-Path $script:PaJob 'journal.json')
    if($journal -and ((Get-PaField $journal 'product') -cne 'police-assistant-2026' -or (Get-PaField $journal 'job') -cne [IO.Path]::GetFileName($script:PaJob) -or (Get-PaField $journal 'moonloader') -ine $script:PaML)){throw 'progress_journal_owner_mismatch'}
    # A durable commit also proves success if only the final receipt failed.
    if(-not $marker -and $journal -and (Get-PaField $journal 'phase') -eq 'committed'){
        $coherent=$false;try{$coherent=(Get-PaField $journal 'version' '') -ceq (Get-PaCurrent)}catch{}
        foreach($row in @(Get-PaField $journal 'plan')){
            try{if(-not (Test-PaOwned $row.path) -and $row.path -cne 'cef/assets/hud/index.html'){$coherent=$false;break};if((Get-PaHash (Get-PaPath $script:PaGame $row.path)) -cne $row.sha256){$coherent=$false;break}}catch{$coherent=$false;break}
        }
        if($coherent -and @(Get-PaField $journal 'plan').Count -gt 0){$v.heading='SUCCESS';$v.detail='All installed files verified. YOU CAN START GTA NOW.';$v.percent=100;$v.terminal=$true;$v.safe=$true;return $v}
    }
    if($phase -eq 'current'){$v.heading='ALREADY UP TO DATE';$v.detail='No installation was needed. You can start GTA.';$v.terminal=$true;$v.safe=-not $marker;return $v}
    if($phase -in @('rolled_back','error','cancelled')){
        $v.terminal=$true;$v.tone=if($phase -eq 'error'){'red'}else{'amber'}
        $v.safe=-not $marker -and (-not $journal -or (Get-PaField $journal 'phase') -eq 'rolled_back' -or [int](Get-PaField $journal 'touched' -1) -eq 0)
        $v.heading=if($phase -eq 'rolled_back'){'PREVIOUS VERSION RESTORED'}elseif($phase -eq 'cancelled'){'UPDATE CANCELLED'}else{'UPDATE NOT INSTALLED'}
        $v.detail=if($v.safe){'Your personal data is preserved. You can start GTA and retry the update.'}else{'Keep GTA closed. The safety gate is active; recovery is required.'}
        $v.detail+='  Details: '+[string](Get-PaField $details 'cause' (Get-PaField $status 'message' 'unknown_error'));return $v
    }
    if(-not $progress){
        if($titles.ContainsKey($phase)){$v.heading=$titles[$phase]}
        $v.percent=if($phase -eq 'downloading'){15}elseif($phase -eq 'waiting'){55}else{2}
        if($journal -and (Get-PaField $journal 'phase') -eq 'applying'){
            $plan=@(Get-PaField $journal 'plan');$done=[int](Get-PaField $journal 'touched' 0)
            $v.heading='INSTALLING UPDATE';$v.percent=70+[int](23*$done/[Math]::Max(1,$plan.Count));$v.detail=('Files: '+$done+' / '+$plan.Count+'. Keep GTA closed.')
        }elseif($phase -eq 'waiting'){$v.detail='Download checked. Keep GTA closed while backups and installation are prepared.'}
    }
    if($phase -eq 'waiting' -and (Get-PaGameRunning)){
        $v.heading=if($marker){'GTA REOPENED - PLEASE CLOSE IT'}else{'CLOSE GTA TO CONTINUE'}
        $v.detail='Installation is waiting. Close GTA; this window will tell you when it is safe to return.';$v.tone='amber'
    }
    $active=Read-PaSharedJson (Join-Path $script:PaState 'active.json')
    if($active -and (Get-PaField $active 'job') -ceq [IO.Path]::GetFileName($script:PaJob)){
        $worker=Get-Process -Id ([int](Get-PaField $active 'pid' 0)) -ErrorAction SilentlyContinue
        if(-not $worker -or $worker.StartTime.ToUniversalTime().Ticks -ne (Get-PaField $active 'started')){
            $v.heading='UPDATE INTERRUPTED';$v.terminal=$true;$v.tone='red';$v.safe=-not $marker -and -not $journal
            $v.detail=if($v.safe){'Installation did not start. Your current PA is safe; start GTA and retry.'}else{'Keep GTA closed. Open PA recovery before using the game.'}
        }
    }
    return $v
}
function New-PaProgressForm {
    Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing
    if(-not ('PaUpdateWindow' -as [type])){
        Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Text.RegularExpressions;
public class PaUpdateWindow : Form {
 public Label Header,Stage,Detail,Percent,Steps,Footer; public Label[] StepRows;
 public Panel Track,Fill,Actions; public TableLayoutPanel Main,Current,Content; public Control ProgressBox;
 public Button Done; public bool Terminal,CanStartGame;public string LastStage="";int Value;
 protected override bool ShowWithoutActivation {get{return true;}}
 public static Color Ink=Color.FromArgb(221,234,234),Muted=Color.FromArgb(139,164,167),Accent=Color.FromArgb(49,220,150),Line=Color.FromArgb(35,61,67),Card=Color.FromArgb(12,27,34);
 public static Label TextLabel(string text,float size,Color color){return new Label{Text=text,Dock=DockStyle.Fill,AutoSize=false,Font=new Font("Segoe UI",size),ForeColor=color,Margin=new Padding(0),BackColor=Color.Transparent};}
 public static Panel CardPanel(){var p=new Panel{Dock=DockStyle.Fill,BackColor=Card,Margin=new Padding(0)};p.Paint+=(a,e)=>ControlPaint.DrawBorder(e.Graphics,p.ClientRectangle,Line,ButtonBorderStyle.Solid);return p;}
 public PaUpdateWindow(){
  Text="Police Assistant | Установка обновления";StartPosition=FormStartPosition.CenterScreen;ClientSize=new Size(820,520);MinimumSize=new Size(720,480);
  BackColor=Color.FromArgb(7,16,22);ForeColor=Ink;Font=new Font("Segoe UI",10);AutoScaleMode=AutoScaleMode.Dpi;MaximizeBox=false;
  Main=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(24),ColumnCount=1,RowCount=5,Margin=new Padding(0)};
  Main.RowStyles.Add(new RowStyle(SizeType.Absolute,82));Main.RowStyles.Add(new RowStyle(SizeType.Absolute,1));Main.RowStyles.Add(new RowStyle(SizeType.Percent,100));Main.RowStyles.Add(new RowStyle(SizeType.Absolute,1));Main.RowStyles.Add(new RowStyle(SizeType.Absolute,64));
  var brand=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=new Padding(0)};
  brand.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,100));brand.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
  var mark=TextLabel(" /====\\\n|  PA  |\n \\====/",13,Accent);mark.Font=new Font("Consolas",13);mark.TextAlign=ContentAlignment.MiddleLeft;
  Header=TextLabel("EXSELLENT RP\nPOLICE ASSISTANT",17,Ink);Header.Font=new Font("Segoe UI Semibold",17);Header.TextAlign=ContentAlignment.MiddleLeft;
  brand.Controls.Add(mark,0,0);brand.Controls.Add(Header,1,0);Main.Controls.Add(brand,0,0);
  Main.Controls.Add(new Panel{Dock=DockStyle.Fill,BackColor=Line,Margin=new Padding(0)},0,1);
  Content=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Padding=new Padding(0,20,0,20),Margin=new Padding(0)};
  Content.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,204));Content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
  var rail=CardPanel();rail.Margin=new Padding(0,0,16,0);var railGrid=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=4,Padding=new Padding(14),Margin=new Padding(0)};
  railGrid.RowStyles.Add(new RowStyle(SizeType.Absolute,32));for(int i=0;i<3;i++)railGrid.RowStyles.Add(new RowStyle(SizeType.Percent,33.33f));
  railGrid.Controls.Add(TextLabel("ЭТАПЫ УСТАНОВКИ",9,Muted),0,0);StepRows=new Label[3];
  string[] names={"01  Загрузка\n      и проверка","02  Резервные\n      копии","03  Установка\n      и проверка"};
  for(int i=0;i<3;i++){var cell=CardPanel();cell.Padding=new Padding(8);cell.Margin=new Padding(0,0,0,6);StepRows[i]=TextLabel(names[i],10,Muted);cell.Controls.Add(StepRows[i]);railGrid.Controls.Add(cell,0,i+1);}rail.Controls.Add(railGrid);Content.Controls.Add(rail,0,0);
  var body=CardPanel();Current=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=5,Padding=new Padding(20,16,20,12),Margin=new Padding(0)};Current.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
  foreach(int h in new int[]{58,1,74,48,64})Current.RowStyles.Add(new RowStyle(SizeType.Absolute,h));
  Stage=TextLabel("ПОДГОТОВКА",17,Accent);Stage.Font=new Font("Segoe UI Semibold",17);
  Detail=TextLabel("Подготавливаю сведения об установке…",10,Ink);Detail.Padding=new Padding(0,12,0,0);
  Footer=TextLabel("Дождитесь завершения установки",11,Muted);Footer.Padding=new Padding(0,12,0,0);
  Current.Controls.Add(Stage,0,0);Current.Controls.Add(new Panel{Dock=DockStyle.Fill,BackColor=Line,Margin=new Padding(0)},0,1);Current.Controls.Add(Detail,0,2);
  var progress=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=new Padding(0)};progress.RowStyles.Add(new RowStyle(SizeType.Percent,100));ProgressBox=progress;
  progress.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));progress.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,65));
  Track=new Panel{Dock=DockStyle.Fill,BackColor=Color.FromArgb(29,49,55),Margin=new Padding(0,12,12,10)};Fill=new Panel{Dock=DockStyle.Left,Width=0,BackColor=Accent};Track.Controls.Add(Fill);
  Percent=TextLabel("0%",12,Ink);Percent.Font=new Font("Consolas",12);Percent.TextAlign=ContentAlignment.MiddleRight;progress.Controls.Add(Track,0,0);progress.Controls.Add(Percent,1,0);
  Current.Controls.Add(progress,0,3);Current.Controls.Add(Footer,0,4);body.Controls.Add(Current);Content.Controls.Add(body,1,0);Main.Controls.Add(Content,0,2);
  Main.Controls.Add(new Panel{Dock=DockStyle.Fill,BackColor=Line,Margin=new Padding(0)},0,3);
  Actions=new Panel{Dock=DockStyle.Fill,Padding=new Padding(0,14,0,0),Margin=new Padding(0)};
  Steps=TextLabel("Личные данные сохраняются",9,Muted);Steps.Dock=DockStyle.Left;Steps.Width=320;Steps.TextAlign=ContentAlignment.MiddleLeft;
  Done=new Button{Text="Закрыть",Dock=DockStyle.Right,Width=132,Enabled=false,FlatStyle=FlatStyle.Flat,BackColor=Card,ForeColor=Ink,Font=new Font("Segoe UI",10)};Done.FlatAppearance.BorderColor=Line;Done.Click+=(a,e)=>Close();
  Actions.Controls.Add(Steps);Actions.Controls.Add(Done);Main.Controls.Add(Actions,0,4);Controls.Add(Main);
  Track.SizeChanged+=(a,e)=>Fill.Width=(int)(Track.ClientSize.Width*Math.Max(0,Math.Min(100,Value))/100.0);
 }
 static readonly Dictionary<string,string> Words=new Dictionary<string,string> {
 {"STARTING","ПОДГОТОВКА"},{"CHECKING RELEASE","ПРОВЕРКА НОВОЙ ВЕРСИИ"},{"DOWNLOADING UPDATE","ЗАГРУЗКА ОБНОВЛЕНИЯ"},
 {"VERIFYING DOWNLOAD","ПРОВЕРКА ЗАГРУЗКИ"},{"CLOSE GTA TO CONTINUE","ЗАКРОЙТЕ GTA ДЛЯ УСТАНОВКИ"},
 {"BACKING UP YOUR DATA","СОХРАНЕНИЕ РЕЗЕРВНЫХ КОПИЙ"},{"INSTALLING UPDATE","УСТАНОВКА PA"},
 {"VERIFYING INSTALLATION","ПРОВЕРКА УСТАНОВЛЕННЫХ ФАЙЛОВ"},{"FINISHING SAFELY","ЗАВЕРШЕНИЕ УСТАНОВКИ"},
 {"GTA REOPENED - PLEASE CLOSE IT","GTA ЗАПУЩЕНА — ЗАКРОЙТЕ ИГРУ"},{"RESTORING PREVIOUS VERSION","ВОССТАНОВЛЕНИЕ ПРЕЖНЕЙ ВЕРСИИ"},
 {"RECOVERING UPDATE","ВОССТАНОВЛЕНИЕ ОБНОВЛЕНИЯ"},{"SUCCESS","ГОТОВО"},{"ALREADY UP TO DATE","УСТАНОВЛЕНА АКТУАЛЬНАЯ ВЕРСИЯ"},
 {"PREVIOUS VERSION RESTORED","ПРЕЖНЯЯ ВЕРСИЯ ВОССТАНОВЛЕНА"},{"UPDATE CANCELLED","ОБНОВЛЕНИЕ ОТМЕНЕНО"},
 {"UPDATE NOT INSTALLED","УСТАНОВКА ОСТАНОВЛЕНА"},{"UPDATE INTERRUPTED","ОБНОВЛЕНИЕ ПРЕРВАНО"},
 {"Preparing update status...","Подготавливаю сведения об установке…"},
 {"Update installed and verified. YOU CAN START GTA NOW.","Обновление установлено и проверено. Теперь можно запускать игру."},
 {"All installed files verified. YOU CAN START GTA NOW.","Все установленные файлы проверены. Теперь можно запускать игру."},
 {"Waiting for the installation safety gate to be released.","Завершаю установку. Пока не запускайте игру."},
 {"Your personal data is preserved. You can start GTA and retry the update.","Личные данные сохранены. Можно запустить игру и повторить обновление."},
 {"Keep GTA closed. The safety gate is active; recovery is required.","Не запускайте GTA: для согласованной версии PA требуется восстановление."},
 {"Installation did not start. Your current PA is safe; start GTA and retry.","Установка не началась. Прежний PA сохранён; можно запустить игру и повторить загрузку."},
 {"Keep GTA closed. Open PA recovery before using the game.","Установка прервана. Перед использованием PA нужно завершить восстановление."},
 {"No installation was needed. You can start GTA.","Новая установка не требуется. Можно запускать GTA."},
 {"Installation is waiting. Close GTA; this window will tell you when it is safe to return.","Установка ждёт закрытия GTA. После завершения здесь появится разрешение запускать игру."},
 {"Download checked. Keep GTA closed while backups and installation are prepared.","Загрузка проверена. Подготавливаю копии и установку — пока не запускайте GTA."},
 {"Checking the archive, paths and file hashes.","Проверяю архив, пути и контрольные суммы файлов."},
 {"Saving current program files and personal data.","Сохраняю прежние файлы программы и личные данные."},
 {"Checking all installed files and personal data.","Проверяю установленные файлы и сохранность личных данных."},
 {"Releasing the installation safety gate.","Завершаю установку и снимаю блокировку PA."},
 {"Installation paused. Close GTA; the update will continue safely.","Установка приостановлена. Закройте GTA — помощник продолжит работу."},
 {"Restoring the previous program files. Personal files are not overwritten.","Восстанавливаю прежние файлы PA. Личные данные не заменяются."},
 {"Recovering a previous update. Keep GTA closed.","Восстанавливаю прерванное обновление. Не запускайте GTA."},
 {"Looking for the approved release on GitHub.","Проверяю выбранную версию на GitHub."},
 {"Downloading the approved release from GitHub.","Скачиваю выбранную версию с GitHub."},
 {"Download verified. Close GTA; wait for SUCCESS before starting it again.","Загрузка проверена. Закройте GTA и дождитесь сообщения «Готово»."}
 };
 public static string Tr(string text) {
  if(Words.ContainsKey(text))return Words[text];
  if(text.Contains("  Details: ")){var a=text.Split(new string[]{"  Details: "},2,StringSplitOptions.None);return Tr(a[0])+"  Код: "+a[1];}
  if(text.StartsWith("Backup "))return "Резервные копии: "+text.Substring(7).Replace(" / "," из ");
  if(text.StartsWith("Installing "))return "Устанавливаю файл "+text.Substring(11).Replace(" / "," из ");
  if(text.StartsWith("Verified "))return "Проверено "+text.Substring(9).Replace(" / "," из ").Replace(" files."," файлов.");
  if(text.StartsWith("Received "))return "Получено "+text.Substring(9).Replace(" bytes."," байт.");
  if(text.StartsWith("Files: "))return "Файлы: "+text.Substring(7).Replace("Keep GTA closed.","Не запускайте GTA.");
  return text;
 }
 public void SetState(string stage,string detail,int percent,string tone,bool terminal,bool safe,string version){
  Terminal=terminal;CanStartGame=safe;LastStage=stage;Value=percent;Stage.Text=Tr(stage);Detail.Text=Tr(detail);Percent.Text=percent+"%";Done.Enabled=terminal;
  Color color=tone=="red"?Color.FromArgb(255,111,111):tone=="amber"?Color.FromArgb(244,193,87):Accent;Stage.ForeColor=color;Fill.BackColor=color;
  Fill.Width=(int)(Track.ClientSize.Width*Math.Max(0,Math.Min(100,percent))/100.0);
  Footer.Text=safe?"Можно запускать GTA":terminal?"Пока не запускайте GTA.\nНужно завершить восстановление.":"Не запускайте GTA\nдо завершения установки.";Footer.ForeColor=safe?Accent:Muted;
  string[] labels={"01  Загрузка\n      и проверка","02  Резервные\n      копии","03  Установка\n      и проверка"};
  int done=percent==100?3:percent>=70?2:percent>=55?1:0;
  for(int i=0;i<3;i++){StepRows[i].Text=labels[i]+(i<done?"  ✓":"");StepRows[i].ForeColor=i<=done?Accent:Muted;}
  if(version.Length>0)Text="Police Assistant "+version+" | "+Tr(stage);
 }
 protected override void OnFormClosing(FormClosingEventArgs e){if(!Terminal && e.CloseReason==CloseReason.UserClosing){e.Cancel=true;Detail.Text="Это окно можно свернуть. Дождитесь итогового сообщения перед запуском GTA.";}base.OnFormClosing(e);}
}
public sealed class PaSetupWindow : PaUpdateWindow {
 public TextBox PathBox;public Button Browse,Install;public Label Requirements;public TableLayoutPanel Selector;
 protected override bool ShowWithoutActivation {get{return false;}}
 public PaSetupWindow(){
  Text="Установка Police Assistant";ClientSize=new Size(820,620);MinimumSize=new Size(720,580);Terminal=true;
  Stage.Text="ВЫБЕРИТЕ ПАПКУ ИГРЫ";Current.RowStyles[0].Height=58;
  Current.Controls.Remove(Detail);Selector=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=3,Margin=new Padding(0),Padding=new Padding(0,10,0,0)};
  foreach(int h in new int[]{24,32,32})Selector.RowStyles.Add(new RowStyle(SizeType.Absolute,h));
  Selector.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));Selector.Controls.Add(TextLabel("GTA San Andreas или MoonLoader",9,Muted),0,0);
  PathBox=new TextBox{Dock=DockStyle.Fill,Font=new Font("Segoe UI",10),BackColor=Color.FromArgb(22,37,42),ForeColor=Ink,BorderStyle=BorderStyle.FixedSingle,Margin=new Padding(0,0,0,5)};
  Browse=new Button{Text="Выбрать папку…",Dock=DockStyle.Left,Width=155,FlatStyle=FlatStyle.Flat,BackColor=Card,ForeColor=Ink,Margin=new Padding(0)};Browse.FlatAppearance.BorderColor=Line;
  Selector.Controls.Add(PathBox,0,1);Selector.Controls.Add(Browse,0,2);Current.Controls.Add(Selector,0,2);Current.RowStyles[2].Height=114;
  ProgressBox.Visible=false;Current.Controls.Remove(ProgressBox);Requirements=TextLabel("Выберите папку игры.\nБиблиотеки будут проверены автоматически.",10,Ink);Requirements.Padding=new Padding(0,10,0,0);Current.Controls.Add(Requirements,0,3);Current.RowStyles[3].Height=94;Current.RowStyles[4].Height=82;
  Footer.Text="Настройки и бинды сохраняются.\nПеред записью создаются резервные копии.";Footer.Font=new Font("Segoe UI",9);Steps.Width=200;Steps.Text="Закройте GTA перед установкой";
  Install=new Button{Text="Установить PA",Dock=DockStyle.Right,Width=240,Enabled=false,FlatStyle=FlatStyle.Flat,BackColor=Color.FromArgb(20,92,65),ForeColor=Ink,Font=new Font("Segoe UI Semibold",10)};Install.FlatAppearance.BorderColor=Accent;
  Actions.Controls.Add(Install);Actions.Controls.SetChildIndex(Install,0);Done.Enabled=true;
  StepRows[0].Text="01  Папка игры\n      Выберите путь";StepRows[0].ForeColor=Accent;StepRows[1].Text="02  Библиотеки\n      Проверка";StepRows[2].Text="03  Установка\n      Подтверждение";
 }
 public void BeginInstallation(){
  Terminal=false;Done.Enabled=false;Install.Enabled=false;Install.Visible=false;Selector.Visible=false;Requirements.Visible=false;
  Current.Controls.Remove(Selector);Current.Controls.Remove(Requirements);Current.Controls.Add(Detail,0,2);Current.RowStyles[2].Height=74;
  Current.Controls.Add(ProgressBox,0,3);ProgressBox.Visible=true;Current.RowStyles[3].Height=48;Current.RowStyles[4].Height=64;
  SetState("INSTALLING UPDATE","Подготавливаю проверку файлов…",2,"green",false,false,"");
 }
}
'@
    }
    return (New-Object PaUpdateWindow)
}
function Show-PaProgressWindow {
    $viewLock=$null;$form=$null;$timer=$null
    try{
        try{$viewLock=[IO.File]::Open((Join-Path $script:PaJob 'progress-view.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{return}
        $form=New-PaProgressForm;$timer=New-Object Windows.Forms.Timer;$timer.Interval=400
        # Keep named helper lookup in this script, not a closure's dynamic module.
        $script:PaProgressUi=@{form=$form;ready=(Join-Path $script:PaJob 'view.ready.json')}
        $paint={
            $form=$script:PaProgressUi.form
            try{$v=Get-PaProgressView;$form.SetState($v.heading,$v.detail,$v.percent,$v.tone,$v.terminal,$v.safe,$v.version)}
            catch{$form.Detail.Text='Читаю сведения об установке. Пока не запускайте GTA.'}
        }
        $form.Add_Shown({try{[IO.File]::WriteAllText($script:PaProgressUi.ready,('{"pid":'+$PID+'}'))}catch{}})
        $timer.Add_Tick($paint);&$paint;$timer.Start();[Windows.Forms.Application]::Run($form)
    }finally{if($timer){$timer.Stop();$timer.Dispose()};if($form){$form.Dispose()};if($viewLock){$viewLock.Dispose()};$script:PaProgressUi=$null}
}
function Start-PaProgressWindow {
    if(-not $script:PaPresentation){return}
    try{
        $exe=Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell/v1.0/powershell.exe'
        $quote={param([string]$s)'"'+[regex]::Replace([regex]::Replace($s,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}
        $arguments='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File '+(&$quote $script:PaWorkerPath)+' -Mode Progress -MoonLoader '+(&$quote $script:PaML)+' -JobRoot '+(&$quote $script:PaJob)
        $script:PaViewProcess=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    }catch{$script:PaViewProcess=$null}
}
function Wait-PaInstallationClosed {
    if(Get-PaGameRunning){
        Set-PaProgress 'paused' $script:PaProgressPercent 'Installation paused. Close GTA; the update will continue safely.'
        Set-PaStatus 'waiting' 'close_game_to_continue';Wait-PaClosed $false
    }
    Assert-PaClosed
}
function Complete-PaPresentation {
    if(-not $script:PaPresentation -or -not $script:PaJob){return}
    $ready=Join-Path $script:PaJob 'view.ready.json';$until=[DateTime]::UtcNow.AddSeconds(8)
    while(-not [IO.File]::Exists($ready) -and $script:PaViewProcess -and -not $script:PaViewProcess.HasExited -and [DateTime]::UtcNow -lt $until){Start-Sleep -Milliseconds 100}
    if(-not [IO.File]::Exists($ready)){
        # A native final receipt is the fallback if Windows cannot open the viewer.
        try{$unused=New-PaProgressForm;$unused.Dispose();$v=Get-PaProgressView;[Windows.Forms.MessageBox]::Show(([PaUpdateWindow]::Tr($v.heading)+"`n`n"+[PaUpdateWindow]::Tr($v.detail)),'Обновление Police Assistant')|Out-Null}catch{}
    }
}
function Copy-PaVerified([string]$from,[string]$to,[string]$expected) {
    Assert-PaPlain $from;Assert-PaPlain $to
    if((Get-PaHash $from) -ne $expected){throw 'source_hash_changed'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))|Out-Null
    $inputStream=$null;$outputStream=$null
    try {
        $inputStream=[IO.File]::OpenRead($from)
        $outputStream=New-Object IO.FileStream($to,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
        $inputStream.CopyTo($outputStream);$outputStream.Flush($true)
    }finally{if($inputStream){$inputStream.Dispose()};if($outputStream){$outputStream.Dispose()}}
    if((Get-PaHash $to) -ne $expected){throw 'backup_hash_mismatch'}
}
function Get-PaRuntimeBackup($journal,$row) {
    # Existing journals keep their original mirrored paths. New backups use
    # short indexed names; the journal preserves the complete source mapping.
    $layout=[string](Get-PaField $journal 'backup_layout' '')
    if(-not $layout){return Get-PaPath $journal.backup ('runtime/'+$row.path)}
    if($layout -cne 'flat-v1'){throw 'unsafe_journal'}
    $relative=[string](Get-PaField $row 'backup_file' '')
    if($relative -cnotmatch '^runtime/[0-9]{4}\.bin$'){throw 'unsafe_journal'}
    return Get-PaPath $journal.backup $relative
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
    Assert-PaPlain $script:PaState;if($Mode -ne 'Progress'){[IO.Directory]::CreateDirectory($script:PaState)|Out-Null}
    $script:PaMarker=Join-Path $script:PaML 'pa26-update.pending'
}
function Set-PaStatus([string]$phase,[string]$message,$details=$null) {
    $value=[ordered]@{product='police-assistant-2026';phase=$phase;message=$message;job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;utc=[DateTime]::UtcNow.ToString('o')}
    if($details){$value.details=$details}
    Write-PaJson (Join-Path $script:PaJob 'status.json') $value
    $active=Join-Path $script:PaState 'active.json'
    if($phase -in @('installed','rolled_back','error','cancelled','current')){
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
                    if($out){$pct=if($response.ContentLength -gt 0){10+[int](30*$count/$response.ContentLength)}else{15};Set-PaProgress 'downloading' $pct ('Received '+$count+' bytes.')}
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
    Set-PaProgress 'verifying_package' 42 'Checking the archive, paths and file hashes.'
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
    $verified=0
    foreach($row in $m.files) {
        if(-not (Test-PaOwned $row.path) -or -not $files.Add($row.path) -or $row.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'unsafe_manifest'}
        $p=Get-PaPath $folder $row.path
        if((Get-Item -LiteralPath $p).Length -ne $row.size -or (Get-PaHash $p) -ne $row.sha256){throw 'payload_hash_mismatch'}
        $verified++;Set-PaProgress 'verifying_package' (42+[int](13*$verified/$m.files.Count)) ('Verified '+$verified+' / '+$m.files.Count+' files.')
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
    Set-PaProgress 'rollback' $script:PaProgressPercent 'Restoring the previous program files. Personal files are not overwritten.'
    foreach($row in @($journal.plan|Select-Object -First $journal.touched|Sort-Object order -Descending)) {
        if(-not (Test-PaOwned $row.path) -and $row.path -cne 'cef/assets/hud/index.html'){throw 'unsafe_journal'}
        Wait-PaInstallationClosed;$target=Get-PaPath $script:PaGame $row.path
        $actual=if([IO.File]::Exists($target)){Get-PaHash $target}else{''}
        if($row.existed -and $actual -eq $row.before){continue}
        if($actual -and $actual -ne $row.sha256){throw 'runtime_changed_during_recovery'}
        if($row.existed){
            $backup=Get-PaRuntimeBackup $journal $row
            if((Get-PaHash $backup) -ne $row.before){throw 'damaged_backup'}
            $temp=$target+'.pa26-restore-'+[guid]::NewGuid().ToString('N');Copy-PaVerified $backup $temp $row.before;Wait-PaInstallationClosed
            if([IO.File]::Exists($target)){[IO.File]::Replace($temp,$target,[NullString]::Value)}else{[IO.File]::Move($temp,$target)}
        }elseif([IO.File]::Exists($target)){[IO.File]::Delete($target)}
    }
    $journal.phase='rolled_back';Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
    Wait-PaInstallationClosed;Assert-PaMarkerOwner $journal.job;[IO.File]::Delete($script:PaMarker)
    Set-PaStatus 'rolled_back' 'update_rolled_back' @{backup=$journal.backup}
}
function Invoke-PaTransaction([string]$folder,$m,[bool]$WaitForGame=$false) {
    if($WaitForGame){Wait-PaInstallationClosed}else{Assert-PaClosed}
    if([IO.File]::Exists($script:PaMarker)){throw 'recovery_required'}
    if((Compare-PaVersion $m.version (Get-PaCurrent)) -le 0){throw 'version_changed'}
    $plan=@(Get-PaPlan $folder $m);$personal=@(Get-PaPersonal)
    $backup=Join-Path $script:PaState ('backups\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[IO.Path]::GetFileName($script:PaJob));Assert-PaPlain $backup
    $totalBackup=$plan.Count+$personal.Count;$backed=0
    Set-PaProgress 'backup' 55 'Saving current program files and personal data.'
    $order=0;foreach($row in $plan) {
        Wait-PaInstallationClosed
        $target=Get-PaPath $script:PaGame $row.path;$row.order=$order;$order++;$row.existed=[IO.File]::Exists($target);$row.before=''
        $row.backup_file='runtime/'+$row.order.ToString('D4')+'.bin'
        if($row.existed){$row.before=Get-PaHash $target;Copy-PaVerified $target (Get-PaPath $backup $row.backup_file) $row.before}
        $backed++;Set-PaProgress 'backup' (55+[int](15*$backed/[Math]::Max(1,$totalBackup))) ('Backup '+$backed+' / '+$totalBackup)
    }
    $personalIndex=0
    foreach($row in $personal){
        Wait-PaInstallationClosed
        $row.backup_file='personal/'+$personalIndex.ToString('D6')+'.bin';$personalIndex++
        Copy-PaVerified (Get-PaLocalPath $script:PaGame $row.path) (Get-PaPath $backup $row.backup_file) $row.sha256
        $backed++;Set-PaProgress 'backup' (55+[int](15*$backed/[Math]::Max(1,$totalBackup))) ('Backup '+$backed+' / '+$totalBackup)
    }
    Assert-PaPersonal $personal
    $journal=@{product='police-assistant-2026';phase='applying';job=[IO.Path]::GetFileName($script:PaJob);moonloader=$script:PaML;
        version=$m.version;backup=$backup;backup_layout='flat-v1';personal=$personal;plan=$plan;touched=0}
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
            Wait-PaInstallationClosed;Assert-PaPersonal $personal
            Set-PaProgress 'installing' (70+[int](23*$journal.touched/[Math]::Max(1,$plan.Count))) ('Installing '+($journal.touched+1)+' / '+$plan.Count+' - '+$row.path)
            $target=Get-PaPath $script:PaGame $row.path;$temp=$target+'.pa26-new-'+$journal.job
            Copy-PaVerified $row.source $temp $row.sha256
            $journal.touched++;Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
            Wait-PaInstallationClosed
            if($row.existed){if((Get-PaHash $target) -ne $row.before){throw 'runtime_changed'};[IO.File]::Replace($temp,$target,[NullString]::Value)}else{[IO.File]::Move($temp,$target)}
            if($script:PaFault){&$script:PaFault $journal.touched}
        }
        Set-PaProgress 'verifying_install' 94 'Checking all installed files and personal data.'
        foreach($row in $plan){Wait-PaInstallationClosed;if((Get-PaHash (Get-PaPath $script:PaGame $row.path)) -ne $row.sha256){throw 'installed_hash_mismatch'}}
        Assert-PaPersonal $personal;$journal.phase='committed';Write-PaJson (Join-Path $script:PaJob 'journal.json') $journal
        Set-PaProgress 'finishing' 99 'Releasing the installation safety gate.'
        Wait-PaInstallationClosed;Assert-PaMarkerOwner $journal.job;[IO.File]::Delete($script:PaMarker)
    }catch {
        $failure=$_
        if($Mode -eq 'Library' -and $failure.Exception.Message -eq 'simulated_crash'){throw}
        if(Get-PaGameRunning){Set-PaStatus 'waiting' 'close_game_to_recover';Wait-PaClosed $false}
        Restore-PaTransaction $journal
        throw $failure
    }
    # SUCCESS is published only after verification and gate removal.
    Set-PaStatus 'installed' 'update_installed' @{version=$m.version;backup=$backup;personal_files=$personal.Count}
}
if($Mode -eq 'Library'){return}
$paLock=$null
try {
    if($Mode -eq 'Monitor'){
        Add-Type -AssemblyName System.Windows.Forms
        if(-not $MoonLoader){
            $picker=New-Object Windows.Forms.FolderBrowserDialog;$picker.Description='Выберите папку GTA San Andreas или её папку MoonLoader';$picker.ShowNewFolderButton=$false
            $defaultGame=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher/game'
            if(Test-Path -LiteralPath $defaultGame){$picker.SelectedPath=$defaultGame}
            try{if($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){exit 0};$MoonLoader=$picker.SelectedPath}finally{$picker.Dispose()}
        }
        $MoonLoader=[IO.Path]::GetFullPath($MoonLoader).TrimEnd('\');Assert-PaPlain $MoonLoader
        if([IO.Path]::GetFileName($MoonLoader) -ine 'MoonLoader'){$MoonLoader=Join-Path $MoonLoader 'MoonLoader'}
        $monitorState=Join-Path $script:PaBase ('games/'+(Get-PaKey $MoonLoader));Assert-PaPlain $monitorState
        $record=Read-PaSharedJson (Join-Path $monitorState 'active.json');if(-not $record){$record=Read-PaSharedJson (Join-Path $monitorState 'result.json')}
        $monitorJob=[string](Get-PaField $record 'job' '')
        if(-not $record -or (Get-PaField $record 'moonloader') -ine $MoonLoader -or $monitorJob -cnotmatch '^[0-9a-f]{32}$'){
            [Windows.Forms.MessageBox]::Show('Для этой игры обновление ещё не запускалось. Начните загрузку в PA и откройте это окно снова.','POLICE ASSISTANT')|Out-Null;exit 0
        }
        $JobRoot=Join-Path $script:PaBase ('jobs/'+$monitorJob);$Mode='Progress'
    }
    Initialize-PaPaths $MoonLoader $JobRoot
    if($Mode -eq 'Progress'){Show-PaProgressWindow;exit 0}
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
        $oldRequest=Read-PaSharedJson (Join-Path $script:PaJob 'request.json')
        $script:PaPresentation=(Get-PaField $oldRequest 'show_progress_window' $true) -ne $false;$script:PaTargetVersion=$journal.version
        Set-PaProgress 'recovering' 55 'Recovering a previous update. Keep GTA closed.';Start-PaProgressWindow
        Set-PaStatus 'waiting' 'close_game_to_recover';Wait-PaClosed $false
        if($journal.phase -eq 'committed'){
            foreach($row in $journal.plan){if((Get-PaHash (Get-PaPath $script:PaGame $row.path)) -ne $row.sha256){throw 'installed_hash_mismatch'}}
            Wait-PaInstallationClosed;[IO.File]::Delete($script:PaMarker);Set-PaStatus 'installed' 'update_installed' @{version=$journal.version;backup=$journal.backup}
        }else{Restore-PaTransaction $journal};exit 0
    }
    if([IO.File]::Exists($script:PaMarker)){throw 'recovery_required'}
    $request=Read-PaJson (Join-Path $script:PaJob 'request.json')
    if($request.product -cne 'police-assistant-2026' -or $request.moonloader -ine $script:PaML){throw 'invalid_request'}
    if($Mode -eq 'Prepare'){$script:PaPresentation=(Get-PaField $request 'show_progress_window' $true) -ne $false;Set-PaProgress 'checking' 2 'Looking for the approved release on GitHub.';Start-PaProgressWindow}
    Set-PaStatus 'checking' 'checking'
    $candidate=Get-PaCandidate $request
    if(-not $candidate){Set-PaStatus 'current' 'no_new_version';exit 0}
    if($Mode -eq 'Check'){Set-PaStatus 'available' 'new_version' $candidate;exit 0}
    Assert-PaApproval $request $candidate
    $script:PaTargetVersion=$candidate.version;Set-PaProgress 'downloading' 10 'Downloading the approved release from GitHub.'
    Set-PaStatus 'downloading' 'downloading' @{version=$candidate.version}
    $archive=Join-Path $script:PaJob 'package.zip'
    Get-PaRemote $candidate.url 'asset' 67108864 $request.timeout_seconds $archive
    $folder=Join-Path $script:PaJob 'package';$manifest=Expand-PaPackage $archive $folder $candidate
    Set-PaProgress 'waiting' 55 'Download verified. Close GTA; wait for SUCCESS before starting it again.'
    Set-PaStatus 'waiting' 'downloaded_close_game' @{version=$candidate.version}
    Wait-PaClosed
    Invoke-PaTransaction $folder $manifest $true
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
}finally{if($paLock){$paLock.Dispose()};Complete-PaPresentation}
