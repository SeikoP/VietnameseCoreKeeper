param(
    [string]$Version = '',
    [string]$ZipPath = '',
    [string]$Changelog = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'modio-common.ps1')

$cfg = Get-ModIoConfig
$token = Get-ModIoToken

if (-not $Version) { $Version = $cfg.MODIO_VERSION }
if (-not $Version) { throw 'Provide -Version or set MODIO_VERSION.' }
if (-not $ZipPath) { $ZipPath = Join-Path $root "releases\vietnamese-core-keeper-$Version.zip" }
$zip = Get-Item -LiteralPath $ZipPath

if (-not $Changelog) { $Changelog = "Vietnamese Core Keeper $Version update." }
$uri = "$($cfg.MODIO_API_PATH.TrimEnd('/'))/games/$($cfg.MODIO_GAME_ID)/mods/$($cfg.MODIO_MOD_ID)/files"
$curlArgs = @(
    '--fail', '--silent', '--show-error', '-X', 'POST',
    '-H', "Authorization: Bearer $token",
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
