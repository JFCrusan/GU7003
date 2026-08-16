# Codex HIL controller

`hil/codex-hil.ps1` is the Windows bench controller for bounded Codex implementation and hardware-in-the-loop cycles.

The controller keeps the two trust boundaries separate:

1. Codex runs with workspace-write access only in the feature worktree. It may edit, inspect diffs, and run safe non-hardware checks.
2. The parent PowerShell controller runs `hil/compile-all.ps1`, the focused HIL script, Arduino upload, waits, and C920 capture outside the Codex sandbox.
3. The controller saves logs, snapshots, and original videos under `%TEMP%\GU7003-HIL\Controller`. Snapshots are attached directly. Each video is retained and also converted into a bounded ordered set of timestamped frames plus FFprobe timing metadata for the next Codex iteration.
4. Codex either fixes the implementation and requests another HIL cycle, returns `pass` after validating every declared static and dynamic requirement against fresh evidence, or reports a precise human-review boundary.

No iteration commits, merges, pushes, resets, cleans, or removes a worktree. The controller also rejects `pass` if the feature files changed after the latest HIL run.

## Bench defaults

- Board: Arduino Duemilanove / ATmega328P
- FQBN: `arduino:avr:diecimila:cpu=atmega328`
- Port: `COM3`
- Camera: `HD Pro Webcam C920`
- Crop: `crop=390:115:135:120`

All can be overridden with controller parameters. The camera and crop are passed through controller-scoped environment variables, so feature HIL scripts can call either `capture-vfd.ps1` or `capture-vfd-video.ps1` without duplicating bench calibration. Video clips default to 10 seconds, 30 fps, lossless Matroska/FFV1, and the exact calibrated `crop=390:115:135:120`; the 4:4:4 pixel format preserves the crop's odd 115-pixel height.

## Static and dynamic scenario modes

A scenario may declare one evidence mode:

```json
{
  "hilScript": "hil/test-feature.ps1",
  "evidenceMode": "snapshot",
  "requireVisualExpectations": true
}
```

- `snapshot` (the backward-compatible default) requires at least one camera image and supports exact `visual-expectations.json` validation.
- `video` requires at least one captured video and a valid `video-expectations.json` contract.
- `mixed` requires both snapshot and video evidence. Any supplied static or dynamic expectation is authoritative and must pass.

The existing snapshot workflow and exact row/layout checks are unchanged.

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

It should compile the focused sketch, upload it, wait for each observable state, save snapshots and/or videos beneath `CaptureDirectory`, write the applicable test-owned expectation manifest, throw on mechanical failures, and print the artifact paths. Supported video extensions are `.mkv`, `.mp4`, `.mov`, `.avi`, and `.webm`; `capture-vfd-video.ps1` intentionally produces lossless `.mkv`. Semantic display correctness is decided from the evidence contract, not by a zero process exit code alone.

A feature test can make visual acceptance exact by writing `visual-expectations.json` beneath `CaptureDirectory`. The file uses this shape:

```json
{
  "version": 1,
  "captures": [
    {
      "image": "state-name.jpg",
      "requiredRows": ["EXACT TOP TEXT", "EXACT BOTTOM TEXT"],
      "layout": "Describe required placement and wrapping.",
      "forbidden": ["Describe stale, joined, wrapped, or extra content that must reject the frame."]
    }
  ]
}
```

The controller validates that each manifest entry names exactly one captured image and sends the test-owned contract to the visual reviewer. When a scenario sets `requireVisualExpectations` to `true`, missing or invalid expectations fail the HIL cycle. Codex must return a structured `visual_validation` record for every expected image, including verbatim `observed_rows`, a placement/wrapping verdict, and any forbidden content it sees. The controller compares those observed rows to `requiredRows` exactly; any missing, mismatched, joined, wrapped, forbidden, or unreviewable frame rejects `pass`.

### Dynamic video expectations

A video test writes `video-expectations.json` beneath `CaptureDirectory`. Every field is explicit so dynamic review cannot collapse into a permissive "looks okay" verdict:

