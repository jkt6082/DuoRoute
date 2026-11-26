# Copies DuoRoute into your WoW Forever AddOns folder. Then /reload in game
# (new files such as images need a full game restart).
param([string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns")
if (-not (Test-Path $AddOns)) { Write-Error "AddOns folder not found: $AddOns"; exit 1 }
$dest = Join-Path $AddOns "DuoRoute"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot "DuoRoute\*") -Destination $dest -Recurse -Force
Write-Host "Installed DuoRoute -> $dest"
