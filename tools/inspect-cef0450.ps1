param([string]$HudRoot, [switch]$Inventory, [switch]$OnlineProfiles)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'cef-contract-engine.ps1')
$registry=Get-Content -LiteralPath (Join-Path $root 'CEF_CONTRACT.json') -Raw|ConvertFrom-Json
Get-PaCefContract $HudRoot $registry -Inventory:$Inventory -OnlineProfiles:$OnlineProfiles|ConvertTo-Json -Depth 8
