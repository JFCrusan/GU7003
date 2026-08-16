[CmdletBinding()]
param(
    [string]$Image = (Join-Path $PSScriptRoot "vfd.jpg"),
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

$FfmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
$Ffmpeg = if ($FfmpegCommand) { $FfmpegCommand.Source } else { $null }

if (-not $Ffmpeg) {
    $FfmpegCandidates = @(
        "C:\Program Files\DownloadHelper CoApp\ffmpeg.exe"
    )

    $Ffmpeg = $FfmpegCandidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

if (-not $Ffmpeg) {
    throw "ffmpeg was not found. Install it or add it to PATH."
}

$Image = [System.IO.Path]::GetFullPath($Image)
$ImageDirectory = Split-Path -Parent $Image
if (-not (Test-Path -LiteralPath $ImageDirectory)) {
    New-Item -ItemType Directory -Path $ImageDirectory -Force | Out-Null
}

& $Ffmpeg -hide_banner -loglevel warning -y `
    -f dshow `
    -i "video=$VideoDevice" `
    -vf $Crop `
    -frames:v 1 `
    -update 1 `
    $Image

if ($LASTEXITCODE -ne 0) {
    throw "VFD capture failed."
}

if (-not (Test-Path -LiteralPath $Image)) {
    throw "VFD image was not created: $Image"
}

Write-Host "Capture PASS: $Image"
