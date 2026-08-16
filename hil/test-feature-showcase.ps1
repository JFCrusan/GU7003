[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$CaptureDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\FeatureShowcase")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Sketch = Join-Path $RepoRoot "examples\FeatureShowcase"
$CaptureImageScript = Join-Path $PSScriptRoot "capture-vfd.ps1"
$CaptureVideoScript = Join-Path $PSScriptRoot "capture-vfd-video.ps1"
$BuildPath = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-ArduinoBuild\feature-showcase"

function Resolve-ArduinoCli {
    $Command = Get-Command arduino-cli -ErrorAction SilentlyContinue
    if ($Command) { return $Command.Source }

    return @(
        "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

function Wait-Until {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Clock,
        [Parameter(Mandatory = $true)]
        [double]$Seconds
    )

    $RemainingMilliseconds = [int][Math]::Ceiling(($Seconds - $Clock.Elapsed.TotalSeconds) * 1000.0)
    if ($RemainingMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $RemainingMilliseconds
    }
    elseif ($RemainingMilliseconds -lt -2500) {
        throw "Missed the $Seconds-second capture window by $([Math]::Round(-$RemainingMilliseconds / 1000.0, 2)) seconds."
    }
}

function Capture-ImageAt {
    param(
        [System.Diagnostics.Stopwatch]$Clock,
        [double]$Seconds,
        [string]$Name
    )

    Wait-Until -Clock $Clock -Seconds $Seconds
    $Path = Join-Path $CaptureDirectory $Name
    & $CaptureImageScript -Image $Path
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Static capture failed: $Name"
    }
}

function Capture-VideoAt {
    param(
        [System.Diagnostics.Stopwatch]$Clock,
        [double]$Seconds,
        [string]$Name,
        [int]$DurationSeconds
    )

    Wait-Until -Clock $Clock -Seconds $Seconds
    $Path = Join-Path $CaptureDirectory $Name
    & $CaptureVideoScript -Video $Path -DurationSeconds $DurationSeconds -FramesPerSecond 30
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Video capture failed: $Name"
    }
}

$ArduinoCli = Resolve-ArduinoCli
if (-not $ArduinoCli) {
    throw "arduino-cli was not found. Install it or add it to PATH."
}

$CaptureDirectory = [System.IO.Path]::GetFullPath($CaptureDirectory)
New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null

$VisualExpectations = [ordered]@{
    version = 1
    captures = @(
        [ordered]@{
            image = "title.jpg"
            requiredRows = @("FEATURE", "SHOWCASE")
            layout = "Exactly two centered, separate 8-pixel rows. FEATURE is centered above SHOWCASE; neither row is clipped, wrapped, joined, or touching an edge."
            forbidden = @("Any extra text, stale pixels, wrapping, clipping, reverse background, cursor, or off-center title placement.")
        },
        [ordered]@{
            image = "typography.jpg"
            requiredRows = @("1X1 SMALL", "2X1 BOLD")
            layout = "Exactly two separate rows: normal-width 1X1 SMALL on top and visibly double-width 2X1 BOLD below, with no overlap or clipping."
            forbidden = @("Same-sized rows; overlap; joined, wrapped, clipped, duplicated, stale, or extra text.")
        },
        [ordered]@{
            image = "reverse-inverted.jpg"
            requiredRows = @("REVERSE MODE", "INVERTED")
            layout = "Two clean centered rows with visibly reversed bright character cells; every character is legible and unwrapped."
            forbidden = @("Normally rendered character cells, mixed normal/reverse cells, stale brightness labels, wrapping, clipping, or extra content.")
        },
        [ordered]@{
            image = "reverse-restored.jpg"
            requiredRows = @("REVERSE MODE", "RESTORED")
            layout = "Two clean centered rows on the restored normal dark background, with no reversed pixels remaining."
            forbidden = @("INVERTED remaining, any bright reverse background, stale pixels, wrapping, clipping, or extra content.")
        },
        [ordered]@{
            image = "graphics.jpg"
            requiredRows = @("GRAPHICS", "PIXELS + ART")
            layout = "A crisp 16x16 diamond at far left, two separate text rows in the middle, and a distinct 8x8 check at far right; all elements are fully visible and separated."
            forbidden = @("Missing, malformed, clipped, or merged bitmap; overlapping text; compositing swatches; stale prior-phase content; reverse background.")
        },
        [ordered]@{
            image = "write-mixture.jpg"
            requiredRows = @("N OR AND XOR")
            layout = "One clean top label row identifying four separated 20-pixel composited swatches below it. The N, OR, AND, and XOR swatches have four visibly distinct validated stripe patterns from left to right."
            forbidden = @("Missing or identical swatches; labels touching or wrapping; any fifth swatch; graphics-scene icons; stale, reversed, or extra content.")
        },
        [ordered]@{
            image = "windows-initial.jpg"
            requiredRows = @("WINDOW ONE", "WINDOW TWO")
            layout = "Exactly two separate 8-pixel text rows: WINDOW ONE in the top user window and WINDOW TWO in the bottom user window."
            forbidden = @("Joined, wrapped, clipped, duplicated, stale, missing, or extra text.")
        },
        [ordered]@{
            image = "windows-updated.jpg"
            requiredRows = @("ONE UPDATED", "WINDOW TWO")
            layout = "Exactly two separate rows: ONE UPDATED in the independently cleared top window and unchanged WINDOW TWO below."
            forbidden = @("WINDOW ONE remaining; WINDOW TWO changed or erased; joined, wrapped, clipped, duplicated, stale, or extra text.")
        },
        [ordered]@{
            image = "windows-base.jpg"
            requiredRows = @("BASE RESTORED", "WINDOWS OFF")
            layout = "Exactly two clean base-window rows after both user windows are canceled: BASE RESTORED above WINDOWS OFF."
            forbidden = @("Any WINDOW ONE, ONE UPDATED, or WINDOW TWO content; joined rows; wrapping; clipping; reverse background; stale pixels; extra content.")
        },
        [ordered]@{
            image = "finale.jpg"
            requiredRows = @("SHOWCASE", "LOOPING...")
            layout = "Exactly two centered, separate rows forming a clean finale card on a normal dark background."
            forbidden = @("Window content, blink, reverse background, compositing marks, graphics icons, wrapping, clipping, stale pixels, or extra text.")
        },
        [ordered]@{
            image = "loop-title.jpg"
            requiredRows = @("FEATURE", "SHOWCASE")
            layout = "The next loop has returned to the exact clean centered title card: FEATURE above SHOWCASE, with all prior state absent."
            forbidden = @("LOOPING..., any finale fragment, stale window/graphics/mixture content, blink, reverse background, wrapping, clipping, or extra text.")
        }
    )
}

