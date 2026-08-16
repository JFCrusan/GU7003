[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\VideoSelfTest")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-MediaTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }
    $Candidate = "C:\Program Files\DownloadHelper CoApp\$Name.exe"
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return $Candidate
    }
    return $null
}

$Ffmpeg = Resolve-MediaTool -Name "ffmpeg"
if (-not $Ffmpeg) {
    throw "ffmpeg was not found."
}

$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$Video = Join-Path $OutputDirectory "simulated-alternation.mkv"
$ReviewDirectory = Join-Path $OutputDirectory "review"
$PrepareScript = Join-Path $PSScriptRoot "prepare-video-evidence.ps1"

# Alternating monochrome frames exercise odd-height 390x115 lossless video,
# FFprobe timing, bounded sampling, timestamped filenames, and frame decoding.
& $Ffmpeg -hide_banner -loglevel error -y `
    -f lavfi `
    -i "color=c=black:s=390x116:r=4:d=4" `
    -vf "format=yuv444p,crop=390:115:0:0,negate=enable='lt(mod(t,1),0.5)'" `
    -an `
    -c:v ffv1 `
    -level 3 `
    -g 1 `
    $Video
if ($LASTEXITCODE -ne 0) {
    throw "Simulated FFmpeg video generation failed."
}

& $PrepareScript `
    -Video $Video `
    -OutputDirectory $ReviewDirectory `
    -SamplesPerSecond 2 `
    -MaximumFrames 12 `
    -AdditionalTimestampsCsv "0.25,3.75"
if ($LASTEXITCODE -ne 0) {
    throw "Simulated video evidence preparation failed."
}

$MetadataPath = Join-Path $ReviewDirectory "video-metadata.json"
$Metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
if ([double]$Metadata.durationSeconds -lt 3.9 -or [double]$Metadata.durationSeconds -gt 4.1) {
    throw "Unexpected self-test duration: $($Metadata.durationSeconds)"
}
if ([int]$Metadata.width -ne 390 -or [int]$Metadata.height -ne 115) {
    throw "Calibrated evidence dimensions were not preserved: $($Metadata.width)x$($Metadata.height)"
}
if (@($Metadata.samples).Count -lt 9 -or @($Metadata.samples).Count -gt 12) {
    throw "Bounded frame extraction produced an unexpected count: $(@($Metadata.samples).Count)"
}
foreach ($Sample in @($Metadata.samples)) {
    if (-not (Test-Path -LiteralPath $Sample.imagePath -PathType Leaf)) {
        throw "Timestamped self-test frame is missing: $($Sample.imagePath)"
    }
}

Write-Host "Video evidence self-test PASS"
Write-Host "Original video retained: $Video"
Write-Host "Metadata:                $MetadataPath"
Write-Host "Timestamped frames:      $(@($Metadata.samples).Count)"
