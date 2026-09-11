$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

foreach ($path in @('.env.example', 'tools/Publish-ModIo.ps1', 'tools/modio-common.ps1', 'tools/Get-NextModIoVersion.ps1')) {
    if (-not (Test-Path (Join-Path $root $path))) { throw "Missing project file: $path" }
}
if ((Get-Content -Raw (Join-Path $root '.gitignore')) -notmatch '(?m)^\.env$') { throw '.env is not ignored by Git.' }

$envPath = Join-Path $root '.env'
if (Test-Path -LiteralPath $envPath) {
    $envText = Get-Content -Raw -LiteralPath $envPath
    foreach ($key in @('MODIO_API_PATH', 'MODIO_API_KEY', 'MODIO_USER_ID', 'MODIO_CLIENT_NAME', 'MODIO_CLIENT_ID', 'MODIO_GAME_ID', 'MODIO_MOD_ID')) {
        if ($envText -notmatch "(?m)^$key=.+$") { throw "Missing non-empty .env key: $key" }
    }
}

Write-Output 'PASS: local mod.io toolchain is present.'