$VideoExpectations = [ordered]@{
    version = 1
    videos = @(
        [ordered]@{
            video = "brightness-sweep.mkv"
            duration = [ordered]@{ minSeconds = 9.5; maxSeconds = 11.0 }
            states = @(
                [ordered]@{ name = "brightness-2"; description = "Rows BRIGHTNESS and LEVEL 2 are cleanly visible at the sweep's lowest intensity."; minOccurrences = 3 },
                [ordered]@{ name = "brightness-5"; description = "Rows BRIGHTNESS and LEVEL 5 are cleanly visible at a clearly brighter middle intensity."; minOccurrences = 3 },
                [ordered]@{ name = "brightness-8"; description = "Rows BRIGHTNESS and LEVEL 8 are cleanly visible at the sweep's brightest intensity."; minOccurrences = 3 }
            )
            cadence = [ordered]@{ mode = "none"; states = @(); expectedStateSeconds = 0; toleranceSeconds = 0; minTransitions = 0 }
            scrolling = [ordered]@{ direction = "none"; continuityRequired = $true; noStaleContent = $true }
            keyFrames = @()
            forbidden = @("Out-of-order levels; unchanged intensity across all three levels; stale or overprinted digits; blank frames; reverse background; wrapped, clipped, or extra text.")
            review = [ordered]@{ framesPerSecond = 2.0; maxFrames = 24 }
        },
        [ordered]@{
            video = "blink-blank.mkv"
            duration = [ordered]@{ minSeconds = 6.5; maxSeconds = 8.0 }
            states = @(
                [ordered]@{ name = "blank-visible"; description = "NATIVE BLINK above NORMAL / BLANK is fully visible in normal mode."; minOccurrences = 3 },
                [ordered]@{ name = "blank-hidden"; description = "The display is fully blank with neither row nor stale partial pixels visible."; minOccurrences = 3 }
            )
            cadence = [ordered]@{ mode = "alternating"; states = @("blank-visible", "blank-hidden"); expectedStateSeconds = 1.0; toleranceSeconds = 0.4; minTransitions = 5 }
            scrolling = [ordered]@{ direction = "none"; continuityRequired = $true; noStaleContent = $true }
            keyFrames = @()
            forbidden = @("Partial-row blanking, stale pixels in hidden intervals, frozen state, wrong alternation order, reverse flashes, wrapping, clipping, or unrelated content.")
            review = [ordered]@{ framesPerSecond = 2.0; maxFrames = 18 }
        },
        [ordered]@{
            video = "blink-reverse.mkv"
            duration = [ordered]@{ minSeconds = 6.5; maxSeconds = 8.0 }
            states = @(
                [ordered]@{ name = "reverse-normal"; description = "NATIVE BLINK above NORMAL / REVERSE is fully visible on the normal dark background."; minOccurrences = 3 },
                [ordered]@{ name = "reverse-inverted"; description = "The same two complete rows are fully visible with reversed bright character cells."; minOccurrences = 3 }
            )
            cadence = [ordered]@{ mode = "alternating"; states = @("reverse-normal", "reverse-inverted"); expectedStateSeconds = 1.0; toleranceSeconds = 0.4; minTransitions = 5 }
            scrolling = [ordered]@{ direction = "none"; continuityRequired = $true; noStaleContent = $true }
            keyFrames = @()
            forbidden = @("Blank phases, a persistent partial reversal state, stale pixels, frozen state, wrong alternation order, wrapping, clipping, or unrelated content.")
            review = [ordered]@{ framesPerSecond = 2.0; maxFrames = 18 }
        },
        [ordered]@{
            video = "finale-to-loop.mkv"
            duration = [ordered]@{ minSeconds = 7.5; maxSeconds = 9.0 }
            states = @(
                [ordered]@{ name = "finale-visible"; description = "The clean centered SHOWCASE / LOOPING... finale is visible."; minOccurrences = 2 },
                [ordered]@{ name = "title-visible"; description = "The next clean centered FEATURE / SHOWCASE title is visible."; minOccurrences = 2 }
            )
            cadence = [ordered]@{ mode = "none"; states = @(); expectedStateSeconds = 0; toleranceSeconds = 0; minTransitions = 0 }
            scrolling = [ordered]@{ direction = "none"; continuityRequired = $true; noStaleContent = $true }
            keyFrames = @(
                [ordered]@{
                    name = "finale-start"
                    position = "start"
                    requiredRows = @("SHOWCASE", "LOOPING...")
                    layout = "Two clean centered finale rows on a normal dark background."
                    forbidden = @("FEATURE, stale content, wrapping, clipping, reverse background, or extra text.")
                },
                [ordered]@{
                    name = "next-loop-title"
                    position = "end"
                    requiredRows = @("FEATURE", "SHOWCASE")
                    layout = "Two clean centered title rows after the loop transition, with no finale residue."
                    forbidden = @("LOOPING..., stale content, wrapping, clipping, reverse background, or extra text.")
                }
            )
            forbidden = @("A blank or partially cleared transition frame persisting between cards; joined rows; stale window/graphics/mixture pixels; blink or reverse state leakage.")
            review = [ordered]@{ framesPerSecond = 2.0; maxFrames = 20 }
        }
    )
}