```json
{
  "version": 1,
  "videos": [
    {
      "video": "scroll-demo.mkv",
      "duration": { "minSeconds": 9.5, "maxSeconds": 11.0 },
      "states": [
        {
          "name": "message-present",
          "description": "The expected message is visibly traversing the display.",
          "minOccurrences": 3
        }
      ],
      "cadence": {
        "mode": "none",
        "states": [],
        "expectedStateSeconds": 0,
        "toleranceSeconds": 0,
        "minTransitions": 0
      },
      "scrolling": {
        "direction": "left",
        "continuityRequired": true,
        "noStaleContent": true
      },
      "keyFrames": [
        {
          "name": "start",
          "position": "start",
          "requiredRows": ["SCROLL START"],
          "layout": "One unwrapped row beginning at the left edge.",
          "forbidden": ["Old text or a partially cleared column."]
        },
        {
          "name": "finish",
          "position": "end",
          "requiredRows": ["SCROLL DONE"],
          "layout": "One steady, unwrapped row after scrolling completes.",
          "forbidden": ["Any remaining scroll fragment."]
        }
      ],
      "forbidden": ["Reverse motion, jumps, blank gaps, or frozen/stale columns."],
      "review": { "framesPerSecond": 4, "maxFrames": 48 }
    }
  ]
}
```

`cadence.mode` is `none`, `steady`, or `alternating`. An alternating contract names at least two declared states and specifies expected seconds per state, tolerance, and minimum transitions. `scrolling.direction` is `none`, `left`, `right`, `up`, or `down`. A key frame uses exactly one locator: `position` (`start`/`end`) or `atSeconds`.

FFprobe duration is checked mechanically against the declared range. The contract also rejects sampling settings that would hit `maxFrames` before the maximum duration or sample alternating states fewer than twice per expected state. The reviewer must then return one strict `dynamic_validation` record per video with valid evidence-frame names and occurrence counts for states, measured cadence and transition count, direction/continuity/stale-content verdicts, and exact per-key-frame row/layout results tied to a timestamped frame. Any absent/unreviewable state, invented frame reference, out-of-tolerance cadence, insufficient transitions, wrong direction, discontinuity, stale content, key-frame mismatch, or forbidden content rejects `pass`.

## Codex video input fallback

Current Codex models support image input but not direct video input. The controller therefore never discards the source clip: it stores the original beside the HIL evidence, probes duration/frame rate/dimensions/codec, and extracts 2-48 ordered PNG frames named with their timestamps. Each video contract controls review sampling from 0.25-8 fps with a hard 48-frame bound; explicit timestamped key frames are added automatically when capacity allows. The metadata and frames are passed to Codex through the supported image interface.

This fallback makes timing review discrete. Set `review.framesPerSecond` high enough to resolve the declared cadence or motion; for example, 2 fps is suitable for approximately one-second blink states, while smooth scrolling generally warrants 4-8 fps. If the bounded evidence cannot establish a requirement, the reviewer must return `unreviewable`, not `match`.

## Non-destructive validation and native-blink demo

The media pipeline has a camera-free self-test:

```powershell
.\hil\test-video-evidence.ps1
```

It generates a four-second alternating FFmpeg test clip at the calibrated 390x115 dimensions, retains the original video, probes it, extracts bounded timestamped frames, and asserts duration/dimensions/frame availability.

If the clean `C:\Projects\GU7003-native-blink` worktree and bench are available, this focused demo reuses its existing `BlinkValidation` sketch without editing that branch:

```powershell
.\hil\demo-native-blink-video.ps1 `
    -NativeBlinkWorktree C:\Projects\GU7003-native-blink `
    -Port COM3
```

The demo compiles/uploads the existing sketch, captures a 15-second C920 clip, and writes a strict Normal/Blank alternation contract. Run `prepare-video-evidence.ps1` against the resulting clip for a standalone inspection, or use the same capture/contract pattern in a controller-owned feature test.

Pass `-HilScript hil/test-name.ps1` to pin a specific focused test. A matching `hil/scenarios/<feature>.json` may also provide a default script and known starting context.

## Terminal states and safeguards

- `PASS`: the latest compile and focused HIL processes exited successfully; the scenario's required external snapshot/video capture exists; every supplied static and dynamic expectation has one exact matching reviewer record; mechanically measured video duration is in range; Codex inspected all bounded evidence; and the tested feature fingerprint still matches the worktree.
- `HUMAN REVIEW BOUNDARY`: the retry limit was reached, hardware/evidence is genuinely ambiguous or unavailable, the Codex process failed, structured output was invalid, or protected Git state changed.

At either boundary, the controller prints the feature branch, worktree, final Git status, and evidence directory. Review and commit remain explicit human actions.
