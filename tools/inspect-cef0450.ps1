param([string]$HudRoot, [switch]$Inventory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'cef-contract-engine.ps1')
$registry=Get-Content -LiteralPath (Join-Path $root 'CEF_CONTRACT.json') -Raw|ConvertFrom-Json
Get-PaCefContract $HudRoot $registry -Inventory:$Inventory|ConvertTo-Json -Depth 8
