$ErrorActionPreference = 'Stop'

# BLOCKING validity gate for Localization/Localization.csv.
#
# This test answers only "is the file structurally sound and safe to ship".
# It deliberately does NOT fail on translation coverage: a partially translated
# file is functionally correct because Scripts/LocalizationFallback.cs resolves
# missing Vietnamese to the original English, and the raw key when none exists.
# Coverage is reported separately by Test-LocalizationCoverage.ps1.

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\LocalizationTsv.ps1')

$root = Split-Path $PSScriptRoot -Parent
$repo = Join-Path $root 'Localization\Localization.csv'
$allowPath = Join-Path $root 'Localization\Known-Untranslated.txt'

$problems = [System.Collections.Generic.List[string]]::new()
$allow = Get-LocalizationAllowlist -Path $allowPath
$records = Read-LocalizationRecords -Path $repo

if ($records.Count -lt 2) { throw "Localization.csv has no data rows." }
if ($records[0].Body -notmatch "^Key`tType`tDesc`t") {
    $problems.Add("Unexpected header: $($records[0].Body)")
}

$data = $records | Select-Object -Skip 1

# 1. empty key
foreach ($r in $data) {
    if ([string]::IsNullOrWhiteSpace($r.Key)) {
        $problems.Add("Empty key at line $($r.Line).")
    }
}

# 2. missing required columns / malformed TSV
foreach ($r in $data) {
    if ($r.Fields -lt 4) {
        $problems.Add("Row has $($r.Fields) field(s), expected at least 4 (Key/Type/Desc/value) at line $($r.Line): $($r.Key)")
    }
    if ([string]::IsNullOrWhiteSpace($r.Type)) {
        $problems.Add("Row has an empty Type at line $($r.Line): $($r.Key)")
    }
}

# 3. duplicate keys
$duplicates = @($data | Group-Object Key | Where-Object Count -gt 1)
foreach ($d in $duplicates) {
    $problems.Add("Duplicate key '$($d.Name)' appears $($d.Count) times.")
}

# 4. unexpected blank Vietnamese (allowlist is the only exception)
foreach ($r in $data) {
    if ([string]::IsNullOrWhiteSpace($r.Value) -and -not $allow.ContainsKey($r.Key)) {
        $problems.Add("Blank Vietnamese for '$($r.Key)' at line $($r.Line).")
    }
}

# 5. placeholder mismatch against the original English where one is known.
#    Known-Untranslated entries are exempt: they have no Vietnamese to compare.
$englishPath = Join-Path $env:TEMP 'vck_english_source.tsv'
if (Test-Path -LiteralPath $englishPath) {
    $english = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($englishPath)) {
        $p = $line -split "`t", 2
        if ($p.Count -eq 2) { $english[$p[0]] = $p[1] -replace '\\n', "`n" }
    }
    foreach ($r in $data) {
        if (-not $english.ContainsKey($r.Key)) { continue }
        if ([string]::IsNullOrWhiteSpace($r.Value)) { continue }
        $expected = [regex]::Matches($english[$r.Key], '\{?\d+\}?') | ForEach-Object { $_.Value } | Sort-Object
        $actual = [regex]::Matches($r.Value, '\{?\d+\}?') | ForEach-Object { $_.Value } | Sort-Object
        if (($expected -join ',') -ne ($actual -join ',')) {
            $problems.Add("Placeholder mismatch for '$($r.Key)': expected [$($expected -join ',')] found [$($actual -join ',')].")
        }
    }
} else {
    Write-Output "INFO: no extracted English source at $englishPath; placeholder parity check skipped."
}

# 6. encoding corruption guard
$bytes = [System.IO.File]::ReadAllBytes($repo)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $problems.Add('File has a UTF-8 BOM; the game source has none.')
}
try {
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    [void]$strict.GetString($bytes)
} catch {
    $problems.Add("File is not valid UTF-8: $($_.Exception.Message)")
}

  # Generated key list must match the CSV exactly. Scripts/LocalizationFallback.cs treats
  # membership in this list as the authoritative proof that VietnameseCoreKeeper supplies
  # a term, so a stale, extra, missing or duplicated key silently reclassifies real terms
  # at runtime. Regenerate with: .\tools\Sync-Localization.ps1 -Write
  $generatedPath = Join-Path $root 'Scripts\VietnameseKeys.g.cs'
  $manifest = Get-Content -Raw (Join-Path $root 'ModManifest.json') | ConvertFrom-Json
  $declared = @($manifest.files.path)
  if (-not (Test-Path -LiteralPath $generatedPath)) {
      $problems.Add('Scripts/VietnameseKeys.g.cs is missing. Run .\tools\Sync-Localization.ps1 -Write.')
  } else {
      $csvKeys = [System.Collections.Generic.List[string]]::new()
      foreach ($row in $data) { if ($row.Key -and $row.Key -ne 'Key') { $csvKeys.Add($row.Key) } }
      $genText = [System.IO.File]::ReadAllText($generatedPath)
      $expected = New-VietnameseKeysSource -Keys ([string[]]$csvKeys.ToArray())
      if ($genText -cne $expected) {
          # Report precisely rather than only "files differ".
          $genKeys = Get-VietnameseKeysFromSource -Path $generatedPath
          $genDupes = @($genKeys | Group-Object | Where-Object { $_.Count -gt 1 })
          if ($genDupes.Count -gt 0) { $problems.Add("Generated key list has $($genDupes.Count) duplicate key(s): $(($genDupes | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ')") }
          $missing = @($csvKeys | Where-Object { $genKeys -notcontains $_ })
          $extra = @($genKeys | Where-Object { $csvKeys -notcontains $_ })
          if ($missing.Count -gt 0) { $problems.Add("$($missing.Count) key(s) missing from the generated list: $(($missing | Select-Object -First 3) -join ', ')") }
          if ($extra.Count -gt 0) { $problems.Add("$($extra.Count) stale key(s) in the generated list: $(($extra | Select-Object -First 3) -join ', ')") }
          if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $genDupes.Count -eq 0) {
              $problems.Add('Generated key list content differs from the canonical output (formatting drift).')
          }
      }
      if ($declared -notcontains 'Scripts/VietnameseKeys.g.cs') {
          $problems.Add('ModManifest.json does not declare Scripts/VietnameseKeys.g.cs.')
      }  }

  if ($problems.Count -gt 0) {
    # Write-Error is terminating while ErrorActionPreference is Stop, so report
    # every problem first and throw once with the full list.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    foreach ($p in $problems) { Write-Error "Localization validity: $p" }
    $ErrorActionPreference = $previous
    throw "Localization validity failed with $($problems.Count) problem(s): $($problems -join ' | ')"
}

Write-Output "PASS: $($data.Count) rows, valid TSV, no empty or duplicate keys, no unexpected blanks, placeholders balanced, valid UTF-8 without BOM."
