[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Video,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [ValidateRange(0.25, 8.0)]
    [double]$SamplesPerSecond = 2.0,

    [ValidateRange(2, 48)]
    [int]$MaximumFrames = 24,

    [string]$AdditionalTimestampsCsv = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

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

function Convert-RationalToDouble {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq "0/0") {
        return 0.0
    }
    if ($Value -notmatch "^(-?[0-9]+(?:\.[0-9]+)?)/([0-9]+(?:\.[0-9]+)?)$") {
        return [double]::Parse($Value, $InvariantCulture)
    }

    $Numerator = [double]::Parse($Matches[1], $InvariantCulture)
    $Denominator = [double]::Parse($Matches[2], $InvariantCulture)
    if ($Denominator -eq 0) {
        return 0.0
    }
    return $Numerator / $Denominator
}

$Ffmpeg = Resolve-MediaTool -Name "ffmpeg"
$Ffprobe = Resolve-MediaTool -Name "ffprobe"
if (-not $Ffmpeg -or -not $Ffprobe) {
    throw "ffmpeg and ffprobe are required to prepare video evidence."
}

$Video = [System.IO.Path]::GetFullPath($Video)
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $Video -PathType Leaf)) {
    throw "Video evidence was not found: $Video"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$ProbeText = @(& $Ffprobe -v error -select_streams v:0 `
    -show_entries "format=duration,size:stream=codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames" `
    -of json $Video 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe failed for '$Video': $ProbeText"
}

$Probe = $ProbeText | ConvertFrom-Json
$Streams = @($Probe.streams)
if ($Streams.Count -ne 1) {
    throw "Expected exactly one video stream in '$Video'."
}
$DurationSeconds = [double]::Parse([string]$Probe.format.duration, $InvariantCulture)
if ($DurationSeconds -le 0) {
    throw "Video duration must be positive: $Video"
}
$Stream = $Streams[0]
$FrameRate = Convert-RationalToDouble -Value ([string]$Stream.avg_frame_rate)
if ($FrameRate -le 0) {
    $FrameRate = Convert-RationalToDouble -Value ([string]$Stream.r_frame_rate)
}

$FinalFrameMargin = if ($FrameRate -gt 0) { 1.0 / $FrameRate } else { 0.05 }
$FinalFrameMargin = [Math]::Max(0.001, [Math]::Min($FinalFrameMargin, $DurationSeconds / 2.0))
$LastTimestamp = [Math]::Max(0.0, $DurationSeconds - $FinalFrameMargin)

$AdditionalTimestamps = New-Object System.Collections.Generic.List[double]
if (-not [string]::IsNullOrWhiteSpace($AdditionalTimestampsCsv)) {
    foreach ($Value in $AdditionalTimestampsCsv.Split(',')) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }
        $Timestamp = [double]::Parse($Value.Trim(), $InvariantCulture)
        if ($Timestamp -lt 0 -or $Timestamp -gt $DurationSeconds) {
            throw "Additional frame timestamp $Timestamp is outside the video duration."
        }
        $AdditionalTimestamps.Add([Math]::Min($Timestamp, $LastTimestamp))
    }
}
$UniqueAdditionalTimestamps = @($AdditionalTimestamps | Sort-Object -Unique)
if ($UniqueAdditionalTimestamps.Count -gt ($MaximumFrames - 2)) {
    throw "Explicit key-frame timestamps leave no room for start/end review frames within the $MaximumFrames-frame bound."
}

$NominalCount = [int][Math]::Ceiling($DurationSeconds * $SamplesPerSecond) + 1
$UniformCapacity = $MaximumFrames - $UniqueAdditionalTimestamps.Count
$UniformCount = [Math]::Min($UniformCapacity, [Math]::Max(2, $NominalCount))
$Timestamps = New-Object System.Collections.Generic.List[double]
for ($Index = 0; $Index -lt $UniformCount; $Index++) {
    $Timestamp = if ($UniformCount -eq 1) { 0.0 } else { $LastTimestamp * $Index / ($UniformCount - 1) }
    $Timestamps.Add($Timestamp)
}
foreach ($Timestamp in $UniqueAdditionalTimestamps) {
    $Timestamps.Add($Timestamp)
}

$SortedTimestamps = @($Timestamps | Sort-Object -Unique)
if ($SortedTimestamps.Count -gt $MaximumFrames) {
    throw "Video evidence requested $($SortedTimestamps.Count) frames; the declared limit is $MaximumFrames."
}

$Samples = @()
$FrameIndex = 0
foreach ($Timestamp in $SortedTimestamps) {
    $FrameIndex++
    $Milliseconds = [int64][Math]::Round($Timestamp * 1000.0)
    $FrameName = "frame-{0:D3}-t{1:D8}ms.png" -f $FrameIndex, $Milliseconds
    $FramePath = Join-Path $OutputDirectory $FrameName
    $TimestampText = $Timestamp.ToString("0.000000", $InvariantCulture)

    & $Ffmpeg -hide_banner -loglevel error -y `
        -ss $TimestampText `
        -i $Video `
        -frames:v 1 `
        -vf "format=rgb24" `
        $FramePath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $FramePath -PathType Leaf)) {
        throw "Failed to extract review frame at $TimestampText seconds from '$Video'."
    }

    $Samples += [ordered]@{
        image = $FrameName
        imagePath = $FramePath
        timeSeconds = [Math]::Round($Timestamp, 6)
    }
}

$EncodedFrameCount = 0
if ($Stream.PSObject.Properties.Name -contains "nb_frames" -and
    -not [string]::IsNullOrWhiteSpace([string]$Stream.nb_frames) -and
    [string]$Stream.nb_frames -ne "N/A") {
    $EncodedFrameCount = [int64]$Stream.nb_frames
}

$Metadata = [ordered]@{
    version = 1
    video = [System.IO.Path]::GetFileName($Video)
    videoPath = $Video
    durationSeconds = [Math]::Round($DurationSeconds, 6)
    fileSizeBytes = [int64]$Probe.format.size
    codec = [string]$Stream.codec_name
    width = [int]$Stream.width
    height = [int]$Stream.height
    frameRate = [Math]::Round($FrameRate, 6)
    encodedFrameCount = $EncodedFrameCount
    requestedSamplesPerSecond = $SamplesPerSecond
    maximumFrames = $MaximumFrames
    samples = $Samples
}
$MetadataPath = Join-Path $OutputDirectory "video-metadata.json"
$Metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $MetadataPath -Encoding UTF8

Write-Host "Video evidence preparation PASS: $Video"
Write-Host "Metadata: $MetadataPath"
Write-Host "Duration: $($Metadata.durationSeconds) seconds"
Write-Host "Frames:   $($Samples.Count) timestamped review images"
