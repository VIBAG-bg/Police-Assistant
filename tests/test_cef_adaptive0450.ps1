Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'tools/cef-contract-engine.ps1')
$registry=Get-Content -LiteralPath (Join-Path $root 'CEF_CONTRACT.json') -Raw|ConvertFrom-Json
$source='C:\Users\35987\AppData\Local\Exsellent Launcher\game\cef\assets\hud'
$main=[IO.File]::ReadAllText((Join-Path $source 'main.js'))
$tag='<!-- PA26 CEF chat adapter --><script src="pa26-chat.js"></script>'
$html=[IO.File]::ReadAllText((Join-Path $source 'index.html')).Replace($tag,'')
$box=Join-Path $root ('tests/cef-contract-sandbox/adaptive-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($box)|Out-Null
$checks=0;$rows=@()
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
function Case([string]$name,[string]$js,[string]$markup,[bool]$allowed){
 [IO.File]::WriteAllText((Join-Path $box 'main.js'),$js,(New-Object Text.UTF8Encoding($false)))
 [IO.File]::WriteAllText((Join-Path $box 'index.html'),$markup,(New-Object Text.UTF8Encoding($false)))
 $hash=(Get-FileHash -LiteralPath (Join-Path $box 'main.js') -Algorithm SHA256).Hash
 $clock=[Diagnostics.Stopwatch]::StartNew();$r=Get-PaCefContract $box $registry;$clock.Stop()
 Check ($r.allowed -eq $allowed) ($name+': '+$r.reason)
 Check ((Get-FileHash -LiteralPath (Join-Path $box 'main.js') -Algorithm SHA256).Hash -eq $hash) 'Analysis never writes JS'
 $script:rows+=@{name=$name;state=$r.state;reason=$r.reason;allowed=$r.allowed;elapsed_ms=$clock.Elapsed.TotalMilliseconds;sha256=$r.sha256}
 return $r
}
$current=Case 'current_d7526' $main $html $true
Check (-not $current.known) 'Current SHA is supported by contract, not hardcoded as fully known'
Check ($current.runtime -eq 'NOT_RUN') 'Static verification does not claim runtime acceptance'
Case 'unrelated_comment' ($main+"`n// Harmless launcher maintenance release`n") $html $true|Out-Null
Case 'unrelated_whitespace' ($main.Replace('const hudContainer=',"`nconst  hudContainer = ")) $html $true|Out-Null
Case 'private_identifier_rename' ($main.Replace('_0x221766','_0xabcdef123')) $html $true|Out-Null
Case 'unrelated_function_implementation' ([regex]::Replace($main,'function formatTime\([^)]*\)\{','$0const paCosmeticRevision=1;')) $html $true|Out-Null
Case 'missing_send' ($main.Replace('function sendMessageToChat(','function incompatibleSender(')) $html $false|Out-Null
Case 'wrong_send_payload' ($main.Replace('sgfUzgXLshvKu2vUze1LC3nHz2u','rgLMzMvYzw50twvZC2fNzuv2zw50')) $html $false|Out-Null
Case 'wrong_incoming_event' ($main.Replace('y2HHDdPTzxnZywDLCW','y2HHDdP3CM9Uz3H4Ea')) $html $false|Out-Null
Case 'missing_input' $main ($html.Replace('id="chatInputField"','id="changedInputField"')) $false|Out-Null
Case 'wrong_input_type' $main ($html.Replace('<input class="chat-input-text"','<textarea class="chat-input-text"')) $false|Out-Null
Case 'duplicate_input' $main ($html.Replace('</body>','<input id="chatInputField"></body>')) $false|Out-Null
Case 'disabled_input' $main ($html.Replace('id="chatInputField"','disabled id="chatInputField"')) $false|Out-Null
Case 'async_handler' $main ($html.Replace('<script src="main.js">','<script async src="main.js">')) $false|Out-Null
Case 'extra_script' $main ($html.Replace('</body>','<script src="other.js"></script></body>')) $false|Out-Null
Case 'names_only_not_a_contract' 'function sendMessageToChat(x){cef.emit("HandleHudSendMessage",x)}' $html $false|Out-Null
Case 'unexecuted_launcher_payload' ($main+"`nthrow new Error('INSTALLER_MUST_NEVER_EXECUTE_ME');") $html $false|Out-Null
$knownFixture=$registry|ConvertTo-Json -Depth 30|ConvertFrom-Json
$knownFixture.known_versions[0].sha256=$current.sha256
$saved=$registry;$registry=$knownFixture
$known=Case 'known_registry_path_fixture' $main $html $true
Check $known.known 'Known registry takes reviewed identity path'
$registry=$saved
$missing=Get-PaCefContract (Join-Path $box 'missing') $registry
Check ($missing.state -eq 'UNAVAILABLE' -and -not $missing.allowed) 'Missing launcher is unavailable'
Check ((Get-FileHash -LiteralPath (Join-Path $source 'main.js') -Algorithm SHA256).Hash.ToLowerInvariant() -eq $current.sha256) 'Live source read-only'
$report=@{status='passed';checks=$checks;cases=$rows;game_started=$false;live_game_written=$false;old_reviewed_launcher='BLOCKED_SOURCE_NOT_AVAILABLE';environment='Windows PowerShell 5.1 / .NET CSharp verifier; local files read-only'}
$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'CEF_ADAPTIVE_STATIC0450.json') -Encoding UTF8
Write-Output ('Adaptive static contract checks: '+$checks)
