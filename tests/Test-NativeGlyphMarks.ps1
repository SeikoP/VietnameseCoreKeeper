$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\Scripts\VietnameseFontFix.cs')
if ($source -notmatch "bool hasHorn = decomposed\.IndexOf\('\\u031B'\) >= 0;") {
    throw "The horn-aware tone placement needed by 'ữ' is missing."
}
if ($source -notmatch 'int toneX = hasHorn \? center') {
    throw "The tone mark in 'ữ' is not centered away from the horn."
}
if ($source -notmatch "if \(character == 'đ'\)[\s\S]+?bounds\[3\] - scale[\s\S]+?bounds\[2\] - scale[\s\S]+?3 \* scale") {
    throw "The crossbar in 'đ' is not three pixels wide and one pixel below the stem top."
}
if ($source -notmatch "if \(character == 'Đ'\)[\s\S]+?int y = \(bounds\[1\] \+ bounds\[3\]\) / 2;[\s\S]+?bounds\[0\] - scale[\s\S]+?3 \* scale") {
    throw "The crossbar in 'Đ' is not a three-pixel stroke at its original height across the left stem."
}
if ($source -notmatch "case '\\u0303':[\s\S]+?toneX - scale, high[\s\S]+?toneX, high[\s\S]+?toneX, top[\s\S]+?toneX \+ scale, top") {
    throw "The tilde in 'ã/ữ' is not a two-row pixel wave."
}
if ($source -notmatch "character == 't'[\s\S]+?widestRow[\s\S]+?x - scale") {
    throw "The crossbar in 't' is not shifted left by one pixel."
}
if ($source -notmatch 'int verticalPadding = 2;[\s\S]+?font\.charDims\.y \+ 2 \* verticalPadding[\s\S]+?cellY \+ verticalPadding[\s\S]+?verticalPadding \+ templateSprite\.pivot\.y') {
    throw "Vietnamese compound marks do not have two pixels of vertical padding."
}

if ($source -notmatch 'IsStructuralMark[\s\S]+?DrawStructuralMark[\s\S]+?compositeBounds = FindInkBounds[\s\S]+?DrawToneMark') {
    throw "Vietnamese marks are not composed structural-first with tone marks anchored to recomputed composite bounds."
}
if ($source -match 'private static void DrawMark\(') {
    throw "Legacy one-pass DrawMark compositor is still present."
}

Write-Output "PASS: pixel-precise crossbars/tilde and two-pass composite-aware Vietnamese mark placement are present."
