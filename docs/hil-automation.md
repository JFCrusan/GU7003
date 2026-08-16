# Codex HIL controller

`hil/codex-hil.ps1` is the Windows bench controller for bounded Codex implementation and hardware-in-the-loop cycles.

The controller keeps the two trust boundaries separate:

1. Codex runs with workspace-write access only in the feature worktree. It may edit, inspect diffs, and run safe non-hardware checks.
2. The parent PowerShell controller runs `hil/compile-all.ps1`, the focused HIL script, Arduino upload, waits, and C920 capture outside the Codex sandbox.
3. The controller saves the logs and images under `%TEMP%\GU7003-HIL\Controller`, attaches the images to the next Codex iteration, and includes a bounded log excerpt in its prompt.
4. Codex either fixes the implementation and requests another HIL cycle, returns `pass` after visually validating fresh evidence, or reports a precise human-review boundary.

No iteration commits, merges, pushes, resets, cleans, or removes a worktree. The controller also rejects `pass` if the feature files changed after the latest HIL run.

## Bench defaults

- Board: Arduino Duemilanove / ATmega328P
- FQBN: `arduino:avr:diecimila:cpu=atmega328`
- Port: `COM3`
- Camera: `HD Pro Webcam C920`
- Crop: `crop=390:115:135:120`

All can be overridden with controller parameters. The camera and crop are passed to `capture-vfd.ps1` through controller-scoped environment variables, so feature HIL scripts can continue calling the capture script normally.

## Resume `feature/user-windows`

Run the controller from a clean `main` worktree after controller-v2 has been reviewed and integrated:

```powershell
.\hil\codex-hil.ps1 `
    -Feature user-windows `
    -Task "Finish user windows, including restoration of the base window after both user windows are cancelled." `
    -MaxIterations 5
```

The controller discovers and reuses the already registered `feature/user-windows` worktree, including its uncommitted changes. `hil/scenarios/user-windows.json` automatically selects `hil/test-user-windows.ps1` and supplies the known starting evidence: definition, selection, independent updates, compilation, and upload worked, but the final base-window-restoration capture failed.

The old feature worktree is never deleted or recreated. If its registered path or branch is inconsistent, the controller stops for human review.

## Start a new feature

```powershell
.\hil\codex-hil.ps1 `
    -Feature feature-name `
    -Task "Describe the feature and its observable HIL acceptance criteria." `
    -MaxIterations 5
```

For a new feature, the controller creates `feature/feature-name` and its worktree from clean local `main`. If the branch already has a registered worktree, that worktree is reused wherever it is located. If the branch exists without a worktree, the controller creates only the worktree.

Use `-PlanOnly` to verify branch/worktree discovery and bench settings without creating anything or running Codex, compilation, upload, or capture:

```powershell
.\hil\codex-hil.ps1 -Feature user-windows -Task "preflight" -PlanOnly
```

## Focused HIL script contract

Each hardware feature must provide a relative PowerShell script under the feature worktree. The script must accept:

```powershell
param(
    [string]$FQBN,
    [string]$Port,
    [string]$CaptureDirectory
)
```

It should compile the focused sketch, upload it, wait for each observable state, save every `.jpg`, `.jpeg`, or `.png` capture beneath `CaptureDirectory`, throw on mechanical failures, and print the capture paths. Semantic display correctness is decided by Codex from the attached images, not by a zero process exit code alone.

Pass `-HilScript hil/test-name.ps1` to pin a specific focused test. A matching `hil/scenarios/<feature>.json` may also provide a default script and known starting context.

## Terminal states and safeguards

- `PASS`: the latest compile and focused HIL processes exited successfully, at least one image was captured, Codex inspected the evidence, and the tested feature fingerprint still matches the worktree.
- `HUMAN REVIEW BOUNDARY`: the retry limit was reached, hardware/evidence is genuinely ambiguous or unavailable, the Codex process failed, structured output was invalid, or protected Git state changed.

At either boundary, the controller prints the feature branch, worktree, final Git status, and evidence directory. Review and commit remain explicit human actions.
