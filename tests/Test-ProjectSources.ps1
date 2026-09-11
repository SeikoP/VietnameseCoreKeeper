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
if ((Get-Content -Raw (Join-Path $root 'Scripts/VietnameseFontFix.cs')) -notmatch 'AddGlyphs') { throw 'Font fix source is not the expected script.' }

Write-Output "PASS: project sources are present ($($rows.Count) localization rows)."
