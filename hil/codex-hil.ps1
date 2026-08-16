[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9._-]*$")]
    [string]$Feature,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Task,

    [ValidateRange(2, 20)]
    [int]$MaxIterations = 5,

    [string]$HilScript = "",
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$Port = "COM3",
    [string]$VideoDevice = "HD Pro Webcam C920",
    [string]$Crop = "crop=390:115:135:120",

    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-GitLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingTree,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Output = @(& git -C $WorkingTree @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($Output -join [Environment]::NewLine)"
    }

    return $Output
}

function Get-RegisteredWorktrees {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $Records = @()
    $Current = $null

    foreach ($Line in @(Invoke-GitLines -WorkingTree $Repository -Arguments @("worktree", "list", "--porcelain"))) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            if ($null -ne $Current) {
                $Records += $Current
                $Current = $null
            }
            continue
        }

        if ($Line.StartsWith("worktree ")) {
            if ($null -ne $Current) {
                $Records += $Current
            }
            $Current = [ordered]@{
                Path = [System.IO.Path]::GetFullPath($Line.Substring(9))
                Branch = ""
                Head = ""
            }
        }
        elseif ($null -ne $Current -and $Line.StartsWith("HEAD ")) {
            $Current.Head = $Line.Substring(5)
        }
        elseif ($null -ne $Current -and $Line.StartsWith("branch ")) {
            $Current.Branch = $Line.Substring(7)
        }
    }

    if ($null -ne $Current) {
        $Records += $Current
    }

    return @($Records | ForEach-Object { [pscustomobject]$_ })
}

function Get-WorktreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$WorkingTree)

    $Material = New-Object System.Text.StringBuilder
    $Diff = @(Invoke-GitLines -WorkingTree $WorkingTree -Arguments @("diff", "--binary", "HEAD", "--", "."))
    [void]$Material.AppendLine(($Diff -join "`n"))

    $Untracked = @(Invoke-GitLines -WorkingTree $WorkingTree -Arguments @("ls-files", "--others", "--exclude-standard"))
    foreach ($RelativePath in @($Untracked | Sort-Object)) {
        $FullPath = Join-Path $WorkingTree $RelativePath
        [void]$Material.AppendLine("UNTRACKED:$RelativePath")
        if (Test-Path -LiteralPath $FullPath -PathType Leaf) {
            [void]$Material.AppendLine((Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash)
        }
    }

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Material.ToString())
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Sha256.ComputeHash($Bytes))).Replace("-", "")
    }
    finally {
        $Sha256.Dispose()
    }
}

function Resolve-SafeHilScript {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingTree,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "HIL script paths must be relative to the feature worktree: $RelativePath"
    }

    $RootWithSeparator = [System.IO.Path]::GetFullPath($WorkingTree).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $Candidate = [System.IO.Path]::GetFullPath((Join-Path $WorkingTree $RelativePath))
    if (-not $Candidate.StartsWith($RootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "HIL script escapes the feature worktree: $RelativePath"
    }
    if ([System.IO.Path]::GetExtension($Candidate) -ne ".ps1") {
        throw "HIL script must be a PowerShell script: $RelativePath"
    }

    return $Candidate
}

function Get-LogExcerpt {
    param(
        [string]$Path,
        [int]$MaximumCharacters = 16000
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "(log was not created)"
    }

    $Content = Get-Content -LiteralPath $Path -Raw
    if ($Content.Length -le $MaximumCharacters) {
        return $Content
    }

    return "(earlier output omitted)`n" + $Content.Substring($Content.Length - $MaximumCharacters)
}

function Read-VisualExpectations {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Images
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $Manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($Manifest.PSObject.Properties.Name -notcontains "version" -or $Manifest.version -ne 1) {
        throw "Visual expectations must declare version 1: $Path"
    }
    if ($Manifest.PSObject.Properties.Name -notcontains "captures" -or @($Manifest.captures).Count -eq 0) {
        throw "Visual expectations must contain at least one capture: $Path"
    }

    $ImagesByName = @{}
    foreach ($Image in $Images) {
        $Name = [System.IO.Path]::GetFileName($Image)
        if ($ImagesByName.ContainsKey($Name)) {
            throw "Captured image names must be unique for exact visual validation: $Name"
        }
        $ImagesByName[$Name] = $Image
    }

    $Seen = @{}
    $Expectations = @()
    foreach ($Capture in @($Manifest.captures)) {
        foreach ($Property in @("image", "requiredRows", "layout", "forbidden")) {
            if ($Capture.PSObject.Properties.Name -notcontains $Property) {
                throw "Visual expectation is missing property '$Property': $Path"
            }
        }

        $ImageName = [string]$Capture.image
        if ([string]::IsNullOrWhiteSpace($ImageName) -or
            [System.IO.Path]::GetFileName($ImageName) -ne $ImageName) {
            throw "Visual expectation image must be a filename without directories: '$ImageName'"
        }
        if ($Seen.ContainsKey($ImageName)) {
            throw "Visual expectation image names must be unique: $ImageName"
        }
        if (-not $ImagesByName.ContainsKey($ImageName)) {
            throw "Visual expectation does not match a captured image: $ImageName"
        }
        if (@($Capture.requiredRows).Count -eq 0) {
            throw "Visual expectation must name at least one exact required row: $ImageName"
        }
        if ([string]::IsNullOrWhiteSpace([string]$Capture.layout)) {
            throw "Visual expectation must describe exact layout: $ImageName"
        }

        $Seen[$ImageName] = $true
        $Expectations += [pscustomobject]@{
            Image = $ImageName
            ImagePath = $ImagesByName[$ImageName]
            RequiredRows = @($Capture.requiredRows)
            Layout = [string]$Capture.layout
            Forbidden = @($Capture.forbidden)
        }
    }

    return @($Expectations)
}

