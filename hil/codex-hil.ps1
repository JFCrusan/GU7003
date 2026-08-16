[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9._-]*$")]
    [string]$Feature,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Task,

    [ValidateRange(1, 50)]
    [int]$MaxIterations = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$RepoParent = Split-Path -Parent $RepoRoot
$RepoName = Split-Path -Leaf $RepoRoot
$WorktreeRoot = Join-Path $RepoParent "$RepoName-worktrees"
$WorktreePath = Join-Path $WorktreeRoot $Feature
$BranchName = "feature/$Feature"

$CurrentBranch = (& git -C $RepoRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine the current Git branch." }
if ($CurrentBranch -ne "main") {
    throw "codex-hil.ps1 must start from a main worktree; current branch is '$CurrentBranch'."
}

$Status = @(& git -C $RepoRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect the main working tree." }
if ($Status.Count -ne 0) {
    throw "The main working tree must be clean before starting feature automation."
}

& git -C $RepoRoot rev-parse --verify --quiet "main^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "The local main branch does not exist." }

& git -C $RepoRoot show-ref --verify --quiet "refs/heads/$BranchName"
$BranchCheck = $LASTEXITCODE
if ($BranchCheck -eq 0) { throw "Branch already exists: $BranchName" }
if ($BranchCheck -ne 1) { throw "Unable to check whether $BranchName exists." }

if (Test-Path -LiteralPath $WorktreePath) {
    throw "Worktree path already exists: $WorktreePath"
}

$CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
if (-not $CodexCommand) {
    throw "codex was not found. Install the Codex CLI or add it to PATH."
}

New-Item -ItemType Directory -Path $WorktreeRoot -Force | Out-Null

Write-Host "=== GU7003 CODEX HIL CONTROLLER ==="
Write-Host "Source:             $RepoRoot (clean main)"
Write-Host "Feature branch:     $BranchName"
Write-Host "Feature worktree:   $WorktreePath"
Write-Host "Maximum iterations: $MaxIterations"

& git -C $RepoRoot worktree add -b $BranchName $WorktreePath main
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create feature branch/worktree."
}

$Prompt = @"
You are implementing a feature in the GU7003 Arduino VFD library.

Task:
$Task

The controller already created branch $BranchName and worktree $WorktreePath from clean main.
Remain in that branch and worktree.

Requirements:
- Target hardware: Noritake GU112X16G-7003, 112x16 pixels.
- Target board: Arduino Duemilanove / ATmega328P.
- Hardware port: COM3.
- Implement the requested feature without regressing existing public behavior.
- Run hil/compile-all.ps1 so every example compiles.
- Create or run a focused feature-specific HIL test when physical validation applies.
- Upload to COM3, capture the display through hil/capture-vfd.ps1, and inspect the generated camera image or images yourself.
- Run git diff --check.
- Treat implement -> compile -> HIL -> image inspection as one iteration. Iterate on failures, using no more than $MaxIterations iterations.
- Never push, merge, or commit.
- Stop at a human review boundary when validation passes or safe progress is exhausted.

At the end report the branch/worktree, files changed, compile results, HIL and image-inspection results, remaining problems, final git status, and readiness for human review.
"@

& $CodexCommand.Source exec `
    --sandbox workspace-write `
    --cd $WorktreePath `
    $Prompt
$CodexExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "=== HUMAN REVIEW BOUNDARY ==="
Write-Host "Branch:   $BranchName"
Write-Host "Worktree: $WorktreePath"
& git -C $WorktreePath status --short --branch

if ($CodexExitCode -ne 0) {
    throw "codex exec exited with code $CodexExitCode. Review the worktree before continuing."
}

Write-Host "Codex completed without committing, merging, or pushing."
