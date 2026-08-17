[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$CaptureDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\BitmapNativeScroll"),
    [ValidateRange(6, 15)]
    [int]$DurationSeconds = 10
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
$Sketch = Join-Path $RepoRoot "examples\BitmapNativeScroll"
$BuildPath = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-ArduinoBuild\bitmap-native-scroll"
$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
$Video = Join-Path $CaptureDirectory "bitmap-native-scroll.mkv"
$CaptureVideoScript = Join-Path $PSScriptRoot "capture-vfd-video.ps1"
$ArduinoCli = Resolve-ArduinoCli
if (-not $ArduinoCli) { throw "arduino-cli was not found." }

New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null
$Expectations = [ordered]@{
    version = 1
    videos = @(
        [ordered]@{
            video = "bitmap-native-scroll.mkv"
            duration = [ordered]@{
                minSeconds = $DurationSeconds - 0.5
                maxSeconds = $DurationSeconds + 1.0
            }
            states = @(
                [ordered]@{
                    name = "sprite-enters-right"
                    description = "A 16-dot-tall geometric sprite emerges progressively from the right edge; it is not composed of font glyphs or text rows."
                    minOccurrences = 2
                },
                [ordered]@{
                    name = "sprite-crosses-center"
                    description = "The same asymmetric pixel sprite is intact near the center of the 112x16 window."
                    minOccurrences = 2
                },
                [ordered]@{
                    name = "sprite-exits-left"
                    description = "The sprite leaves progressively through the left edge and the window returns fully blank."
                    minOccurrences = 2
                }
            )
            cadence = [ordered]@{
                mode = "none"
                states = @()
                expectedStateSeconds = 0
                toleranceSeconds = 0
                minTransitions = 0
            }
            scrolling = [ordered]@{
                direction = "left"
                continuityRequired = $true
                noStaleContent = $true
            }
            keyFrames = @()
            forbidden = @(
                "Text, recognizable font glyphs, or two text rows being mistaken for the sprite.",
                "Instant appearance, software-redrawn stepping, rightward motion, a frozen partial sprite, duplicated fragments, wrapping, or stale pixels after exit."
            )
            review = [ordered]@{
                framesPerSecond = 6.0
                maxFrames = 48
            }
        }
    )
}
$Expectations | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $CaptureDirectory "video-expectations.json") -Encoding UTF8

Write-Host "=== GU7003 BITMAP NATIVE SCROLL HIL ==="
Write-Host "Repository: $RepoRoot"
Write-Host "Port:       $Port"
Write-Host "Captures:   $CaptureDirectory"

Write-Host "[1/3] Compiling only BitmapNativeScroll..."
New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
& $ArduinoCli compile --fqbn $FQBN --library $RepoRoot --build-path $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "BitmapNativeScroll compile failed." }

Write-Host "[2/3] Uploading BitmapNativeScroll to $Port..."
& $ArduinoCli upload -p $Port --fqbn $FQBN --input-dir $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "BitmapNativeScroll upload failed." }

Write-Host "[3/3] Capturing native bitmap motion with the calibrated C920 crop..."
& $CaptureVideoScript -Video $Video -DurationSeconds $DurationSeconds -FramesPerSecond 30
if ($LASTEXITCODE -ne 0) { throw "Bitmap native scroll video capture failed." }

Write-Host "Bitmap native scroll evidence capture PASS"
Write-Host "Video:        $Video"
Write-Host "Expectations: $(Join-Path $CaptureDirectory 'video-expectations.json')"