function Read-VideoExpectations {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Videos
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $Manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($Manifest.PSObject.Properties.Name -notcontains "version" -or $Manifest.version -ne 1) {
        throw "Video expectations must declare version 1: $Path"
    }
    if ($Manifest.PSObject.Properties.Name -notcontains "videos" -or @($Manifest.videos).Count -eq 0) {
        throw "Video expectations must contain at least one video: $Path"
    }

    $VideosByName = @{}
    foreach ($Video in $Videos) {
        $Name = [System.IO.Path]::GetFileName($Video)
        if ($VideosByName.ContainsKey($Name)) {
            throw "Captured video names must be unique for dynamic validation: $Name"
        }
        $VideosByName[$Name] = $Video
    }

    $SeenVideos = @{}
    $Expectations = @()
    foreach ($VideoExpectation in @($Manifest.videos)) {
        foreach ($Property in @("video", "duration", "states", "cadence", "scrolling", "keyFrames", "forbidden", "review")) {
            if ($VideoExpectation.PSObject.Properties.Name -notcontains $Property) {
                throw "Video expectation is missing property '$Property': $Path"
            }
        }

        $VideoName = [string]$VideoExpectation.video
        if ([string]::IsNullOrWhiteSpace($VideoName) -or
            [System.IO.Path]::GetFileName($VideoName) -ne $VideoName) {
            throw "Video expectation must use a filename without directories: '$VideoName'"
        }
        if ($SeenVideos.ContainsKey($VideoName)) {
            throw "Video expectation filenames must be unique: $VideoName"
        }
        if (-not $VideosByName.ContainsKey($VideoName)) {
            throw "Video expectation does not match a captured video: $VideoName"
        }

        foreach ($Property in @("minSeconds", "maxSeconds")) {
            if ($VideoExpectation.duration.PSObject.Properties.Name -notcontains $Property) {
                throw "Video duration expectation is missing '$Property': $VideoName"
            }
        }
        $MinimumSeconds = [double]$VideoExpectation.duration.minSeconds
        $MaximumSeconds = [double]$VideoExpectation.duration.maxSeconds
        if ($MinimumSeconds -le 0 -or $MaximumSeconds -lt $MinimumSeconds) {
            throw "Video duration range is invalid: $VideoName"
        }

        foreach ($Property in @("framesPerSecond", "maxFrames")) {
            if ($VideoExpectation.review.PSObject.Properties.Name -notcontains $Property) {
                throw "Video review settings are missing '$Property': $VideoName"
            }
        }
        $ReviewFramesPerSecond = [double]$VideoExpectation.review.framesPerSecond
        $MaximumReviewFrames = [int]$VideoExpectation.review.maxFrames
        if ($ReviewFramesPerSecond -lt 0.25 -or $ReviewFramesPerSecond -gt 8.0 -or
            $MaximumReviewFrames -lt 2 -or $MaximumReviewFrames -gt 48) {
            throw "Video review settings exceed the supported bounds: $VideoName"
        }
        if (([int][Math]::Ceiling($MaximumSeconds * $ReviewFramesPerSecond) + 1) -gt $MaximumReviewFrames) {
            throw "Video review maxFrames would reduce the declared framesPerSecond before maxSeconds: $VideoName"
        }

        $StateNames = @{}
        $States = @()
        foreach ($State in @($VideoExpectation.states)) {
            foreach ($Property in @("name", "description", "minOccurrences")) {
                if ($State.PSObject.Properties.Name -notcontains $Property) {
                    throw "Video state expectation is missing '$Property': $VideoName"
                }
            }
            $StateName = [string]$State.name
            if ([string]::IsNullOrWhiteSpace($StateName) -or $StateNames.ContainsKey($StateName)) {
                throw "Video state names must be non-empty and unique: $VideoName"
            }
            if ([string]::IsNullOrWhiteSpace([string]$State.description) -or [int]$State.minOccurrences -lt 1) {
                throw "Video state description/minOccurrences is invalid for '$StateName': $VideoName"
            }
            $StateNames[$StateName] = $true
            $States += $State
        }

        foreach ($Property in @("mode", "states", "expectedStateSeconds", "toleranceSeconds", "minTransitions")) {
            if ($VideoExpectation.cadence.PSObject.Properties.Name -notcontains $Property) {
                throw "Video cadence expectation is missing '$Property': $VideoName"
            }
        }
        $CadenceMode = [string]$VideoExpectation.cadence.mode
        if (@("none", "steady", "alternating") -notcontains $CadenceMode) {
            throw "Video cadence mode must be none, steady, or alternating: $VideoName"
        }
        if ($CadenceMode -eq "alternating") {
            if (@($VideoExpectation.cadence.states).Count -lt 2 -or
                [double]$VideoExpectation.cadence.expectedStateSeconds -le 0 -or
                [double]$VideoExpectation.cadence.toleranceSeconds -lt 0 -or
                [int]$VideoExpectation.cadence.minTransitions -lt 1) {
                throw "Alternating cadence expectations are incomplete: $VideoName"
            }
            if (($ReviewFramesPerSecond * [double]$VideoExpectation.cadence.expectedStateSeconds) -lt 2.0) {
                throw "Alternating cadence review must sample at least twice per expected state: $VideoName"
            }
            foreach ($StateName in @($VideoExpectation.cadence.states)) {
                if (-not $StateNames.ContainsKey([string]$StateName)) {
                    throw "Cadence references unknown state '$StateName': $VideoName"
                }
            }
        }

        foreach ($Property in @("direction", "continuityRequired", "noStaleContent")) {
            if ($VideoExpectation.scrolling.PSObject.Properties.Name -notcontains $Property) {
                throw "Video scrolling expectation is missing '$Property': $VideoName"
            }
        }
        $Direction = [string]$VideoExpectation.scrolling.direction
        if (@("none", "left", "right", "up", "down") -notcontains $Direction) {
            throw "Unsupported scrolling direction '$Direction': $VideoName"
        }

        $KeyFrameNames = @{}
        $KeyFrames = @()
        foreach ($KeyFrame in @($VideoExpectation.keyFrames)) {
            foreach ($Property in @("name", "requiredRows", "layout", "forbidden")) {
                if ($KeyFrame.PSObject.Properties.Name -notcontains $Property) {
                    throw "Video key-frame expectation is missing '$Property': $VideoName"
                }
            }
            $KeyFrameName = [string]$KeyFrame.name
            if ([string]::IsNullOrWhiteSpace($KeyFrameName) -or $KeyFrameNames.ContainsKey($KeyFrameName)) {
                throw "Video key-frame names must be non-empty and unique: $VideoName"
            }
            $HasPosition = $KeyFrame.PSObject.Properties.Name -contains "position"
            $HasTimestamp = $KeyFrame.PSObject.Properties.Name -contains "atSeconds"
            if ($HasPosition -eq $HasTimestamp) {
                throw "Key frame '$KeyFrameName' must declare exactly one of position or atSeconds: $VideoName"
            }
            if ($HasPosition -and @("start", "end") -notcontains [string]$KeyFrame.position) {
                throw "Key frame '$KeyFrameName' position must be start or end: $VideoName"
            }
            if ($HasTimestamp -and [double]$KeyFrame.atSeconds -lt 0) {
                throw "Key frame '$KeyFrameName' has a negative timestamp: $VideoName"
            }
            if (@($KeyFrame.requiredRows).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$KeyFrame.layout)) {
                throw "Key frame '$KeyFrameName' needs exact rows and layout: $VideoName"
            }
            $KeyFrameNames[$KeyFrameName] = $true
            $KeyFrames += $KeyFrame
        }

        $SeenVideos[$VideoName] = $true
        $Expectations += [pscustomobject]@{
            Video = $VideoName
            VideoPath = $VideosByName[$VideoName]
            MinimumSeconds = $MinimumSeconds
            MaximumSeconds = $MaximumSeconds
            States = $States
            Cadence = $VideoExpectation.cadence
            Scrolling = $VideoExpectation.scrolling
            KeyFrames = $KeyFrames
            Forbidden = @($VideoExpectation.forbidden)
            ReviewFramesPerSecond = $ReviewFramesPerSecond
            MaximumReviewFrames = $MaximumReviewFrames
        }
    }

    return @($Expectations)
}

