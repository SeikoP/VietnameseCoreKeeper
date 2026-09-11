$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'modio-common.ps1')

$cfg = Get-ModIoConfig
$token = Get-ModIoToken
$uri = "$($cfg.MODIO_API_PATH.TrimEnd('/'))/games/$($cfg.MODIO_GAME_ID)/mods/$($cfg.MODIO_MOD_ID)/files?limit=100"
$json = & curl.exe --fail --silent --show-error -H "Authorization: Bearer $token" -H 'Accept: application/json' $uri
if ($LASTEXITCODE -ne 0) { throw 'mod.io files query failed.' }

$best = 0
foreach ($v in @($json | ConvertFrom-Json).data.version) {
    $m = [regex]::Match([string]$v, '^(\d+)\.(\d+)\.(\d+)$')
    if ($m.Success) {
        $score = [int]$m.Groups[1].Value * 10000 + [int]$m.Groups[2].Value * 100 + [int]$m.Groups[3].Value
        if ($score -gt $best) { $best = $score }
    }
}
if ($best -eq 0) { Write-Output '1.0.0'; exit }

$nextMajor = [math]::Floor($best / 10000)
$nextMinor = [math]::Floor(($best % 10000) / 100)
$nextPatch = ($best % 100) + 1
Write-Output "$nextMajor.$nextMinor.$nextPatch"