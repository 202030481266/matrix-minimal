# Matrix Minimal - installer entry point.
# Kept ASCII-only on purpose: it must also run through "irm ... | iex".
#
#   One line:   irm https://raw.githubusercontent.com/202030481266/matrix-minimal/main/install.ps1 | iex
#   Local:      powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Optional, set before running:
#   $env:MATRIX_NAME = 'neo'          name in the prompt and the intro (asked otherwise)
#   $env:MATRIX_ROOT = 'C:\tmp\mm'    test run: write everything under this folder only
#
# The real work happens in setup.ps1, run with this same PowerShell (5.1 or 7).

$mmRepo = '202030481266/matrix-minimal'
$mmBranch = if ($env:MATRIX_BRANCH) { $env:MATRIX_BRANCH } else { 'main' }
$mmShell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

$mmLocal = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'setup.ps1' } else { $null }
if ($mmLocal -and (Test-Path $mmLocal)) {
    & $mmShell -NoProfile -ExecutionPolicy Bypass -File $mmLocal
    return
}

$mmTemp = Join-Path ([IO.Path]::GetTempPath()) ('matrix-minimal-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $mmTemp -ErrorAction Stop | Out-Null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Host "  Downloading Matrix Minimal ($mmRepo) ..." -ForegroundColor DarkGreen
    $mmZip = Join-Path $mmTemp 'matrix-minimal.zip'
    Invoke-WebRequest "https://github.com/$mmRepo/archive/refs/heads/$mmBranch.zip" -OutFile $mmZip -UseBasicParsing -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem      # no Archive module needed
    [IO.Compression.ZipFile]::ExtractToDirectory($mmZip, $mmTemp)
    $mmSetup = Get-ChildItem $mmTemp -Recurse -Filter 'setup.ps1' | Select-Object -First 1
    if (-not $mmSetup) { throw 'setup.ps1 not found in the download' }
    & $mmShell -NoProfile -ExecutionPolicy Bypass -File $mmSetup.FullName
} finally {
    Remove-Item $mmTemp -Recurse -Force -ErrorAction SilentlyContinue
}
