param(
    [string]$Version = '',
    [string]$ZipPath = '',
    [string]$Changelog = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Read-DotEnv([string]$path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^\s*(#|$)') { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) { throw "Invalid .env line: $line" }
        $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"', "'")
    }
    return $values
}

$cfg = Read-DotEnv (Join-Path $root '.env')
foreach ($key in @('MODIO_API_PATH', 'MODIO_GAME_ID', 'MODIO_MOD_ID')) {
    if (-not $cfg[$key]) { throw "Missing .env key: $key" }
}

if (-not $Version) { $Version = $cfg.MODIO_VERSION }
if (-not $Version) { throw 'Provide -Version or set MODIO_VERSION.' }
if (-not $ZipPath) { $ZipPath = Join-Path $root "releases\vietnamese-core-keeper-$Version.zip" }
$zip = Get-Item -LiteralPath $ZipPath
$userPath = Join-Path $env:LOCALAPPDATA "mod.io\05289\Steam705408214\user.json"
$user = Get-Content -Raw -LiteralPath $userPath | ConvertFrom-Json
if (-not $user.oAuthToken) { throw "OAuth token missing: $userPath" }

if (-not $Changelog) { $Changelog = "Vietnamese Core Keeper $Version update." }
$headers = @{ Authorization = "Bearer $($user.oAuthToken)"; Accept = 'application/json' }
$uri = "$($cfg.MODIO_API_PATH.TrimEnd('/'))/games/$($cfg.MODIO_GAME_ID)/mods/$($cfg.MODIO_MOD_ID)/files"
$curlArgs = @(
    '--fail', '--silent', '--show-error', '-X', 'POST',
    '-H', "Authorization: Bearer $($user.oAuthToken)",
    '-H', 'Accept: application/json',
    '-F', "filedata=@$($zip.FullName)",
    '-F', "version=$Version",
    '-F', "changelog=$Changelog",
    '-F', 'active=true',
    $uri
)
$json = & curl.exe @curlArgs
if ($LASTEXITCODE -ne 0) { throw "mod.io upload failed (curl exit $LASTEXITCODE)." }
$result = $json | ConvertFrom-Json
$result | Select-Object id, mod_id, filename, filesize, version, virus_status, virus_positive
