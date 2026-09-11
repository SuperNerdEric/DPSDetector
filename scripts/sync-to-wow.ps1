# Syncs repo addon/ folders into the live WoW AddOns directory.
# Usage:
#   powershell -File scripts/sync-to-wow.ps1
#   powershell -File scripts/sync-to-wow.ps1 -Regions us,eu

param(
  [string]$WowAddOns = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns",
  [string[]]$Regions = @("us")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$AddonSrc = Join-Path $RepoRoot "addon"

$packs = @("DPSDetector")
foreach ($region in $Regions) {
  $packs += "DPSDetector_DB_$($region.ToUpper())"
}

foreach ($name in $packs) {
  $from = Join-Path $AddonSrc $name
  $to = Join-Path $WowAddOns $name
  if (-not (Test-Path $from)) {
    throw "Missing source pack: $from"
  }
  New-Item -ItemType Directory -Force -Path $to | Out-Null
  robocopy $from $to /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
  if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed for $name (exit $LASTEXITCODE)"
  }
  Write-Host "Synced $name -> $to"
}

Write-Host "Done. /reload in WoW to pick up changes."
