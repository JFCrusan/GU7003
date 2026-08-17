[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ControllerPath = Join-Path $PSScriptRoot "codex-hil.ps1"

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing $Description. Pattern: $Pattern`nOutput:`n$Text"
    }
}

function Test-PlanProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$ReasoningEffort,
        [Parameter(Mandatory = $true)][int]$MaxIterations,
        [Parameter(Mandatory = $true)][string]$ValidationScope
    )

    $Output = @(
        & $ControllerPath `
            -Feature "profile-$Profile-dry-run" `
            -Task "Verify $Profile controller profile resolution only." `
            -Profile $Profile `
            -Model "profile-test-model" `
            -PlanOnly *>&1
    ) -join "`n"

    Assert-Match -Text $Output -Pattern "(?m)^Profile:\s+$Profile$" -Description "$Profile profile banner"
    Assert-Match -Text $Output -Pattern "(?m)^Codex model:\s+profile-test-model$" -Description "effective model banner"
    Assert-Match -Text $Output -Pattern "(?m)^Reasoning effort:\s+$ReasoningEffort$" -Description "$Profile reasoning banner"
    Assert-Match -Text $Output -Pattern "(?m)^Validation scope:\s+$ValidationScope$" -Description "$Profile validation banner"
    Assert-Match -Text $Output -Pattern "(?m)^Maximum iterations:\s+$MaxIterations$" -Description "$Profile iteration limit"
    Assert-Match -Text $Output -Pattern "(?m)^Codex invocation:.*--model profile-test-model.*--config model_reasoning_effort='$ReasoningEffort'.*--strict-config.*--sandbox workspace-write.*--ask-for-approval never" -Description "$Profile Codex overrides and safeguards"
    Assert-Match -Text $Output -Pattern "PLAN ONLY: no branch, worktree, Codex, compile, upload, or camera action was performed\." -Description "dry-run boundary"
}

$DefaultOutput = @(
    & $ControllerPath `
        -Feature "profile-default-dry-run" `
        -Task "Verify the default controller profile only." `
        -Model "profile-test-model" `
        -PlanOnly *>&1
) -join "`n"
Assert-Match -Text $DefaultOutput -Pattern "(?m)^Profile:\s+fast$" -Description "default fast profile"
Assert-Match -Text $DefaultOutput -Pattern "(?m)^Reasoning effort:\s+low$" -Description "default low reasoning"
Assert-Match -Text $DefaultOutput -Pattern "(?m)^Maximum iterations:\s+2$" -Description "default fast iteration limit"
Assert-Match -Text $DefaultOutput -Pattern "(?m)^Codex invocation:.*--config model_reasoning_effort='low'.*--strict-config" -Description "default low reasoning CLI override"

Test-PlanProfile -Profile "fast" -ReasoningEffort "low" -MaxIterations 2 -ValidationScope "focused"
Test-PlanProfile -Profile "normal" -ReasoningEffort "medium" -MaxIterations 5 -ValidationScope "focused"
Test-PlanProfile -Profile "release" -ReasoningEffort "high" -MaxIterations 8 -ValidationScope "full"

$FastLimitError = ""
try {
    & $ControllerPath `
        -Feature "profile-fast-limit" `
        -Task "Verify the fast iteration cap only." `
        -Profile "fast" `
        -MaxIterations 3 `
        -Model "profile-test-model" `
        -PlanOnly *>&1 | Out-Null
}
catch {
    $FastLimitError = $_.Exception.Message
}
Assert-Match -Text $FastLimitError -Pattern "fast profile permits at most 2 Codex iterations" -Description "fast iteration hard limit"

$ControllerText = Get-Content -LiteralPath $ControllerPath -Raw
$UnsafeControllerText = $ControllerText.Replace('ReasoningEffort = "low"', 'ReasoningEffort = "high"')
if ($UnsafeControllerText -eq $ControllerText) {
    throw "Unable to create the high-reasoning guard test fixture."
}

$TemporaryController = Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-codex-hil-unsafe-$PID.ps1"
try {
    Set-Content -LiteralPath $TemporaryController -Value $UnsafeControllerText -NoNewline
    $PowerShellExecutable = (Get-Process -Id $PID).Path
    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $GuardOutput = @(
            & $PowerShellExecutable `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $TemporaryController `
                -Feature "profile-fast-guard" `
                -Task "Verify the fast reasoning guard only." `
                -Profile "fast" `
                -Model "profile-test-model" `
                -PlanOnly 2>&1
        ) -join "`n"
        $GuardExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
}
finally {
    Remove-Item -LiteralPath $TemporaryController -Force -ErrorAction SilentlyContinue
}

if ($GuardExitCode -eq 0) {
    throw "The mutated fast/high policy did not fail. Output:`n$GuardOutput"
}
Assert-Match -Text $GuardOutput -Pattern "fast profile resolved to prohibited reasoning effort 'high'" -Description "fast/high hard guard"
if ($GuardOutput -match "Codex invocation:") {
    throw "The fast/high guard emitted a Codex invocation before aborting. Output:`n$GuardOutput"
}

Write-Host "PASS: Codex HIL profile/config checks"
