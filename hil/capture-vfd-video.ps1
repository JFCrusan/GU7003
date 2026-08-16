[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Video,

    [ValidateRange(1, 60)]
    [int]$DurationSeconds = 10,

    [ValidateRange(1, 60)]
    [int]$FramesPerSecond = 30,

    [string]$VideoDevice = $(
        if ([string]::IsNullOrWhiteSpace($env:GU7003_HIL_VIDEO_DEVICE)) {
            "HD Pro Webcam C920"
        }
        else {
            $env:GU7003_HIL_VIDEO_DEVICE
        }
    ),

    [string]$Crop = $(
        if ([string]::IsNullOrWhiteSpace($env:GU7003_HIL_CROP)) {
            "crop=390:115:135:120"
        }
        else {
            $env:GU7003_HIL_CROP
        }
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Ffmpeg {
    $Command = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    return @(
        "C:\Program Files\DownloadHelper CoApp\ffmpeg.exe"
    ) |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

$Ffmpeg = Resolve-Ffmpeg
if (-not $Ffmpeg) {
    throw "ffmpeg was not found. Install it or add it to PATH."
}

$Video = [System.IO.Path]::GetFullPath($Video)
if ([System.IO.Path]::GetExtension($Video).ToLowerInvariant() -ne ".mkv") {
    throw "VFD video capture uses lossless Matroska output; the video filename must end in .mkv."
}

$VideoDirectory = Split-Path -Parent $Video
if (-not (Test-Path -LiteralPath $VideoDirectory)) {
    New-Item -ItemType Directory -Path $VideoDirectory -Force | Out-Null
}

# The calibrated crop has an odd height. YUV 4:4:4 preserves its exact
# 390x115 geometry without the even-dimension rounding required by 4:2:0.
$VideoFilter = "format=yuv444p,$Crop,fps=$FramesPerSecond"

& $Ffmpeg -hide_banner -loglevel warning -y `
    -f dshow `
    -rtbufsize 256M `
    -i "video=$VideoDevice" `
    -t $DurationSeconds `
    -an `
    -vf $VideoFilter `
    -c:v ffv1 `
    -level 3 `
    -g 1 `
    -slicecrc 1 `
    $Video

if ($LASTEXITCODE -ne 0) {
    throw "VFD video capture failed."
}

if (-not (Test-Path -LiteralPath $Video -PathType Leaf)) {
    throw "VFD video was not created: $Video"
}
if ((Get-Item -LiteralPath $Video).Length -eq 0) {
    throw "VFD video is empty: $Video"
}

Write-Host "Video capture PASS: $Video"
Write-Host "Duration requested: $DurationSeconds seconds"
Write-Host "Capture rate:       $FramesPerSecond fps"
Write-Host "Crop:               $Crop"