function Invoke-LoggedPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $PowerShellExecutable = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        $PowerShellExecutable = (Get-Command pwsh -ErrorAction Stop).Source
    }

    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        # Native tools such as arduino-cli and ffmpeg may use stderr for normal
        # progress. Preserve it in the evidence log without turning it into a
        # controller exception before their process exit code can be inspected.
        $ErrorActionPreference = "Continue"
        & $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1 |
            Tee-Object -FilePath $LogPath |
            ForEach-Object { Write-Host $_ }
        $ProcessExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    return $ProcessExitCode
}

function Test-ResultContract {
    param([Parameter(Mandatory = $true)]$Result)

    $RequiredProperties = @(
        "status",
        "summary",
        "hil_script",
        "expected_display",
        "visual_validation",
        "dynamic_validation",
        "tests_run",
        "remaining_issues",
        "human_review_reason"
    )
    foreach ($Property in $RequiredProperties) {
        if ($Result.PSObject.Properties.Name -notcontains $Property) {
            throw "Codex result is missing required property '$Property'."
        }
    }

    if (@("ready_for_hil", "pass", "human_review") -notcontains $Result.status) {
        throw "Codex returned unsupported status '$($Result.status)'."
    }
    if ($Result.status -eq "ready_for_hil" -and [string]::IsNullOrWhiteSpace($Result.hil_script)) {
        throw "Codex requested HIL without naming a HIL script."
    }
    if ($Result.status -eq "human_review" -and [string]::IsNullOrWhiteSpace($Result.human_review_reason)) {
        throw "Codex requested human review without explaining the boundary."
    }
}

function Write-ReviewSummary {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$WorkingTree,
        [string]$Artifacts = ""
    )

    Write-Host ""
    Write-Host "=== $Status ==="
    Write-Host "Reason:   $Reason"
    Write-Host "Branch:   $Branch"
    Write-Host "Worktree: $WorkingTree"
    if (-not [string]::IsNullOrWhiteSpace($Artifacts)) {
        Write-Host "Evidence: $Artifacts"
    }
    & git -C $WorkingTree status --short --branch
    Write-Host "No feature commit, merge, push, reset, or worktree cleanup was performed."
}

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$RepoParent = Split-Path -Parent $RepoRoot
$RepoName = Split-Path -Leaf $RepoRoot
$DefaultWorktreeRoot = Join-Path $RepoParent "$RepoName-worktrees"
$DefaultWorktreePath = Join-Path $DefaultWorktreeRoot $Feature
$BranchName = "feature/$Feature"
$BranchRef = "refs/heads/$BranchName"
$SchemaPath = Join-Path $PSScriptRoot "codex-hil-result.schema.json"
$ScenarioPath = Join-Path (Join-Path $PSScriptRoot "scenarios") "$Feature.json"

$ScenarioContext = ""
$ScenarioHilScript = ""
$RequireVisualExpectations = $false
$EvidenceMode = "snapshot"
if (Test-Path -LiteralPath $ScenarioPath -PathType Leaf) {
    $Scenario = Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json
    if ($Scenario.PSObject.Properties.Name -contains "hilScript") {
        $ScenarioHilScript = [string]$Scenario.hilScript
    }
    if ($Scenario.PSObject.Properties.Name -contains "context") {
        $ScenarioContext = (@($Scenario.context) -join "`n- ")
        if (-not [string]::IsNullOrWhiteSpace($ScenarioContext)) {
            $ScenarioContext = "- $ScenarioContext"
        }
    }
    if ($Scenario.PSObject.Properties.Name -contains "requireVisualExpectations") {
        $RequireVisualExpectations = [bool]$Scenario.requireVisualExpectations
    }
    if ($Scenario.PSObject.Properties.Name -contains "evidenceMode") {
        $EvidenceMode = [string]$Scenario.evidenceMode
    }
}
if (@("snapshot", "video", "mixed") -notcontains $EvidenceMode) {
    throw "Scenario evidenceMode must be snapshot, video, or mixed: $ScenarioPath"
}

$ConfiguredHilScript = $HilScript
if ([string]::IsNullOrWhiteSpace($ConfiguredHilScript)) {
    $ConfiguredHilScript = $ScenarioHilScript
}

$CurrentBranch = (@(Invoke-GitLines -WorkingTree $RepoRoot -Arguments @("branch", "--show-current")) -join "").Trim()
if ($CurrentBranch -ne "main") {
    throw "codex-hil.ps1 must start from a main worktree; current branch is '$CurrentBranch'."
}

$MainStatus = @(Invoke-GitLines -WorkingTree $RepoRoot -Arguments @("status", "--porcelain", "--untracked-files=all"))
if ($MainStatus.Count -ne 0) {
    throw "The main controller worktree must be clean before automation starts."
}

if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    throw "Codex result schema was not found: $SchemaPath"
}
$null = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json

$Worktrees = @(Get-RegisteredWorktrees -Repository $RepoRoot)
$MatchingWorktrees = @($Worktrees | Where-Object { $_.Branch -eq $BranchRef })
if ($MatchingWorktrees.Count -gt 1) {
    throw "Multiple worktrees are registered for $BranchName. Resolve that Git state manually."
}

$BranchExistsOutput = @(& git -C $RepoRoot show-ref --verify --quiet $BranchRef 2>&1)
$BranchCheck = $LASTEXITCODE
if ($BranchCheck -notin @(0, 1)) {
    throw "Unable to check whether $BranchName exists: $($BranchExistsOutput -join [Environment]::NewLine)"
}

