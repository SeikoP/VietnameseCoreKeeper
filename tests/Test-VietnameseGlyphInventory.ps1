$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot '..\Scripts\VietnameseFontFix.cs'
$source = Get-Content -Raw -LiteralPath $sourcePath

$match = [regex]::Match($source, '(?s)private const string Characters =\s*(?<expr>.*?);\s*\r?\n\s*private static readonly')
if (-not $match.Success) { throw 'Could not locate VietnameseFontFix.Characters.' }

$pieces = [regex]::Matches($match.Groups['expr'].Value, '"(?<s>[^"]*)"')
$characters = -join @($pieces | ForEach-Object { $_.Groups['s'].Value })
if ([string]::IsNullOrEmpty($characters)) { throw 'Characters table is empty.' }

$allowedBases = [System.Collections.Generic.HashSet[char]]::new()
foreach ($ch in 'AaEeIiOoUuYyDdTt'.ToCharArray()) { [void]$allowedBases.Add($ch) }
$allowedMarks = [System.Collections.Generic.HashSet[int]]::new()
foreach ($cp in @(0x0300,0x0301,0x0302,0x0303,0x0306,0x0309,0x031B,0x0323)) {
    [void]$allowedMarks.Add($cp)
}

$seen = [System.Collections.Generic.HashSet[char]]::new()
foreach ($ch in $characters.ToCharArray()) {
    if (-not $seen.Add($ch)) { throw "Duplicate glyph declaration: $ch (U+$([int]$ch).ToString('X4'))" }
    if ($ch -eq 'Đ' -or $ch -eq 'đ' -or $ch -eq 't') { continue }

    $d = $ch.ToString().Normalize([Text.NormalizationForm]::FormD)
    if ($d.Length -lt 1 -or -not $allowedBases.Contains($d[0])) {
        throw "Unsupported Vietnamese glyph base for $ch (U+$([int]$ch).ToString('X4')): $($d[0])"
    }
    for ($i = 1; $i -lt $d.Length; $i++) {
        $cp = [int]$d[$i]
        if (-not $allowedMarks.Contains($cp)) {
            throw "Unsupported combining mark U+$($cp.ToString('X4')) in $ch"
        }
    }
}

# Complete Vietnamese precomposed vowel/tone inventory used by modern Vietnamese,
# plus Đ/đ and the intentionally adjusted native t.
$required = (
    'ĂăÂâÊêÔôƠơƯưĐđ' +
    'ÀÁẢÃẠàáảãạÈÉẺẼẸèéẻẽẹÌÍỈĨỊìíỉĩị' +
    'ÒÓỎÕỌòóỏõọÙÚỦŨỤùúủũụỲÝỶỸỴỳýỷỹỵ' +
    'ẦẤẨẪẬầấẩẫậẰẮẲẴẶằắẳẵặ' +
    'ỀẾỂỄỆềếểễệỒỐỔỖỘồốổỗộỜỚỞỠỢờớởỡợ' +
    'ỪỨỬỮỰừứửữự'
)
foreach ($ch in $required.ToCharArray()) {
    if (-not $seen.Contains($ch)) {
        throw "Missing required Vietnamese glyph: $ch (U+$([int]$ch).ToString('X4'))"
    }
}

if ($source -notmatch 'int markScale = Math\.Max\(1, font\.charDims\.y / 18\);') {
    throw 'Glyph canvas is not scaled from the native PugFont height.'
}
if ($source -notmatch 'int verticalPadding = Math\.Max\(2, 4 \* markScale\);') {
    throw 'Glyph canvas does not reserve scale-aware room for stacked Vietnamese marks.'
}
if ($source -match "DrawToneMark[\s\S]+?case '\\u0302'|DrawToneMark[\s\S]+?case '\\u0306'|DrawToneMark[\s\S]+?case '\\u031B'") {
    throw 'Structural marks leaked into the tone pass.'
}

Write-Output "PASS: $($seen.Count) declared glyphs have supported deterministic decomposition and scale-aware stacked-mark capacity."
