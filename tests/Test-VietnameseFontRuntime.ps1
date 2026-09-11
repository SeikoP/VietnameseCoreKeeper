$ErrorActionPreference = 'Stop'

$log = Join-Path $env:USERPROFILE 'AppData\LocalLow\Pugstorm\Core Keeper\Player.log'
$content = Get-Content -Raw -LiteralPath $log

if ($content -notmatch '\[VietnameseFontFix\] Verified native-matched glyph ị') {
    throw "The runtime font did not verify a visible native-matched 'ị' glyph."
}
if ($content -match '\[VietnameseFontFix\] Install failed') {
    throw 'VietnameseFontFix reported an installation failure.'
}

Write-Output "PASS: native-matched Vietnamese glyph 'ị' is visible."
