$ErrorActionPreference = 'Stop'
$script:modioRoot = Split-Path $PSScriptRoot -Parent

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

function Get-ModIoConfig {
    $cfg = @{}
    $envFile = Join-Path $script:modioRoot '.env'
    if (Test-Path -LiteralPath $envFile) { $cfg = Read-DotEnv $envFile }
    foreach ($key in @('MODIO_API_PATH', 'MODIO_GAME_ID', 'MODIO_MOD_ID')) {
        if (-not $cfg[$key]) { $cfg[$key] = [Environment]::GetEnvironmentVariable($key) }
        if (-not $cfg[$key]) { throw "Missing config (set $key in .env or as an environment variable): $key" }
    }
    return $cfg
}

function Get-ModIoToken {
    if ($env:MODIO_OAUTH_TOKEN) { return $env:MODIO_OAUTH_TOKEN }
    $userPath = Join-Path $env:LOCALAPPDATA 'mod.io\05289\Steam705408214\user.json'
    if (-not (Test-Path -LiteralPath $userPath)) { throw 'No MODIO_OAUTH_TOKEN and no local mod.io user.json found.' }
    $user = Get-Content -Raw -LiteralPath $userPath | ConvertFrom-Json
    if (-not $user.oAuthToken) { throw "OAuth token missing: $userPath" }
    return $user.oAuthToken
}