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
- Return pass only after reviewing the latest controller log and every attached image, only when they visibly prove the task, and only if you made no changes after that evidence.
- A capture script exiting zero proves capture, not visual correctness. Inspect the pixels and expected state transitions.
- Return human_review only for a genuine boundary that cannot be resolved safely in another automated iteration; explain it precisely.
- Use the required JSON schema fields. Use an empty string/array where a field is not applicable.

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
        elseif (@($LatestEvidence.Images).Count -eq 0) {
            $PassProblem = "PASS was rejected because the latest HIL run produced no camera images."
        }
        elseif ((Get-WorktreeFingerprint -WorkingTree $WorktreePath) -ne $LatestEvidence.TestedFingerprint) {
            $PassProblem = "PASS was rejected because files changed after the latest HIL run. Another HIL cycle is required."
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
    $TestedFingerprint = Get-WorktreeFingerprint -WorkingTree $WorktreePath
    $LatestEvidence = [pscustomobject]@{
        Iteration = $Iteration
        HilScript = $SelectedHilScript
        CompileExitCode = $CompileExitCode
        HilExitCode = $HilExitCode
        RunnerProblem = $RunnerProblem
        ExpectedDisplay = @($Result.expected_display)
        Images = $Images
        TestedFingerprint = $TestedFingerprint
        CompileLog = $CompileLog
        HilLog = $HilLog
    }
    $LatestEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath

    $LatestEvidencePrompt = @"
Controller evidence file: $EvidencePath
Focused HIL script: $SelectedHilScript
Compile-all exit code: $CompileExitCode
Focused HIL exit code: $HilExitCode
Runner problem: $RunnerProblem
Expected display/state transitions:
- $(@($Result.expected_display) -join "`n- ")
Camera images attached to this iteration: $($Images.Count)

Compile log:
$(Get-LogExcerpt -Path $CompileLog)

Focused HIL log:
$(Get-LogExcerpt -Path $HilLog)
"@
    $LatestImages = $Images
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
