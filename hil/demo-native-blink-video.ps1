[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$CaptureDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\NativeBlinkVideo"),
    [string]$NativeBlinkWorktree = "C:\Projects\GU7003-native-blink",
    [ValidateRange(5, 15)]
    [int]$DurationSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ArduinoCli {
    $Command = Get-Command arduino-cli -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    return @(
        "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
    ) |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

$NativeBlinkWorktree = [System.IO.Path]::GetFullPath($NativeBlinkWorktree)
if (-not (Test-Path -LiteralPath $NativeBlinkWorktree -PathType Container)) {
    throw "The native-blink worktree was not found: $NativeBlinkWorktree"
}
$Branch = (& git -C $NativeBlinkWorktree branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $Branch -ne "feature/native-blink") {
    throw "Expected a registered feature/native-blink worktree at $NativeBlinkWorktree; found '$Branch'."
}
$DirtyState = @(& git -C $NativeBlinkWorktree status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $DirtyState.Count -ne 0) {
    throw "The native-blink demo requires its existing worktree to be clean; no files will be changed automatically."
}

$ArduinoCli = Resolve-ArduinoCli
if (-not $ArduinoCli) {
    throw "arduino-cli was not found. Install it or add it to PATH."
}

$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null
$Sketch = Join-Path $NativeBlinkWorktree "examples\BlinkValidation"
$BuildPath = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-ArduinoBuild\native-blink-video"
$Video = Join-Path $CaptureDirectory "native-blink.mkv"
$ExpectationsPath = Join-Path $CaptureDirectory "video-expectations.json"
$CaptureVideoScript = Join-Path $PSScriptRoot "capture-vfd-video.ps1"

$Expectations = [ordered]@{
    version = 1
    videos = @(
        [ordered]@{
            video = "native-blink.mkv"
            duration = [ordered]@{
                minSeconds = $DurationSeconds - 0.5
                maxSeconds = $DurationSeconds + 1.0
            }
            states = @(
                [ordered]@{
                    name = "blank-phase-visible"
                    description = "During BLANK 5 CYCLES, both rows BLINK TEST and BLANK 5 CYCLES are visibly present."
                    minOccurrences = 2
                },
                [ordered]@{
                    name = "blank-phase-hidden"
                    description = "During the same finite Normal/Blank phase, the display is fully blank."
                    minOccurrences = 2
                }
            )
            cadence = [ordered]@{
                mode = "alternating"
                states = @("blank-phase-visible", "blank-phase-hidden")
                expectedStateSeconds = 1.0
                toleranceSeconds = 0.35
                minTransitions = 4
            }
            scrolling = [ordered]@{
                direction = "none"
                continuityRequired = $true
                noStaleContent = $true
            }
            keyFrames = @()
            forbidden = @(
                "A partially cleared or stale BLINK TEST / BLANK 5 CYCLES row during a blank interval.",
                "Transitions in the wrong order, a frozen phase, or unexplained flashes between the visible and blank states."
            )
            review = [ordered]@{
                framesPerSecond = 2.0
                maxFrames = 36
            }
        }
    )
}
$Expectations | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ExpectationsPath -Encoding UTF8

Write-Host "=== GU7003 NATIVE BLINK VIDEO DEMO ==="
Write-Host "Source worktree: $NativeBlinkWorktree (read-only/clean)"
Write-Host "Output:          $CaptureDirectory"
Write-Host "[1/3] Compiling existing BlinkValidation example..."
New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
& $ArduinoCli compile --fqbn $FQBN --library $NativeBlinkWorktree --build-path $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "BlinkValidation compile failed." }

Write-Host "[2/3] Uploading existing BlinkValidation example to $Port..."
& $ArduinoCli upload -p $Port --fqbn $FQBN --input-dir $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "BlinkValidation upload failed." }

Write-Host "[3/3] Capturing the initial READY/Normal-Blank sequence..."
& $CaptureVideoScript -Video $Video -DurationSeconds $DurationSeconds
if ($LASTEXITCODE -ne 0) { throw "Native blink video capture failed." }

if (-not (Test-Path -LiteralPath $Video -PathType Leaf)) {
    throw "Native blink demo did not produce the expected video: $Video"
}

Write-Host "Native blink video demo capture PASS"
Write-Host "Video:        $Video"
Write-Host "Expectations: $ExpectationsPath"
Write-Host "The demo did not edit, commit, switch, reset, or clean the native-blink worktree."
