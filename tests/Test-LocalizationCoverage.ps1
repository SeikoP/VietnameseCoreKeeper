$ErrorActionPreference = 'Stop'

# REPORT-ONLY coverage summary. This test never fails the build.
#
# A localization file is allowed to be below 100% translated because
# Scripts/LocalizationFallback.cs resolves a missing Vietnamese value to the
# original English, and to the raw key when no original text exists. Coverage is
# therefore an editorial metric, not a correctness gate.

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\LocalizationTsv.ps1')

$root = Split-Path $PSScriptRoot -Parent
$repo = Join-Path $root 'Localization\Localization.csv'
$allowPath = Join-Path $root 'Localization\Known-Untranslated.txt'
$game = 'E:\SteamLibrary\steamapps\common\Core Keeper\localization\Localization.csv'

$allow = Get-LocalizationAllowlist -Path $allowPath
$records = Read-LocalizationRecords -Path $repo
$data = $records | Select-Object -Skip 1

$translated = 0
$sourceBlank = 0
$externalMod = 0
$blankUnlisted = 0
$known = [System.Collections.Generic.HashSet[string]]::new([string[]]@($data.Key))

foreach ($r in $data) {
    $reason = if ($allow.ContainsKey($r.Key)) { $allow[$r.Key] } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($r.Value)) { $translated++ }
    elseif ($reason -eq 'source-blank') { $sourceBlank++ }
    elseif ($reason -eq 'external-mod') { $externalMod++ }
    else { $blankUnlisted++ }
}

Write-Output "COVERAGE (report only, does not fail the build)"
Write-Output "  total rows in the CSV      : $($data.Count)"
Write-Output "  translated Vietnamese     : $translated"
Write-Output "  intentionally source-blank: $sourceBlank"
Write-Output "  known external-mod keys   : $externalMod  (original English shown at runtime)"
Write-Output "  unlisted blanks           : $blankUnlisted"
if ($data.Count -gt 0) {
    Write-Output ("  coverage                  : {0:N2}%" -f (100.0 * $translated / $data.Count))
}

# Allowlisted keys are deliberately absent from the CSV: no Vietnamese exists and
# none is invented. They are counted here so the CSV coverage figure is not
# mistaken for total project coverage.
$inRepo = @($allow.Keys | Where-Object { $known.Contains($_) }).Count
$absent = $allow.Count - $inRepo
Write-Output "  allowlist entries total   : $($allow.Count) ($inRepo present as rows, $absent deliberately not shipped)"

if (Test-Path -LiteralPath $game) {
    $gameRecords = Read-LocalizationRecords -Path $game
    $gameKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@((($gameRecords | Select-Object -Skip 1).Key)))
    $untranslated = @($gameKeys | Where-Object { -not $known.Contains($_) -and -not $allow.ContainsKey($_) } | Sort-Object)
    Write-Output "  keys in the live game file not in the repo: $($untranslated.Count)"
    if ($untranslated.Count -gt 0 -and $untranslated.Count -le 25) {
        $untranslated | ForEach-Object { Write-Output "     $_" }
    } elseif ($untranslated.Count -gt 25) {
        Write-Output "     (first 25)"
        $untranslated | Select-Object -First 25 | ForEach-Object { Write-Output "     $_" }
    }
} else {
    Write-Output "  live game file not found; key-set comparison skipped."
}

Write-Output "OK: coverage reported, not enforced."
