[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$CaptureDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\Basic")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Sketch = Join-Path $RepoRoot "examples\Basic"
$CaptureScript = Join-Path $PSScriptRoot "capture-vfd.ps1"
$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
$Image = Join-Path $CaptureDirectory "basic.jpg"
$ArduinoCliCommand = Get-Command arduino-cli -ErrorAction SilentlyContinue
$ArduinoCli = if ($ArduinoCliCommand) { $ArduinoCliCommand.Source } else { $null }

if (-not $ArduinoCli) {
    $ArduinoCliCandidates = @(
        "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
    )

    $ArduinoCli = $ArduinoCliCandidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

if (-not $ArduinoCli) {
    throw "arduino-cli was not found. Install it or add it to PATH."
}

New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null

Write-Host "=== GU7003 BASIC HIL TEST ==="
Write-Host "Repository: $RepoRoot"
Write-Host "Target:     $FQBN"
Write-Host "Port:       $Port"
Write-Host "Captures:   $CaptureDirectory"

Write-Host "[1/4] Compiling Basic..."
& $ArduinoCli compile --fqbn $FQBN --library $RepoRoot $Sketch
if ($LASTEXITCODE -ne 0) { throw "Basic compile FAIL." }
Write-Host "Compile PASS: Basic"

Write-Host "[2/4] Uploading Basic to $Port..."
& $ArduinoCli upload -p $Port --fqbn $FQBN $Sketch
if ($LASTEXITCODE -ne 0) { throw "Basic upload FAIL." }
Write-Host "Upload PASS: Basic"

Write-Host "[3/4] Waiting for VFD startup..."
Start-Sleep -Seconds 3

Write-Host "[4/4] Capturing VFD..."
& $CaptureScript -Image $Image

if (-not (Test-Path -LiteralPath $Image)) {
    throw "Basic HIL capture FAIL: $Image was not created."
}

Write-Host "Basic HIL PASS: $Image"
