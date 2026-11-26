Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'tools/cef-contract-engine.ps1')
$registry=Get-Content -LiteralPath (Join-Path $root 'CEF_CONTRACT.json') -Raw | ConvertFrom-Json
$registry.known_versions=@();$registry.contract_profiles=@()
$folder=Join-Path $PSScriptRoot ('cef-contract-sandbox/self-repair-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($folder)|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$main=Join-Path $folder 'main.js'
$page=Join-Path $folder 'index.html'
$html='<form id="chatInput"><input id="chatInputField"><svg id="SendMsgButton"></svg></form><div id="chatMsgList"></div><div id="Dialog"></div><script src="main.js"></script>'
$js=@'
const _0x1234=_0x5678;
function _0x5678(index){const _0x2222=_0x3456();return _0x2222[index];}
function _0x3456(){const _0x3333=['AB/C','D+E','F='];return _0x3333;}
function sendMessageToChat(text){cef.emit("HandleHudSendMessage",text);return _0x1234(0);}
function addChatMessage(color,text){renderChatMessage(color,text);}
function isChatInputActive(){return chatInputElement.classList.contains("active");}
cef.on("chat:messages",addChatMessage);
'@
foreach($name in $registry.required_functions){
 if(-not $js.Contains('function '+$name+'(')){$js+="`nfunction $name(){return true;}"}
}
[IO.File]::WriteAllText($main,$js,$utf8)
[IO.File]::WriteAllText($page,$html,$utf8)
$approved=Get-PaCefContract $folder $registry -Inventory
if($approved.allowed -or $approved.reason -cne 'functional_profile_mismatch' -or -not $approved.repacked_sha256){throw 'Invalid initial fixture'}
$profile=[pscustomobject]@{
    fingerprint=$registry.interface_version+':'+$approved.sha256
    reviewed_sha256=$approved.sha256
    components=($approved.inventory|ConvertTo-Json -Compress|ConvertFrom-Json)
    repacked_sha256=$approved.repacked_sha256
}
$complete=$registry | ConvertTo-Json -Depth 20|ConvertFrom-Json
$complete.contract_profiles=@($profile)
$script:checks=0
$script:lookups=0
$script:answer=$complete
$script:outage=$false
function Get-PaPublishedCefRegistry {
    $script:lookups++
    if($script:outage){throw 'offline fixture'}
    return $script:answer
}
function Check($ok,[string]$why){$script:checks++;if(-not $ok){throw ('ASSERT: '+$why)}}
function Try-Hud([string]$Text,$Catalog,[switch]$Online,[string]$Html=$html){
    [IO.File]::WriteAllText($main,$Text,$utf8)
    [IO.File]::WriteAllText($page,$Html,$utf8)
    $hash=(Get-FileHash -LiteralPath $main).Hash
    $result=Get-PaCefContract $folder $Catalog -OnlineProfiles:$Online
    Check ((Get-FileHash -LiteralPath $main).Hash -ceq $hash) 'Checks never change the launcher'
    Check ([IO.File]::ReadAllText($page) -ceq $Html) 'Checks never write the HUD'
    return $result
}
$base=Try-Hud $js $complete -Online
Check ($base.reason -ceq 'normalized_contract_and_dom' -and $base.profile_source -ceq 'bundled') 'Bundled profile wins'
$repacked=$js.Replace("['AB/C','D+E','F=']",("["+"`n"+'"\x41" + ''B\/C'', "\u0044+E", "F=", ]'))
$equivalent=Try-Hud $repacked $complete -Online
Check ($equivalent.allowed -and $equivalent.reason -ceq 'normalized_repacked_and_dom' -and $equivalent.sha256 -cne $approved.sha256) 'Equivalent literal packing is accepted'
Check ($equivalent.runtime -ceq 'NOT_RUN' -and $equivalent.fingerprint -ceq $profile.fingerprint -and $script:lookups -eq 0) 'Local match still requires runtime confirmation and never goes online'
foreach($modified in @(
    $repacked.Replace('"F="','"Z="'),
    $repacked.Replace('"F=",','"F=","F=",'),
    $repacked.Replace('"F=",','"F=" + change(),'),
    $repacked.Replace('"F=",',('"F=", // '+[char]0x2028+' change(),')),
    $repacked.Replace('HandleHudSendMessage','ChangedPayload'),
    $repacked.Replace('chat:messages','different:event'),
    $repacked.Replace('.contains("active")','.contains("visible")')
)){
    $denied=Try-Hud $modified $complete
    Check (-not $denied.allowed -and $denied.mode -ceq 'native-only') 'Only equivalent source is admitted'
}
$invalidDom=Try-Hud $js $complete -Online -Html ($html.Replace('<svg id="SendMsgButton"></svg>','<div id="SendMsgButton"></div>'))
Check (-not $invalidDom.allowed -and $script:lookups -eq 0) 'Invalid DOM skips profile lookup'
$disabled=Try-Hud $js $registry
Check (-not $disabled.allowed -and $disabled.profile_lookup -ceq 'disabled' -and $script:lookups -eq 0) 'Opt-out stays local'
$published=Try-Hud $js $registry -Online
Check ($published.allowed -and $published.profile_source -ceq 'official' -and $published.profile_lookup -ceq 'matched' -and $script:lookups -eq 1) 'A reviewed catalog match can activate a missing local profile'
$publishedRepack=Try-Hud $repacked $registry -Online
Check ($publishedRepack.allowed -and $publishedRepack.reason -ceq 'normalized_repacked_and_dom' -and $script:lookups -eq 2) 'Same published profile admits equivalent repacking'
$different=Try-Hud ($repacked.Replace('chat:messages','different:event')) $registry -Online
Check (-not $different.allowed -and $different.profile_lookup -ceq 'no_match') 'Published data never bypasses the static contract'
$script:answer=$complete|ConvertTo-Json -Depth 20|ConvertFrom-Json
$script:answer.protocol=3
$otherProtocol=Try-Hud $js $registry -Online
Check (-not $otherProtocol.allowed -and $otherProtocol.profile_lookup -ceq 'invalid') 'Another catalog protocol cannot opt in'
$script:answer=$complete|ConvertTo-Json -Depth 20|ConvertFrom-Json
$script:answer.known_versions=@([pscustomobject]@{sha256=$approved.sha256;fingerprint=$profile.fingerprint})
$script:answer.contract_profiles=@([pscustomobject]@{fingerprint=$profile.fingerprint;components=[pscustomobject]@{};repacked_sha256=$profile.repacked_sha256})
$shortProfile=Try-Hud $js $registry -Online
Check (-not $shortProfile.allowed -and $shortProfile.profile_lookup -ceq 'no_match') 'Remote identity and incomplete inventory cannot activate CEF'
$script:outage=$true
$offline=Try-Hud $js $registry -Online
Check (-not $offline.allowed -and $offline.profile_lookup -ceq 'unavailable' -and $offline.mode -ceq 'native-only') 'Network failure leaves native chat available'
Write-Output ('CEF 0.46.3 repacking and published profiles: '+$checks+' checks passed')
