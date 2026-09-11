$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

foreach ($path in @('.env', '.env.example', 'tools/Publish-ModIo.ps1', 'docs/MODIO-PUBLISHING.md')) {
    if (-not (Test-Path (Join-Path $root $path))) { throw "Missing project file: $path" }
}

$envText = Get-Content -Raw (Join-Path $root '.env')
foreach ($key in @('MODIO_API_PATH', 'MODIO_API_KEY', 'MODIO_USER_ID', 'MODIO_CLIENT_NAME', 'MODIO_CLIENT_ID', 'MODIO_GAME_ID', 'MODIO_MOD_ID')) {
    if ($envText -notmatch "(?m)^$key=.+$") { throw "Missing non-empty .env key: $key" }
}
if ((Get-Content -Raw (Join-Path $root '.gitignore')) -notmatch '(?m)^\.env$') { throw '.env is not ignored by Git.' }

Write-Output 'PASS: local mod.io configuration and publishing guide are present.'
