# Setup script — run once before launching the sandbox.
# 1. Copies tools.json into scripts/ (sandbox needs it)
# 2. Generates sandbox.wsb from template

if (-not (Test-Path "$PSScriptRoot\tools.json")) {
    Write-Host "ERROR: tools.json not found in $PSScriptRoot" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path "$PSScriptRoot\sandbox.wsb.template")) {
    Write-Host "ERROR: sandbox.wsb.template not found in $PSScriptRoot" -ForegroundColor Red
    exit 1
}

Copy-Item -Path "$PSScriptRoot\tools.json" -Destination "$PSScriptRoot\scripts\tools.json" -Force

(Get-Content "$PSScriptRoot\sandbox.wsb.template").Replace('__SANDBOX__', $PSScriptRoot) |
Set-Content "$PSScriptRoot\sandbox.wsb"

Write-Host "Ready. Launch with: start sandbox.wsb" -ForegroundColor Green
