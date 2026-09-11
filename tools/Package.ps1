param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'ModManifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$paths = @($manifest.files.path)

foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { throw "Manifest file is missing: $path" }
}
if (-not $OutputPath) { $OutputPath = Join-Path $root "releases\vietnamese-core-keeper-$Version.zip" }
$output = [IO.Path]::GetFullPath($OutputPath)
$stage = Join-Path ([IO.Path]::GetTempPath()) ('VietnameseCoreKeeper-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination $stage
    foreach ($path in $paths) {
        $destination = Join-Path $stage $path
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $destination
    }
    New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $output -CompressionLevel Optimal -Force
    Write-Output "Created $output"
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
