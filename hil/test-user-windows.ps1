[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$CaptureDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\UserWindows")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Sketch = Join-Path $RepoRoot "examples\UserWindows"
$CaptureScript = Join-Path $PSScriptRoot "capture-vfd.ps1"
$BuildPath = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-ArduinoBuild\user-windows"
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

$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null

$InitialImage = Join-Path $CaptureDirectory "user-windows-initial.jpg"
$UpdatedImage = Join-Path $CaptureDirectory "user-windows-updated.jpg"
$BaseImage = Join-Path $CaptureDirectory "user-windows-base.jpg"
$VisualExpectationsPath = Join-Path $CaptureDirectory "visual-expectations.json"

$VisualExpectations = [ordered]@{
    version = 1
    captures = @(
        [ordered]@{
            image = "user-windows-initial.jpg"
            requiredRows = @("WINDOW ONE", "WINDOW TWO")
            layout = "Exactly two separate 8-pixel text rows: WINDOW ONE on top and WINDOW TWO below."
            forbidden = @("Joined, wrapped, truncated, missing, duplicated, stale, or extra text.")
        },
        [ordered]@{
            image = "user-windows-updated.jpg"
            requiredRows = @("ONE UPDATED", "WINDOW TWO")
            layout = "Exactly two separate 8-pixel text rows: ONE UPDATED on top and unchanged WINDOW TWO below."
            forbidden = @("WINDOW ONE remaining on top; joined, wrapped, truncated, missing, duplicated, stale, or extra text.")
        },
        [ordered]@{
            image = "user-windows-base.jpg"
            requiredRows = @("BASE ACTIVE", "WINDOWS OFF")
            layout = "Exactly two separate 8-pixel text rows: BASE ACTIVE on top and WINDOWS OFF below."
            forbidden = @(
                "BASE ACTIVEWINDOWS on the first row with OFF wrapped below.",
                "Any joined, wrapped, truncated, missing, duplicated, stale, or extra text.",
                "Any prior user-window content, including WINDOW ONE, ONE UPDATED, or WINDOW TWO."
            )
        }
    )
}
$VisualExpectations | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $VisualExpectationsPath

Write-Host "=== GU7003 USER WINDOWS HIL TEST ==="
Write-Host "Repository: $RepoRoot"
Write-Host "Target:     $FQBN"
Write-Host "Port:       $Port"
Write-Host "Captures:   $CaptureDirectory"

Write-Host "[1/6] Compiling UserWindows..."
New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
& $ArduinoCli compile --fqbn $FQBN --library $RepoRoot --build-path $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "UserWindows compile FAIL." }
Write-Host "Compile PASS: UserWindows"

Write-Host "[2/6] Uploading UserWindows to $Port..."
& $ArduinoCli upload -p $Port --fqbn $FQBN --input-dir $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "UserWindows upload FAIL." }
Write-Host "Upload PASS: UserWindows"

Write-Host "[3/6] Capturing two independently populated windows..."
Start-Sleep -Seconds 5
& $CaptureScript -Image $InitialImage

Write-Host "[4/6] Capturing window 1 update with window 2 preserved..."
Start-Sleep -Seconds 15
& $CaptureScript -Image $UpdatedImage

Write-Host "[5/6] Capturing restored base window after both cancellations..."
Start-Sleep -Seconds 15
& $CaptureScript -Image $BaseImage

Write-Host "[6/6] Checking captures..."
foreach ($Image in @($InitialImage, $UpdatedImage, $BaseImage)) {
    if (-not (Test-Path -LiteralPath $Image)) {
        throw "UserWindows HIL capture FAIL: $Image was not created."
    }
}

Write-Host "UserWindows HIL capture PASS"
Write-Host "Initial: $InitialImage"
Write-Host "Updated: $UpdatedImage"
Write-Host "Base:    $BaseImage"
Write-Host "Visual expectations: $VisualExpectationsPath"
