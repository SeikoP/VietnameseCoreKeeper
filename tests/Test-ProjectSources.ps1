$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$required = @(
    'ModManifest.json',
    'README.md',
    'Localization/Localization.csv',
    'Scripts/VietnameseFontFix.cs',
    'tools/Package.ps1'
)
foreach ($path in $required) {
    $file = Get-Item -LiteralPath (Join-Path $root $path) -ErrorAction SilentlyContinue
    if (-not $file -or $file.Length -eq 0) { throw "Missing project source: $path" }
}

$manifest = Get-Content -Raw (Join-Path $root 'ModManifest.json') | ConvertFrom-Json
if ('Localization/Localization.csv' -notin @($manifest.files.path)) { throw 'Manifest does not declare localization.' }
if ('Scripts/VietnameseFontFix.cs' -notin @($manifest.files.path)) { throw 'Manifest does not declare font fix.' }
$rows = Import-Csv -Delimiter "`t" -LiteralPath (Join-Path $root 'Localization/Localization.csv')
if ($rows.Count -lt 8000) { throw "Localization source is unexpectedly small: $($rows.Count) rows." }
$keys = @($rows.Key)
foreach ($key in @(
    'PlacementPlus/PlacementPlus',
    'PlacementPlus_PlacementPlus/General',
    'PlacementPlus_PlacementPlus/General/MaxBrushSize',
    'PlacementPlus_PlacementPlus/General/ExcludeItems',
    'PlacementPlus_PlacementPlus/General/MinHoldTime'
)) {
    if ($key -notin $keys) { throw "Missing Placement Plus localization key: $key" }
}
if ((Get-Content -Raw (Join-Path $root 'Scripts/VietnameseFontFix.cs')) -notmatch 'AddGlyphs') { throw 'Font fix source is not the expected script.' }

# Every runtime script must be declared in the manifest, and every declared file
# must exist. Core Keeper compiles all declared scripts into one assembly, so a
# script that ships but is not declared silently never runs, while a declared
# script that is missing breaks the whole assembly. This check is generic, so it
# covers future Scripts\*.cs without being updated.
$declared = @($manifest.files.path)
$scriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'Scripts') -Filter '*.cs' -File |
    ForEach-Object { "Scripts/$($_.Name)" })
if ($scriptFiles.Count -eq 0) { throw 'No runtime scripts found in Scripts.' }
foreach ($script in $scriptFiles) {
    if ($script -notin $declared) { throw "Script is present but not declared in ModManifest.json: $script" }
}
foreach ($path in $declared) {
    $file = Get-Item -LiteralPath (Join-Path $root $path) -ErrorAction SilentlyContinue
    if (-not $file -or $file.Length -eq 0) { throw "ModManifest.json declares a missing or empty file: $path" }
}

Write-Output "PASS: project sources are present ($($rows.Count) localization rows, $($scriptFiles.Count) script(s) declared)."