$WorktreePath = $DefaultWorktreePath
$WorktreeAction = ""
if ($MatchingWorktrees.Count -eq 1) {
    $WorktreePath = $MatchingWorktrees[0].Path
    if (-not (Test-Path -LiteralPath $WorktreePath -PathType Container)) {
        throw "The registered feature worktree is missing: $WorktreePath"
    }
    $WorktreeAction = "reuse registered worktree"
}
elseif ($BranchCheck -eq 0) {
    if (Test-Path -LiteralPath $WorktreePath) {
        throw "The expected worktree path exists but is not registered: $WorktreePath"
    }
    $WorktreeAction = "create worktree for existing branch"
}
else {
    if (Test-Path -LiteralPath $WorktreePath) {
        throw "The expected worktree path already exists: $WorktreePath"
    }
    $WorktreeAction = "create feature branch and worktree from main"
}

Write-Host "=== GU7003 CODEX HIL CONTROLLER V2 ==="
Write-Host "Controller source:  $RepoRoot (clean main)"
Write-Host "Feature branch:     $BranchName"
Write-Host "Feature worktree:   $WorktreePath"
Write-Host "Worktree action:    $WorktreeAction"
Write-Host "Maximum iterations: $MaxIterations"
Write-Host "Board:              $FQBN"
Write-Host "Port:               $Port"
Write-Host "Camera:             $VideoDevice"
Write-Host "Crop:               $Crop"
if (-not [string]::IsNullOrWhiteSpace($ConfiguredHilScript)) {
    Write-Host "Focused HIL script: $ConfiguredHilScript"
}
if (-not [string]::IsNullOrWhiteSpace($ScenarioContext)) {
    Write-Host "Scenario context:   $ScenarioPath"
}
Write-Host "Exact visuals:      $(if ($RequireVisualExpectations) { 'required' } else { 'optional' })"
Write-Host "Evidence mode:      $EvidenceMode"

if ($PlanOnly) {
    Write-Host "PLAN ONLY: no branch, worktree, Codex, compile, upload, or camera action was performed."
    $global:LASTEXITCODE = 0
    return
}

$CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
if (-not $CodexCommand) {
    throw "codex was not found. Install the Codex CLI or add it to PATH."
}

if ($MatchingWorktrees.Count -eq 0) {
    New-Item -ItemType Directory -Path $DefaultWorktreeRoot -Force | Out-Null
    if ($BranchCheck -eq 0) {
        & git -C $RepoRoot worktree add $WorktreePath $BranchName
    }
    else {
        & git -C $RepoRoot worktree add -b $BranchName $WorktreePath main
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the feature worktree. Git state was not cleaned up automatically."
    }
}

$ActualFeatureBranch = (@(Invoke-GitLines -WorkingTree $WorktreePath -Arguments @("branch", "--show-current")) -join "").Trim()
if ($ActualFeatureBranch -ne $BranchName) {
    throw "Feature worktree branch mismatch. Expected '$BranchName', found '$ActualFeatureBranch'."
}
$InitialHead = (@(Invoke-GitLines -WorkingTree $WorktreePath -Arguments @("rev-parse", "HEAD")) -join "").Trim()

$RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StateDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-HIL\Controller\$Feature\$RunStamp-$PID"
New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null

$LatestEvidence = $null
$LatestEvidencePrompt = "No controller-run HIL evidence exists yet."
$LatestImages = @()
$PreviousCodexSummary = "No previous Codex iteration."
$FinalStatus = ""
$FinalReason = ""