$VisualExpectations | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $CaptureDirectory "visual-expectations.json") -Encoding UTF8
$VideoExpectations | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $CaptureDirectory "video-expectations.json") -Encoding UTF8

Write-Host "=== GU7003 FEATURE SHOWCASE HIL ==="
Write-Host "Repository: $RepoRoot"
Write-Host "Target:     $FQBN"
Write-Host "Port:       $Port"
Write-Host "Captures:   $CaptureDirectory"

Write-Host "[1/3] Compiling FeatureShowcase..."
New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
& $ArduinoCli compile --fqbn $FQBN --library $RepoRoot --build-path $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "FeatureShowcase compile failed." }

Write-Host "[2/3] Uploading FeatureShowcase to $Port..."
& $ArduinoCli upload -p $Port --fqbn $FQBN --input-dir $BuildPath $Sketch
if ($LASTEXITCODE -ne 0) { throw "FeatureShowcase upload failed." }

Write-Host "[3/3] Capturing one complete showroom loop..."
$Clock = [System.Diagnostics.Stopwatch]::StartNew()
Capture-ImageAt -Clock $Clock -Seconds 5.0 -Name "title.jpg"
Capture-ImageAt -Clock $Clock -Seconds 14.0 -Name "typography.jpg"
Capture-VideoAt -Clock $Clock -Seconds 20.0 -Name "brightness-sweep.mkv" -DurationSeconds 10
Capture-ImageAt -Clock $Clock -Seconds 35.5 -Name "reverse-inverted.jpg"
Capture-ImageAt -Clock $Clock -Seconds 39.5 -Name "reverse-restored.jpg"
Capture-VideoAt -Clock $Clock -Seconds 44.0 -Name "blink-blank.mkv" -DurationSeconds 7
Capture-VideoAt -Clock $Clock -Seconds 54.5 -Name "blink-reverse.mkv" -DurationSeconds 7
Capture-ImageAt -Clock $Clock -Seconds 65.0 -Name "graphics.jpg"
Capture-ImageAt -Clock $Clock -Seconds 74.0 -Name "write-mixture.jpg"
Capture-ImageAt -Clock $Clock -Seconds 83.0 -Name "windows-initial.jpg"
Capture-ImageAt -Clock $Clock -Seconds 90.0 -Name "windows-updated.jpg"
Capture-ImageAt -Clock $Clock -Seconds 98.0 -Name "windows-base.jpg"
Capture-ImageAt -Clock $Clock -Seconds 105.0 -Name "finale.jpg"
Capture-VideoAt -Clock $Clock -Seconds 106.5 -Name "finale-to-loop.mkv" -DurationSeconds 8
Capture-ImageAt -Clock $Clock -Seconds 116.0 -Name "loop-title.jpg"
$Clock.Stop()

Write-Host "FeatureShowcase evidence capture complete."
Write-Host "Visual expectations: $(Join-Path $CaptureDirectory 'visual-expectations.json')"
Write-Host "Video expectations:  $(Join-Path $CaptureDirectory 'video-expectations.json')"
