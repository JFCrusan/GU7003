[CmdletBinding()]
param(
    [string]$FQBN = "arduino:avr:diecimila:cpu=atmega328",
    [string]$BuildRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "GU7003-ArduinoBuild\compile-all")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ExamplesRoot = Join-Path $RepoRoot "examples"
$ArduinoCliCommand = Get-Command arduino-cli -ErrorAction SilentlyContinue
$ArduinoCli = if ($ArduinoCliCommand) { $ArduinoCliCommand.Source } else { $null }

if (-not $ArduinoCli) {
    $ArduinoCliCandidates = @(
        "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
    )

    $ArduinoCli = $ArduinoCliCandidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

if (-not $ArduinoCli) {
    throw "arduino-cli was not found. Install it or add it to PATH."
}

if (-not (Test-Path -LiteralPath $ExamplesRoot -PathType Container)) {
    throw "Examples directory was not found: $ExamplesRoot"
}

$Examples = @(Get-ChildItem -LiteralPath $ExamplesRoot -Directory | Sort-Object Name)
if ($Examples.Count -eq 0) {
    throw "No example directories were found under $ExamplesRoot"
}

Write-Host "=== GU7003 COMPILE ALL ==="
Write-Host "Repository: $RepoRoot"
Write-Host "Library:    $RepoRoot"
Write-Host "Target:     $FQBN"
Write-Host "Examples:   $($Examples.Count)"

$Passed = 0
foreach ($Example in $Examples) {
    Write-Host ""
    Write-Host "Compiling $($Example.Name)..."
    $BuildPath = Join-Path $BuildRoot $Example.Name
    New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
    & $ArduinoCli compile --fqbn $FQBN --library $RepoRoot --build-path $BuildPath $Example.FullName

    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL: $($Example.Name)" -ForegroundColor Red
        throw "Compilation stopped after $Passed of $($Examples.Count) examples passed."
    }

    $Passed++
    Write-Host "PASS: $($Example.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "COMPILE ALL PASS: $Passed/$($Examples.Count) examples" -ForegroundColor Green
