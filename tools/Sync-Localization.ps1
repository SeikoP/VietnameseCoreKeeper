param(
    # Official English for Core Keeper keys, extracted from the game's own
    # localization table. Optional; when absent, sync only reports new keys.
    [string]$EnglishSource = (Join-Path $env:TEMP 'vck_english_source.tsv'),
    [switch]$Write
)

$ErrorActionPreference = 'Stop'

# Deterministic localization sync.
#
# Source of truth for upstream Core Keeper keys is the clean game/template data
# plus the official English, NOT the live game-generated Localization.csv. The live
# file is a derived, self-modifying artifact: it accumulates every key any installed
# mod has ever contributed, and keys injected by a mod persist after that mod is
# removed. It is read here for reporting only.
#
# Guarantees:
#   existing translated key -> repository bytes reused verbatim, terminator included
#   new key with English     -> emitted in game order with an empty Vietnamese cell
#   removed key              -> reported, never silently deleted
#   line terminators         -> preserved exactly as they are today

. (Join-Path $PSScriptRoot 'LocalizationTsv.ps1')

$root = Split-Path $PSScriptRoot -Parent
$repo = Join-Path $root 'Localization\Localization.csv'
$allowPath = Join-Path $root 'Localization\Known-Untranslated.txt'
$game = 'E:\SteamLibrary\steamapps\common\Core Keeper\localization\Localization.csv'

$allow = Get-LocalizationAllowlist -Path $allowPath
$english = @{}
if (Test-Path -LiteralPath $EnglishSource) {
    foreach ($line in [System.IO.File]::ReadAllLines($EnglishSource)) {
        $p = $line -split "`t", 2
        if ($p.Count -eq 2 -and -not $english.ContainsKey($p[0])) { $english[$p[0]] = $p[1] -replace '\\n', "`n" }
    }
}

$repoRecords = Read-LocalizationRecords -Path $repo
$repoData = @{}
foreach ($r in ($repoRecords | Select-Object -Skip 1)) { if (-not $repoData.ContainsKey($r.Key)) { $repoData[$r.Key] = $r } }

if (-not (Test-Path -LiteralPath $game)) { throw "Game source not found: $game" }
$gameRecords = Read-LocalizationRecords -Path $game
$gameData = $gameRecords | Select-Object -Skip 1

$newKeys = @($gameData | Where-Object { -not $repoData.ContainsKey($_.Key) -and -not $allow.ContainsKey($_.Key) })
$removed = @($repoData.Keys | Where-Object { $allow.ContainsKey($_) -eq $false -and -not (@($gameData.Key) -contains $_) } | Sort-Object)
$allowlistedPresent = @($gameData | Where-Object { $allow.ContainsKey($_.Key) -and -not $repoData.ContainsKey($_.Key) })

$newWithEnglish = @($newKeys | Where-Object { $english.ContainsKey($_.Key) })
$newWithoutEnglish = @($newKeys | Where-Object { -not $english.ContainsKey($_.Key) })

Write-Output "SYNC REPORT"
Write-Output "  repository rows              : $($repoData.Count)"
Write-Output "  game source rows             : $($gameData.Count)"
Write-Output "  new keys needing translation : $($newKeys.Count)"
Write-Output "     with official English     : $($newWithEnglish.Count)"
Write-Output "     without English source     : $($newWithoutEnglish.Count)"
Write-Output "  removed keys (reported only) : $($removed.Count)"
Write-Output "  allowlisted keys in game file: $($allowlistedPresent.Count)"

if ($newWithoutEnglish.Count -gt 0) {
    Write-Output "  --- new keys with no English source (do not invent text) ---"
    $newWithoutEnglish | Select-Object -First 20 | ForEach-Object { Write-Output "     $($_.Key)" }
    if ($newWithoutEnglish.Count -gt 20) { Write-Output "     ... $($newWithoutEnglish.Count - 20) more" }
}
if ($removed.Count -gt 0) {
    Write-Output "  --- removed keys (kept in the repository) ---"
    $removed | Select-Object -First 20 | ForEach-Object { Write-Output "     $_" }
    if ($removed.Count -gt 20) { Write-Output "     ... $($removed.Count - 20) more" }
}
if ($newWithEnglish.Count -gt 0) {
    Write-Output "  --- new keys awaiting translation ---"
    $newWithEnglish | Select-Object -First 20 | ForEach-Object { Write-Output "     $($_.Key)" }
    if ($newWithEnglish.Count -gt 20) { Write-Output "     ... $($newWithEnglish.Count - 20) more" }
}

# Regenerate the compiled-in key list from the repository CSV. This must run on every
# invocation and before any early return, because Scripts/VietnameseKeys.g.cs is the
# authoritative provenance that Scripts/LocalizationFallback.cs uses to decide which
# terms VietnameseCoreKeeper owns. tests/Test-LocalizationValidity.ps1 fails if the
# generated file ever drifts from the CSV.
function Sync-VietnameseKeys {
    $keysPath = Join-Path $root 'Localization\Localization.csv'
    $genPath = Join-Path $root 'Scripts\VietnameseKeys.g.cs'
    $keys = Get-LocalizationKeyList -Path $keysPath
    $source = New-VietnameseKeysSource -Keys $keys
    $existing = if (Test-Path -LiteralPath $genPath) { [System.IO.File]::ReadAllText($genPath) } else { $null }
    if ($existing -ceq $source) {
        Write-Output "VietnameseKeys.g.cs is up to date ($($keys.Count) keys)."
        return
    }
    if ($Write) {
        [System.IO.File]::WriteAllText($genPath, $source, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "WROTE Scripts/VietnameseKeys.g.cs ($($keys.Count) keys)."
    } else {
        Write-Output "DRIFT: Scripts/VietnameseKeys.g.cs does not match the CSV ($($keys.Count) keys). Re-run with -Write."
    }
}

if (-not $Write) {
    Write-Output "DRY RUN: nothing written. Re-run with -Write to apply."
    Sync-VietnameseKeys
    return
}

if ($newKeys.Count -eq 0) {
    Write-Output "Nothing to add. No changes written."
    Sync-VietnameseKeys
    return
}

# Emit in game order. Existing rows are re-used byte-for-byte, including their
# original terminator, so only the inserted lines show up in the diff.
$crlf = @($repoData.Values | Where-Object { $_.Term -eq "`r`n" }).Count
$lf = @($repoData.Values | Where-Object { $_.Term -eq "`n" }).Count
$newTerm = if ($crlf -ge $lf) { "`r`n" } else { "`n" }

$builder = [System.Text.StringBuilder]::new()
[void]$builder.Append($repoRecords[0].Raw)
$added = 0
foreach ($g in $gameData) {
    if ($repoData.ContainsKey($g.Key)) { [void]$builder.Append($repoData[$g.Key].Raw); continue }
    if ($allow.ContainsKey($g.Key)) { continue }
    [void]$builder.Append($g.Key + "`t" + $g.Type + "`t" + $g.Desc + "`t" + $newTerm)
    $added++
}
[System.IO.File]::WriteAllText($repo, $builder.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "WROTE $added new rows to $repo (terminator '$($newTerm -replace "`r",'\r' -replace "`n",'\n')')."
Write-Output "New rows have empty Vietnamese on purpose: Scripts/LocalizationFallback.cs supplies the original English at runtime."
Sync-VietnameseKeys
