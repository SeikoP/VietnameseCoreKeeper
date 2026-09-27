param(
    # Where the real Core Keeper assemblies live. Overridable so the gate can be
    # pointed at a different install, and so CI can detect that they are absent.
    [string]$GameDir = 'E:\SteamLibrary\steamapps\common\Core Keeper',
    # Fail (exit 1) when the proprietary assemblies are missing. CI sets this to
    # $false and reports the limitation instead of pretending the check passed.
    [switch]$RequireAssemblies,
    # Optional extra .cs files/directories appended to Scripts\. Used by the
    # self-check to prove the gate actually fails on a broken script.
    [string[]]$AdditionalSource = @(),
    # Compile a different directory instead of Scripts\. Used by the self-check so
    # a deliberately broken copy can be compiled in isolation.
    [string]$ScriptsPath = ''
)

$ErrorActionPreference = 'Stop'

# Blocking C# compile gate for the mod's runtime scripts.
#
# Why this exists: Core Keeper compiles every mod script into ONE assembly. A single
# unresolved type anywhere makes the whole assembly fail to load, which silently
# disables VietnameseFontFix and the localization fallback at the same time. The
# only reliable defence is to compile the shipped sources against the same
# assemblies the game uses, before deploying or publishing.
#
# The mod still ships .cs source files, exactly as Core Keeper requires. The output
# here is written to a temporary directory and discarded; it is never packaged.

$root = Split-Path $PSScriptRoot -Parent
$scriptDir = if ($ScriptsPath) { $ScriptsPath } else { Join-Path $root 'Scripts' }

$managed = Join-Path $GameDir 'CoreKeeper_Data\Managed'
if (-not (Test-Path -LiteralPath $managed)) { $managed = Join-Path $GameDir 'Managed' }

function Fail([string]$message) {
    Write-Error "Compile gate: $message"
    exit 1
}

# ---- locate the compiler ----------------------------------------------------
$csc = $null
$sdk = Get-ChildItem (Join-Path $env:ProgramFiles 'dotnet\sdk') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($sdk) {
    $candidate = Join-Path $sdk.FullName 'Roslyn\bincore\csc.dll'
    if (Test-Path -LiteralPath $candidate) { $csc = @{ Kind = 'dotnet'; Path = $candidate } }
}
if (-not $csc) {
    $onPath = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($onPath) { $csc = @{ Kind = 'exe'; Path = $onPath.Source } }
}
if (-not $csc) { Fail 'no C# compiler found (expected the .NET SDK at %ProgramFiles%\dotnet\sdk or csc.exe on PATH).' }

# ---- locate the real game assemblies ---------------------------------------
if (-not (Test-Path -LiteralPath $managed)) {
    $message = "Core Keeper assemblies not found under '$GameDir'. The real compile gate cannot run here."
    if ($RequireAssemblies) { Fail $message }
    Write-Output "SKIP: $message"
    Write-Output '      This gate is blocking for local candidate deployment and for mod.io publish.'
    Write-Output "      It is NOT reproduced in GitHub CI because the game assemblies are proprietary and cannot be committed."
    exit 0
}

$references = @(
    (Join-Path $managed 'mscorlib.dll')
    (Join-Path $managed 'netstandard.dll')
    (Join-Path $managed 'System.dll')
    (Join-Path $managed 'System.Core.dll')
    (Join-Path $managed '0Harmony.dll')
)
$references += @(Get-ChildItem -LiteralPath $managed -Filter 'UnityEngine*.dll' -File | ForEach-Object { $_.FullName })
$references += @(Get-ChildItem -LiteralPath $managed -Filter 'Pug*.dll' -File | ForEach-Object { $_.FullName })
$references += @(
    (Join-Path $managed 'I2.dll')
    (Join-Path $managed 'Unity.Mathematics.dll')
)

$missing = @($references | Where-Object { -not (Test-Path -LiteralPath $_) })
$required = @('mscorlib.dll', 'netstandard.dll', '0Harmony.dll', 'I2.dll')
$missingRequired = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $managed $_)) })
if ($missingRequired.Count -gt 0) {
    $message = "required assemblies missing from '$managed': $($missingRequired -join ', ')"
    if ($RequireAssemblies) { Fail $message }
    Write-Output "SKIP: $message"
    exit 0
}

# ---- collect every runtime script ------------------------------------------
$sources = @(Get-ChildItem -LiteralPath $scriptDir -Filter '*.cs' -File | Sort-Object Name | ForEach-Object { $_.FullName })
if ($sources.Count -eq 0) { Fail "no .cs sources found in $scriptDir" }
foreach ($extra in $AdditionalSource) {
    if (Test-Path -LiteralPath $extra -PathType Container) {
        $sources += @(Get-ChildItem -LiteralPath $extra -Filter '*.cs' -File | ForEach-Object { $_.FullName })
    } elseif (Test-Path -LiteralPath $extra) {
        $sources += (Resolve-Path -LiteralPath $extra).Path
    }
}

# ---- compile ----------------------------------------------------------------
$outDir = Join-Path ([IO.Path]::GetTempPath()) ("vck-compile-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$outDll = Join-Path $outDir 'VietnameseCoreKeeper.dll'

$argList = @()
$argList += @('-nologo', '-nostdlib+', '-noconfig', '-target:library', '-langversion:9.0', '-warnaserror-', '-unsafe-')
$argList += @("-out:$outDll")
foreach ($r in ($references | Sort-Object -Unique)) { $argList += "-r:`"$r`"" }
foreach ($s in $sources) { $argList += "`"$s`"" }

Write-Output "Compile gate"
Write-Output "  compiler : $($csc.Path)"
Write-Output "  managed  : $managed"
Write-Output "  sources  : $($sources.Count)"
foreach ($s in $sources) { Write-Output "             $(Split-Path $s -Leaf)" }
Write-Output "  refs     : $((($references | Sort-Object -Unique)).Count) assemblies"

$compilerOutput = $null
$exitCode = 1
try {
    if ($csc.Kind -eq 'dotnet') {
        $all = @($csc.Path) + $argList
        $compilerOutput = & dotnet @all 2>&1 | Out-String
    } else {
        $compilerOutput = & $csc.Path @argList 2>&1 | Out-String
    }
    $exitCode = $LASTEXITCODE
} catch {
    $compilerOutput = "compiler invocation failed: $($_.Exception.Message)"
    $exitCode = 1
}

$errors = @()
$warnings = @()
foreach ($line in ($compilerOutput -split "`r?`n")) {
    if ($line -match ':\s*error\s+CS\d+') { $errors += $line.Trim() }
    elseif ($line -match ':\s*warning\s+CS\d+') { $warnings += $line.Trim() }
}

if ($exitCode -ne 0 -or $errors.Count -gt 0) {
    Write-Output "FAIL: $($errors.Count) compile error(s)"
    foreach ($e in $errors) { Write-Output "  $e" }
    if ($warnings.Count -gt 0) {
        Write-Output "  ($($warnings.Count) warning(s))"
        foreach ($w in ($warnings | Select-Object -First 5)) { Write-Output "  $w" }
    }
    Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "PASS: all $($sources.Count) runtime script(s) compile together against the real Core Keeper assemblies."
Write-Output "      Output was written to a temp directory and discarded; the mod ships .cs source only."
exit 0
