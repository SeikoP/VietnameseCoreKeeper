$ErrorActionPreference = 'Stop'

# Runtime verification of the Vietnamese font fix against the live Core Keeper log.
# Every check below maps to a distinct way the mod can silently break on a game
# update, so a new failure mode shows up here instead of as blank boxes in-game.

$log = Join-Path $env:USERPROFILE 'AppData\LocalLow\Pugstorm\Core Keeper\Player.log'
if (-not (Test-Path -LiteralPath $log)) {
    throw "Player.log not found: $log"
}
$content = Get-Content -Raw -LiteralPath $log
$problems = [System.Collections.Generic.List[string]]::new()

function Assert-Clean([string]$label, [string]$pattern) {
    $hits = @([regex]::Matches($content, $pattern))
    if ($hits.Count -gt 0) {
        $sample = ([regex]::Match($content, $pattern)).Value.Trim()
        $problems.Add("$label ($($hits.Count) occurrence(s), e.g. `"$sample`")")
    }
}

# 1. The mod must be accepted by the loader. This is the check that silently broke
#    on 1.3: a stale mod.io "Game Version" tag makes the game skip the mod entirely,
#    so no script is compiled and no glyph is ever installed.
if ($content -match 'mod Vietnamese Core Keeper is not compatible with current version') {
    $problems.Add('The mod.io "Game Version" tag does not match the running game version.')
}
if ($content -match 'not loading incompatible mod VietnameseCoreKeeper') {
    $problems.Add('The loader skipped VietnameseCoreKeeper as incompatible.')
}
if ($content -match 'failed to load mod VietnameseCoreKeeper') {
    $problems.Add('The loader failed to load VietnameseCoreKeeper.')
}
Assert-Clean 'VietnameseCoreKeeper load error' 'failed to load mod VietnameseCoreKeeper[^\r\n]*'

# 2. The script must actually compile.
if ($content -notmatch '(?i)loaded mod[^\r\n]*Vietnamese') {
    $problems.Add('No "loaded mod" line for VietnameseCoreKeeper; the mod was never loaded.')
}
Assert-Clean 'Script compile failure' '(?i)CompileFailed'

# 3. Harmony must be able to patch TextManager.Init2.
Assert-Clean 'Harmony patch failure' '(?i)(HarmonyException|Unable to patch|PatchFailed|Patching .* failed|Could not find method .Init2|Could not find target method)'

# 4. The glyph installation itself must have run and succeeded.
$install = [regex]::Match($content, '\[VietnameseFontFix\] Installed (\d+) native-matched Vietnamese glyphs')
if (-not $install.Success) {
    $problems.Add('VietnameseFontFix never logged a successful glyph installation.')
} elseif ([int]$install.Groups[1].Value -le 0) {
    $problems.Add("VietnameseFontFix installed 0 glyphs.")
}
if ($content -match '\[VietnameseFontFix\] Install failed') {
    $problems.Add('VietnameseFontFix reported an installation failure.')
}
if ($content -notmatch '\[VietnameseFontFix\] Verified native-matched glyph') {
    $problems.Add("VietnameseFontFix did not verify a visible 'ị' glyph.")
}

# 5. No Vietnamese code points may be missing once the glyphs are installed.
Assert-Clean 'Missing Vietnamese glyph' 'missing glyph u(1ea[0-9a-f]|1eb[0-9a-f]|1ec[0-9a-f]|1ed[0-9a-f]|1ee[0-9a-f]|1ef[0-9a-f]|01a1|01af)'

if ($problems.Count -gt 0) {
    # Write-Error is terminating while ErrorActionPreference is Stop, so report
    # every problem first and throw once with the full list.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    foreach ($p in $problems) { Write-Error "Vietnamese font runtime check failed: $p" }
    $ErrorActionPreference = $previous
    throw "Vietnamese font runtime verification failed with $($problems.Count) problem(s): $($problems -join ' | ')"
}

Write-Output "PASS: VietnameseCoreKeeper loaded, VietnameseFontFix compiled, Harmony patched, $($install.Groups[1].Value) glyphs installed, no missing Vietnamese glyphs."
