# Clones the repo into the user profile and runs the default setup from PowerShell:
#   irm https://raw.githubusercontent.com/26zl/windows-sandbox-lab/main/install.ps1 | iex

$ErrorActionPreference = "Stop"
$repo = "26zl/windows-sandbox-lab"
$branch = "main"
$name = ($repo -split '/')[-1]
$dest = Join-Path $env:USERPROFILE $name

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
    $expanded = Join-Path $env:TEMP "$name-$branch"
    Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/$branch.zip" -OutFile $zip -UseBasicParsing
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
