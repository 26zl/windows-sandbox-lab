# One-line bootstrap. Run in PowerShell:
#   irm https://raw.githubusercontent.com/26zl/windows-sandbox-lab/main/install.ps1 | iex
#
# Clones (or downloads) the repo to your user folder and runs setup.ps1 with the default
# profile. For extra profiles, clone manually and run e.g. .\setup.ps1 -Profiles security

$ErrorActionPreference = "Stop"
$repo = "26zl/windows-sandbox-lab"
$dest = Join-Path $env:USERPROFILE "windows-sandbox-lab"

function Move-ExistingDestination {
    if (-not (Test-Path $dest)) { return }

    $backup = "$dest.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item -Path $dest -Destination $backup -Force
    Write-Host "Existing folder moved to $backup" -ForegroundColor Yellow
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path "$dest\.git") {
        git -C $dest pull --ff-only --quiet
        if ($LASTEXITCODE -ne 0) { throw "git pull failed in $dest. Resolve local changes or clone manually." }
    }
    else {
        Move-ExistingDestination
        git clone --depth 1 "https://github.com/$repo.git" $dest
        if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
    }
}
else {
    $zip = Join-Path $env:TEMP "wsb-dev.zip"
    $expanded = Join-Path $env:TEMP "windows-sandbox-lab-main"
    Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
    Move-ExistingDestination
    if (Test-Path $expanded) { Remove-Item $expanded -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
    Move-Item $expanded $dest -Force
    Remove-Item $zip -Force
}

Set-Location $dest
Write-Host "Installed to $dest" -ForegroundColor Green
& "$dest\setup.ps1"
Write-Host "Now run:  start sandbox.wsb" -ForegroundColor Cyan
