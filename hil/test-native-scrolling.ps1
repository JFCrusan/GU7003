[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$CaptureDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\NativeScrolling"),
    [ValidateRange(15, 30)]
    [int]$DurationSeconds = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ArduinoCli {
    $Command = Get-Command arduino-cli -ErrorAction SilentlyContinue
    if ($Command) { return $Command.Source }

    return @(
        "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Sketch = Join-Path $RepoRoot "examples\NativeScrolling"
$BuildPath = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-ArduinoBuild\native-scrolling"
$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
$Video = Join-Path $CaptureDirectory "native-scrolling.mkv"
$CaptureVideoScript = Join-Path $PSScriptRoot "capture-vfd-video.ps1"
$ArduinoCli = Resolve-ArduinoCli
if (-not $ArduinoCli) { throw "arduino-cli was not found." }

New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null
$Expectations = [ordered]@{
    version = 1
    videos = @(
        [ordered]@{
            video = "native-scrolling.mkv"
            duration = [ordered]@{ minSeconds = $DurationSeconds - 0.5; maxSeconds = $DurationSeconds + 1.0 }
            states = @(
                [ordered]@{ name = "memory-scroll"; description = "NATIVE ACTION and 512X16 MEMORY enter continuously from the hidden area at the right and travel left."; minOccurrences = 3 },
                [ordered]@{ name = "horizontal-write-scroll"; description = "HORIZONTAL NATIVE CHARACTER SCROLL advances smoothly on one row as new characters are written."; minOccurrences = 3 },
                [ordered]@{ name = "vertical-write-scroll"; description = "VERTICAL TWO moves from the bottom row to the top and VERTICAL THREE appears below it."; minOccurrences = 2 }
            )
            cadence = [ordered]@{ mode = "none"; states = @(); expectedStateSeconds = 0; toleranceSeconds = 0; minTransitions = 0 }
            scrolling = [ordered]@{ direction = "left"; continuityRequired = $true; noStaleContent = $true }
            keyFrames = @()
            forbidden = @(
                "Software-redrawn stepping, rightward motion, frozen partial characters, wrapping between rows during horizontal scrolling, or stale pixels between phases.",
                "Missing vertical row transition or hidden-memory text appearing instantly instead of entering from the right."
            )
            review = [ordered]@{ framesPerSecond = 3.0; maxFrames = 72 }
        }
    )
}
$Expectations | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $CaptureDirectory "video-expectations.json") -Encoding UTF8

Write-Host "=== GU7003 NATIVE SCROLLING HIL ==="
Write-Host "Repository: $RepoRoot"
Write-Host "Port:       $Port"
Write-Host "Captures:   $CaptureDirectory"

Write-Host "[1/3] Compiling NativeScrolling..."
New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
& $ArduinoCli compile --fqbn $FQBN --library $RepoRoot --build-path $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "NativeScrolling compile failed." }

Write-Host "[2/3] Uploading NativeScrolling to $Port..."
& $ArduinoCli upload -p $Port --fqbn $FQBN --input-dir $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "NativeScrolling upload failed." }

Write-Host "[3/3] Capturing dynamic scrolling with the calibrated C920 crop..."
& $CaptureVideoScript -Video $Video -DurationSeconds $DurationSeconds -FramesPerSecond 30
if ($LASTEXITCODE -ne 0) { throw "Native scrolling video capture failed." }

Write-Host "Native scrolling evidence capture PASS"
Write-Host "Video:        $Video"
Write-Host "Expectations: $(Join-Path $CaptureDirectory 'video-expectations.json')"