for ($Iteration = 1; $Iteration -le $MaxIterations; $Iteration++) {
    Write-Host ""
    Write-Host "=== CODEX ITERATION $Iteration/$MaxIterations ==="

    $ResultPath = Join-Path $StateDirectory ("codex-result-{0:D2}.json" -f $Iteration)
    $Prompt = @"
You are one bounded implementation/review iteration for the GU7003 Arduino VFD library.

Task:
$Task

Repository state:
- Feature branch: $BranchName
- Feature worktree: $WorktreePath
- Existing uncommitted feature changes are intentional; inspect and preserve them.
- Initial feature HEAD: $InitialHead

Bench contract:
- Display: Noritake GU112X16G-7003, 112x16 pixels.
- Board: Arduino Duemilanove / ATmega328P ($FQBN).
- Port: $Port.
- Camera: $VideoDevice.
- Crop: $Crop.
- Scenario evidence mode: $EvidenceMode.
- The controller, outside your sandbox, owns compile-all, upload, waits, and camera capture.
- Do not upload hardware, open the camera, or run a hardware-facing HIL script yourself.

Safety contract:
- Work only in the existing feature worktree.
- Never commit, merge, push, reset, clean, create/remove worktrees, or switch branches.
- Run git diff --check and safe static/non-hardware checks when useful.
- Any code or test change made after HIL evidence requires another controller-run HIL cycle.

Result contract:
- Return status ready_for_hil after implementation/static checks are ready for external validation.
- For ready_for_hil, hil_script must be a relative .ps1 path inside this worktree. It must accept -FQBN, -Port, and -CaptureDirectory. Prefer '$ConfiguredHilScript' when that path is configured.
- Return pass only after reviewing the latest controller log and every attached snapshot/video-review frame, only when they prove every declared contract item, and only if you made no changes after that evidence.
- A capture script exiting zero proves capture, not visual correctness. Inspect the pixels and expected state transitions.
- A focused HIL script may define authoritative per-image acceptance in visual-expectations.json under its CaptureDirectory. When exact expectations appear in the latest evidence, visual_validation must contain exactly one record for each expected image filename. Transcribe each visible text row verbatim and in order into observed_rows; do not copy the expected rows unless those pixels are actually visible.
- Mark a visual_validation record as match only when observed_rows exactly equal requiredRows, layout_matches is true, forbidden_observed is empty, and all placement, wrapping, and absence requirements match. Materially incorrect placement, joined text, wrapping, truncation, stale content, or extra content is a mismatch even when the broader behavior works.
- A focused HIL script may also define authoritative dynamic acceptance in video-expectations.json. The original video is retained, but Codex video input is not supported, so the controller attaches a bounded ordered series of timestamped frames and supplies FFprobe timing metadata. dynamic_validation must contain exactly one record for every expected video.
- For each dynamic record, evaluate the declared duration, required state presence, cadence/alternation, direction, continuity, stale-content prohibition, exact key frames, and forbidden content independently. Report measured/observed values and cite only attached timestamped frame filenames. State occurrence counts need at least that many distinct evidence_frames; each key-frame verdict needs its exact evidence_frame. Status match requires every applicable item to match; uncertainty is unreviewable, never a permissive match.
- Do not use a general 'looks okay' verdict. A duration outside its declared range, absent state, insufficient transition count, cadence outside tolerance, wrong direction, discontinuity, stale content, key-frame text/layout mismatch, forbidden content, missing evidence, or unreviewable evidence rejects pass.
- For mismatch or unreviewable evidence, do not return pass. Describe the pixels actually observed and either make the smallest safe correction for another HIL cycle or return human_review at a genuine boundary.
- Return human_review only for a genuine boundary that cannot be resolved safely in another automated iteration; explain it precisely.
- Use the required JSON schema fields, including visual_validation and dynamic_validation. Use an empty string/array and false/zero only where a field is not applicable; applicable match booleans must reflect the evidence.

Scenario context:
$ScenarioContext

Previous Codex summary:
$PreviousCodexSummary

Latest external evidence:
$LatestEvidencePrompt
"@

    $CodexArguments = @(
        "exec",
        "--sandbox", "workspace-write",
        "--ask-for-approval", "never",
        "--cd", $WorktreePath,
        "--output-schema", $SchemaPath,
        "--output-last-message", $ResultPath,
        "--color", "never"
    )
    foreach ($Image in $LatestImages) {
        $CodexArguments += @("--image", $Image)
    }
    # Read the prompt from stdin so bounded log excerpts never approach the
    # Windows process command-line length limit.
    $CodexArguments += "-"

    $Prompt | & $CodexCommand.Source @CodexArguments
    $CodexExitCode = $LASTEXITCODE

    $CurrentFeatureBranch = (@(Invoke-GitLines -WorkingTree $WorktreePath -Arguments @("branch", "--show-current")) -join "").Trim()
    $CurrentHead = (@(Invoke-GitLines -WorkingTree $WorktreePath -Arguments @("rev-parse", "HEAD")) -join "").Trim()
    if ($CurrentFeatureBranch -ne $BranchName -or $CurrentHead -ne $InitialHead) {
        $FinalStatus = "HUMAN REVIEW BOUNDARY"
        $FinalReason = "Codex changed the feature branch or HEAD. The controller will not rewrite Git history automatically."
        break
    }
    if ($CodexExitCode -ne 0) {
        $FinalStatus = "HUMAN REVIEW BOUNDARY"
        $FinalReason = "Codex exited with code $CodexExitCode. Review its output and the preserved worktree."
        break
    }
    if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
        $FinalStatus = "HUMAN REVIEW BOUNDARY"
        $FinalReason = "Codex did not create its structured result file."
        break
    }

    try {
        $Result = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
        Test-ResultContract -Result $Result
    }
    catch {
        $FinalStatus = "HUMAN REVIEW BOUNDARY"
        $FinalReason = "Codex returned an invalid controller result: $($_.Exception.Message)"
        break
    }

    $PreviousCodexSummary = $Result.summary
    Write-Host "Codex status:  $($Result.status)"
    Write-Host "Codex summary: $($Result.summary)"

    if ($Result.status -eq "human_review") {
        $FinalStatus = "HUMAN REVIEW BOUNDARY"
        $FinalReason = $Result.human_review_reason
        break
    }

    if ($Result.status -eq "pass") {
        $PassProblem = ""
        if ($null -eq $LatestEvidence) {
            $PassProblem = "PASS was rejected because no controller-run HIL evidence exists."
        }
        elseif ($LatestEvidence.CompileExitCode -ne 0 -or $LatestEvidence.HilExitCode -ne 0) {
            $PassProblem = "PASS was rejected because the latest external compile/HIL process did not exit successfully."
        }
        elseif ($EvidenceMode -in @("snapshot", "mixed") -and @($LatestEvidence.Images).Count -eq 0) {
            $PassProblem = "PASS was rejected because snapshot evidence was required but the latest HIL run produced no camera images."
        }
        elseif ($EvidenceMode -in @("video", "mixed") -and @($LatestEvidence.Videos).Count -eq 0) {
            $PassProblem = "PASS was rejected because video evidence was required but the latest HIL run produced no video."
        }
        elseif ((Get-WorktreeFingerprint -WorkingTree $WorktreePath) -ne $LatestEvidence.TestedFingerprint) {
            $PassProblem = "PASS was rejected because files changed after the latest HIL run. Another HIL cycle is required."
        }
        elseif (@($Result.remaining_issues).Count -ne 0) {
            $PassProblem = "PASS was rejected because Codex reported remaining issues."
        }
        elseif ($RequireVisualExpectations -and @($LatestEvidence.VisualExpectations).Count -eq 0) {
            $PassProblem = "PASS was rejected because this scenario requires test-owned exact visual expectations."
        }
        elseif ($EvidenceMode -in @("video", "mixed") -and @($LatestEvidence.VideoExpectations).Count -eq 0) {
            $PassProblem = "PASS was rejected because dynamic evidence mode requires test-owned video expectations."
        }

        if ([string]::IsNullOrWhiteSpace($PassProblem) -and
            @($LatestEvidence.VisualExpectations).Count -gt 0) {
            $VisualValidation = @($Result.visual_validation)
            if ($VisualValidation.Count -ne @($LatestEvidence.VisualExpectations).Count) {
                $PassProblem = "PASS was rejected because visual_validation must contain exactly one record per test-owned expectation."
            }
            else {
                foreach ($Expectation in @($LatestEvidence.VisualExpectations)) {
                    $Matches = @($VisualValidation | Where-Object { $_.image -eq $Expectation.Image })
                    if ($Matches.Count -ne 1) {
                        $PassProblem = "PASS was rejected because visual_validation did not uniquely cover '$($Expectation.Image)'."
                        break
                    }
                    if ($Matches[0].status -ne "match") {
                        $PassProblem = "PASS was rejected because '$($Expectation.Image)' was '$($Matches[0].status)', not an exact match."
                        break
                    }
                    $ExpectedRows = @($Expectation.RequiredRows)
                    $ObservedRows = @($Matches[0].observed_rows)
                    if ($ObservedRows.Count -ne $ExpectedRows.Count) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Image)' did not report the required number of exact text rows."
                        break
                    }
                    for ($RowIndex = 0; $RowIndex -lt $ExpectedRows.Count; $RowIndex++) {
                        if ([string]$ObservedRows[$RowIndex] -cne [string]$ExpectedRows[$RowIndex]) {
                            $PassProblem = "PASS was rejected because '$($Expectation.Image)' row $($RowIndex + 1) was '$($ObservedRows[$RowIndex])', expected '$($ExpectedRows[$RowIndex])'."
                            break
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($PassProblem)) {
                        break
                    }
                    if ($Matches[0].layout_matches -ne $true) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Image)' did not match the required placement/wrapping layout."
                        break
                    }
                    if (@($Matches[0].forbidden_observed).Count -ne 0) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Image)' contained forbidden visual material: $(@($Matches[0].forbidden_observed) -join '; ')"
                        break
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$Matches[0].observed)) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Image)' has no visual observation."
                        break
                    }
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($PassProblem) -and
            @($LatestEvidence.VideoExpectations).Count -gt 0) {
            $DynamicValidation = @($Result.dynamic_validation)
            if ($DynamicValidation.Count -ne @($LatestEvidence.VideoExpectations).Count) {
                $PassProblem = "PASS was rejected because dynamic_validation must contain exactly one record per test-owned video expectation."
            }
            else {
                foreach ($Expectation in @($LatestEvidence.VideoExpectations)) {
                    $Matches = @($DynamicValidation | Where-Object { $_.video -eq $Expectation.Video })
                    if ($Matches.Count -ne 1) {
                        $PassProblem = "PASS was rejected because dynamic_validation did not uniquely cover '$($Expectation.Video)'."
                        break
                    }
                    $Validation = $Matches[0]
                    $EvidenceMatches = @($LatestEvidence.VideoEvidence | Where-Object { $_.Video -eq $Expectation.Video })
                    if ($EvidenceMatches.Count -ne 1) {
                        $PassProblem = "PASS was rejected because prepared video evidence did not uniquely cover '$($Expectation.Video)'."
                        break
                    }
                    $AvailableReviewFrames = @($EvidenceMatches[0].ReviewImages | ForEach-Object { [System.IO.Path]::GetFileName($_) })

                    $MeasuredDuration = [double]$EvidenceMatches[0].Metadata.durationSeconds
                    if ($MeasuredDuration -lt $Expectation.MinimumSeconds -or $MeasuredDuration -gt $Expectation.MaximumSeconds) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' duration was $MeasuredDuration seconds, outside $($Expectation.MinimumSeconds)-$($Expectation.MaximumSeconds)."
                        break
                    }
                    if ($Validation.status -ne "match" -or $Validation.duration_matches -ne $true -or
                        [Math]::Abs([double]$Validation.observed_duration_seconds - $MeasuredDuration) -gt 0.25) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not receive a matching, measured duration verdict."
                        break
                    }

                    if (@($Expectation.States).Count -gt 0) {
                        if ($Validation.states_match -ne $true) {
                            $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not match all required states."
                            break
                        }
                        foreach ($State in @($Expectation.States)) {
                            $StateMatches = @($Validation.observed_states | Where-Object { $_.name -ceq [string]$State.name })
                            if ($StateMatches.Count -ne 1 -or
                                [int]$StateMatches[0].occurrence_count -lt [int]$State.minOccurrences -or
                                @($StateMatches[0].evidence_frames).Count -lt [int]$StateMatches[0].occurrence_count -or
                                @($StateMatches[0].evidence_frames | Sort-Object -Unique).Count -ne @($StateMatches[0].evidence_frames).Count) {
                                $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not prove state '$($State.name)' at least $($State.minOccurrences) time(s)."
                                break
                            }
                            foreach ($EvidenceFrame in @($StateMatches[0].evidence_frames)) {
                                if ($AvailableReviewFrames -cnotcontains [string]$EvidenceFrame) {
                                    $PassProblem = "PASS was rejected because '$($Expectation.Video)' state '$($State.name)' cites unknown frame '$EvidenceFrame'."
                                    break
                                }
                            }
                            if (-not [string]::IsNullOrWhiteSpace($PassProblem)) {
                                break
                            }
                        }
                        if (-not [string]::IsNullOrWhiteSpace($PassProblem)) {
                            break
                        }
                    }

                    $CadenceMode = [string]$Expectation.Cadence.mode
                    if ($CadenceMode -eq "alternating") {
                        $ExpectedCadence = [double]$Expectation.Cadence.expectedStateSeconds
                        $CadenceTolerance = [double]$Expectation.Cadence.toleranceSeconds
                        if ($Validation.alternation_matches -ne $true -or
                            $Validation.cadence_matches -ne $true -or
                            [int]$Validation.observed_transition_count -lt [int]$Expectation.Cadence.minTransitions -or
                            [int]$Validation.observed_transition_count -gt ($AvailableReviewFrames.Count - 1) -or
                            [Math]::Abs([double]$Validation.observed_cadence_seconds - $ExpectedCadence) -gt $CadenceTolerance) {
                            $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not prove the declared alternation/cadence contract."
                            break
                        }
                    }
                    elseif ($CadenceMode -eq "steady" -and $Validation.cadence_matches -ne $true) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not prove the declared steady-state cadence contract."
                        break
                    }

                    $ExpectedDirection = [string]$Expectation.Scrolling.direction
                    if ($ExpectedDirection -ne "none" -and
                        ($Validation.direction_matches -ne $true -or [string]$Validation.observed_direction -cne $ExpectedDirection)) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not prove $ExpectedDirection scrolling."
                        break
                    }
                    if ([bool]$Expectation.Scrolling.continuityRequired -and $Validation.continuity_matches -ne $true) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not prove continuous motion/state changes."
                        break
                    }
                    if ([bool]$Expectation.Scrolling.noStaleContent -and $Validation.stale_content_observed -ne $false) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' showed or could not exclude stale content."
                        break
                    }

                    if (@($Expectation.KeyFrames).Count -gt 0) {
                        $KeyFrameValidation = @($Validation.key_frame_validation)
                        if ($Validation.key_frames_match -ne $true -or
                            $KeyFrameValidation.Count -ne @($Expectation.KeyFrames).Count) {
                            $PassProblem = "PASS was rejected because '$($Expectation.Video)' did not exactly cover every key-frame expectation."
                            break
                        }
                        foreach ($KeyFrame in @($Expectation.KeyFrames)) {
                            $KeyMatches = @($KeyFrameValidation | Where-Object { $_.name -ceq [string]$KeyFrame.name })
                            if ($KeyMatches.Count -ne 1 -or $KeyMatches[0].status -ne "match" -or
                                $AvailableReviewFrames -cnotcontains [string]$KeyMatches[0].evidence_frame -or
                                $KeyMatches[0].layout_matches -ne $true -or
                                @($KeyMatches[0].forbidden_observed).Count -ne 0 -or
                                [string]::IsNullOrWhiteSpace([string]$KeyMatches[0].observed)) {
                                $PassProblem = "PASS was rejected because '$($Expectation.Video)' key frame '$($KeyFrame.name)' was not an exact match."
                                break
                            }
                            $ExpectedRows = @($KeyFrame.requiredRows)
                            $ObservedRows = @($KeyMatches[0].observed_rows)
                            if ($ExpectedRows.Count -ne $ObservedRows.Count) {
                                $PassProblem = "PASS was rejected because '$($Expectation.Video)' key frame '$($KeyFrame.name)' reported the wrong row count."
                                break
                            }
                            for ($RowIndex = 0; $RowIndex -lt $ExpectedRows.Count; $RowIndex++) {
                                if ([string]$ObservedRows[$RowIndex] -cne [string]$ExpectedRows[$RowIndex]) {
                                    $PassProblem = "PASS was rejected because '$($Expectation.Video)' key frame '$($KeyFrame.name)' row $($RowIndex + 1) was not exact."
                                    break
                                }
                            }
                            if (-not [string]::IsNullOrWhiteSpace($PassProblem)) {
                                break
                            }
                        }
                        if (-not [string]::IsNullOrWhiteSpace($PassProblem)) {
                            break
                        }
                    }

                    if (@($Validation.forbidden_observed).Count -ne 0 -or
                        [string]::IsNullOrWhiteSpace([string]$Validation.observed)) {
                        $PassProblem = "PASS was rejected because '$($Expectation.Video)' contained forbidden material or lacked a concrete dynamic observation."
                        break
                    }
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($PassProblem)) {
            $FinalStatus = "PASS"
            $FinalReason = $Result.summary
            break
        }

        Write-Warning $PassProblem
        $LatestEvidencePrompt = $PassProblem
        $LatestImages = @()
        if ($Iteration -eq $MaxIterations) {
            $FinalStatus = "HUMAN REVIEW BOUNDARY"
            $FinalReason = "$PassProblem The bounded Codex retry limit was reached."
            break
        }
        continue
    }

    if ($Iteration -eq $MaxIterations) {
        $FinalStatus = "HUMAN REVIEW BOUNDARY"
        $FinalReason = "Codex requested another HIL cycle after the bounded retry limit was reached."
        break
    }

    $SelectedHilScript = $Result.hil_script
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredHilScript)) {
        $SelectedHilScript = $ConfiguredHilScript
    }

    $CycleDirectory = Join-Path $StateDirectory ("cycle-{0:D2}" -f $Iteration)
    $CaptureDirectory = Join-Path $CycleDirectory "captures"
    $CompileLog = Join-Path $CycleDirectory "compile-all.log"
    $HilLog = Join-Path $CycleDirectory "hil.log"
    $EvidencePath = Join-Path $CycleDirectory "evidence.json"
    New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null

    $CompileExitCode = -1
    $HilExitCode = -1
    $RunnerProblem = ""
    try {
        $FocusedHilPath = Resolve-SafeHilScript -WorkingTree $WorktreePath -RelativePath $SelectedHilScript
        $CompileAllPath = Join-Path $WorktreePath "hil\compile-all.ps1"
        if (-not (Test-Path -LiteralPath $CompileAllPath -PathType Leaf)) {
            throw "Compile-all script was not found: $CompileAllPath"
        }
        if (-not (Test-Path -LiteralPath $FocusedHilPath -PathType Leaf)) {
            throw "Focused HIL script was not found: $FocusedHilPath"
        }

        Write-Host ""
        Write-Host "=== EXTERNAL COMPILE + HIL CYCLE $Iteration ==="
        Write-Host "Compile: $CompileAllPath"
        $CompileExitCode = Invoke-LoggedPowerShellScript `
            -ScriptPath $CompileAllPath `
            -Arguments @("-FQBN", $FQBN) `
            -LogPath $CompileLog

        if ($CompileExitCode -eq 0) {
            $PreviousVideoDevice = $env:GU7003_HIL_VIDEO_DEVICE
            $PreviousCrop = $env:GU7003_HIL_CROP
            try {
                $env:GU7003_HIL_VIDEO_DEVICE = $VideoDevice
                $env:GU7003_HIL_CROP = $Crop
                Write-Host "Focused HIL: $FocusedHilPath"
                $HilExitCode = Invoke-LoggedPowerShellScript `
                    -ScriptPath $FocusedHilPath `
                    -Arguments @("-FQBN", $FQBN, "-Port", $Port, "-CaptureDirectory", $CaptureDirectory) `
                    -LogPath $HilLog
            }
            finally {
                if ($null -eq $PreviousVideoDevice) {
                    Remove-Item Env:GU7003_HIL_VIDEO_DEVICE -ErrorAction SilentlyContinue
                }
                else {
                    $env:GU7003_HIL_VIDEO_DEVICE = $PreviousVideoDevice
                }
                if ($null -eq $PreviousCrop) {
                    Remove-Item Env:GU7003_HIL_CROP -ErrorAction SilentlyContinue
                }
                else {
                    $env:GU7003_HIL_CROP = $PreviousCrop
                }
            }
        }
        else {
            $RunnerProblem = "Focused hardware execution was skipped because compile-all failed."
        }
    }
    catch {
        $RunnerProblem = $_.Exception.Message
        $RunnerProblem | Set-Content -LiteralPath $HilLog
    }

    $Images = @(
        Get-ChildItem -LiteralPath $CaptureDirectory -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { @(".jpg", ".jpeg", ".png") -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object FullName |
            Select-Object -ExpandProperty FullName
    )
    $Videos = @(
        Get-ChildItem -LiteralPath $CaptureDirectory -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { @(".mkv", ".mp4", ".mov", ".avi", ".webm") -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object FullName |
            Select-Object -ExpandProperty FullName
    )
    $VisualExpectationsPath = Join-Path $CaptureDirectory "visual-expectations.json"
    $VisualExpectations = @()
    $VisualExpectationProblem = ""
    try {
        $VisualExpectations = @(Read-VisualExpectations -Path $VisualExpectationsPath -Images $Images)
        if ($RequireVisualExpectations -and $VisualExpectations.Count -eq 0) {
            throw "This scenario requires $VisualExpectationsPath."
        }
    }
    catch {
        $VisualExpectationProblem = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($RunnerProblem)) {
            $RunnerProblem = $VisualExpectationProblem
        }
        else {
            $RunnerProblem = "$RunnerProblem $VisualExpectationProblem"
        }
        $HilExitCode = -1
    }

    $VideoExpectationsPath = Join-Path $CaptureDirectory "video-expectations.json"
    $VideoExpectations = @()
    $VideoExpectationProblem = ""
    try {
        $VideoExpectations = @(Read-VideoExpectations -Path $VideoExpectationsPath -Videos $Videos)
        if ($EvidenceMode -in @("video", "mixed") -and $VideoExpectations.Count -eq 0) {
            throw "This scenario requires $VideoExpectationsPath."
        }
    }
    catch {
        $VideoExpectationProblem = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($RunnerProblem)) {
            $RunnerProblem = $VideoExpectationProblem
        }
        else {
            $RunnerProblem = "$RunnerProblem $VideoExpectationProblem"
        }
        $HilExitCode = -1
    }

    $VideoEvidence = @()
    $VideoReviewImages = @()
    if ([string]::IsNullOrWhiteSpace($VideoExpectationProblem)) {
        $PrepareVideoEvidencePath = Join-Path $PSScriptRoot "prepare-video-evidence.ps1"
        foreach ($Video in $Videos) {
            $VideoName = [System.IO.Path]::GetFileName($Video)
            $MatchingExpectation = @($VideoExpectations | Where-Object { $_.Video -eq $VideoName })
            $SamplesPerSecond = 2.0
            $MaximumFrames = 24
            $AdditionalTimestamps = @()
            if ($MatchingExpectation.Count -eq 1) {
                $SamplesPerSecond = [double]$MatchingExpectation[0].ReviewFramesPerSecond
                $MaximumFrames = [int]$MatchingExpectation[0].MaximumReviewFrames
                foreach ($KeyFrame in @($MatchingExpectation[0].KeyFrames)) {
                    if ($KeyFrame.PSObject.Properties.Name -contains "atSeconds") {
                        $AdditionalTimestamps += [double]$KeyFrame.atSeconds
                    }
                    elseif ([string]$KeyFrame.position -eq "start") {
                        $AdditionalTimestamps += 0.0
                    }
                }
            }

            $SafeVideoName = [System.IO.Path]::GetFileNameWithoutExtension($VideoName)
            $ReviewDirectory = Join-Path (Join-Path $CycleDirectory "video-review") $SafeVideoName
            $ReviewLog = Join-Path $CycleDirectory "video-review-$SafeVideoName.log"
            $InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
            $PrepareArguments = @(
                "-Video", $Video,
                "-OutputDirectory", $ReviewDirectory,
                "-SamplesPerSecond", $SamplesPerSecond.ToString($InvariantCulture),
                "-MaximumFrames", ([string]$MaximumFrames)
            )
            if ($AdditionalTimestamps.Count -gt 0) {
                $AdditionalCsv = @($AdditionalTimestamps | ForEach-Object { $_.ToString("0.######", $InvariantCulture) }) -join ","
                $PrepareArguments += @("-AdditionalTimestampsCsv", $AdditionalCsv)
            }

            $PrepareExitCode = Invoke-LoggedPowerShellScript `
                -ScriptPath $PrepareVideoEvidencePath `
                -Arguments $PrepareArguments `
                -LogPath $ReviewLog
            if ($PrepareExitCode -ne 0) {
                $RunnerProblem = "$RunnerProblem Video evidence preparation failed for '$VideoName' with exit code $PrepareExitCode.".Trim()
                $HilExitCode = -1
                continue
            }

            $MetadataPath = Join-Path $ReviewDirectory "video-metadata.json"
            if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
                $RunnerProblem = "$RunnerProblem Video metadata was not created for '$VideoName'.".Trim()
                $HilExitCode = -1
                continue
            }
            $Metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
            $ReviewImages = @($Metadata.samples | Select-Object -ExpandProperty imagePath)
            $VideoReviewImages += $ReviewImages
            $VideoEvidence += [pscustomobject]@{
                Video = $VideoName
                VideoPath = $Video
                MetadataPath = $MetadataPath
                Metadata = $Metadata
                ReviewImages = $ReviewImages
                ReviewLog = $ReviewLog
            }
        }
    }
    $TestedFingerprint = Get-WorktreeFingerprint -WorkingTree $WorktreePath
    $LatestEvidence = [pscustomobject]@{
        Iteration = $Iteration
        HilScript = $SelectedHilScript
        CompileExitCode = $CompileExitCode
        HilExitCode = $HilExitCode
        RunnerProblem = $RunnerProblem
        ExpectedDisplay = @($Result.expected_display)
        VisualExpectations = $VisualExpectations
        VisualExpectationsPath = $VisualExpectationsPath
        Images = $Images
        VideoExpectations = $VideoExpectations
        VideoExpectationsPath = $VideoExpectationsPath
        Videos = $Videos
        VideoEvidence = $VideoEvidence
        VideoReviewImages = $VideoReviewImages
        TestedFingerprint = $TestedFingerprint
        CompileLog = $CompileLog
        HilLog = $HilLog
    }
    $LatestEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath

    $VisualExpectationsPrompt = "No test-owned exact visual expectations were supplied."
    if ($VisualExpectations.Count -gt 0) {
        $VisualExpectationsPrompt = $VisualExpectations | ConvertTo-Json -Depth 5
    }

    $VideoExpectationsPrompt = "No test-owned dynamic video expectations were supplied."
    if ($VideoExpectations.Count -gt 0) {
        $VideoExpectationsPrompt = $VideoExpectations | ConvertTo-Json -Depth 8
    }
    $VideoEvidencePrompt = "No prepared video evidence exists."
    if ($VideoEvidence.Count -gt 0) {
        $VideoEvidencePrompt = $VideoEvidence | ConvertTo-Json -Depth 8
    }

    $LatestEvidencePrompt = @"
Controller evidence file: $EvidencePath
Focused HIL script: $SelectedHilScript
Compile-all exit code: $CompileExitCode
Focused HIL exit code: $HilExitCode
Runner problem: $RunnerProblem
Codex-authored general display/state transitions:
- $(@($Result.expected_display) -join "`n- ")
Authoritative test-owned exact visual expectations:
$VisualExpectationsPrompt
Authoritative test-owned dynamic video expectations:
$VideoExpectationsPrompt
Prepared video evidence (original clips retained at videoPath; ordered timestamped frame paths are attached):
$VideoEvidencePrompt
Static camera images attached to this iteration: $($Images.Count)
Timestamped video-review frames attached to this iteration: $($VideoReviewImages.Count)

Compile log:
$(Get-LogExcerpt -Path $CompileLog)

Focused HIL log:
$(Get-LogExcerpt -Path $HilLog)
"@
    $LatestImages = @($Images) + @($VideoReviewImages)
}

if ([string]::IsNullOrWhiteSpace($FinalStatus)) {
    $FinalStatus = "HUMAN REVIEW BOUNDARY"
    $FinalReason = "The controller stopped without a terminal result. Review the preserved worktree and evidence."
}

Write-ReviewSummary `
    -Status $FinalStatus `
    -Reason $FinalReason `
    -Branch $BranchName `
    -WorkingTree $WorktreePath `
    -Artifacts $StateDirectory
