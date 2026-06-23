# Setup script - run once before launching the sandbox.
#   1. Resolves the default toolchain + any requested profiles into scripts/tools.json
#   2. Generates sandbox.wsb from the template (networking/clipboard toggled for -Offline)
#
# Examples:
#   .\setup.ps1                                # default dev toolchain
#   .\setup.ps1 -Profiles datascience,web      # default + extra profiles
#   .\setup.ps1 -Profiles security -Offline    # hardened, network-disabled box (see README)
#
# Available profiles: datascience, devops, database, web, security, pentest

param(
    [string[]]$Profiles = @(),
    [switch]$Offline
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path "$PSScriptRoot\tools.json")) {
    Write-Host "ERROR: tools.json not found in $PSScriptRoot" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path "$PSScriptRoot\scripts")) {
    Write-Host "ERROR: scripts directory not found in $PSScriptRoot" -ForegroundColor Red
    exit 1
}

$template = "$PSScriptRoot\sandbox.wsb.template"
if (-not (Test-Path $template)) {
    Write-Host "ERROR: template not found: $template" -ForegroundColor Red
    exit 1
}

$config = Get-Content -Raw -Path "$PSScriptRoot\tools.json" | ConvertFrom-Json

if (-not $config.PSObject.Properties['default']) {
    Write-Host "ERROR: tools.json is missing the 'default' tool array." -ForegroundColor Red
    exit 1
}
if (-not $config.PSObject.Properties['profiles']) {
    Write-Host "ERROR: tools.json is missing the 'profiles' object." -ForegroundColor Red
    exit 1
}

$requestedProfiles = $Profiles |
    ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ } |
    Select-Object -Unique

# Default toolchain first, then each requested profile appended.
$selected = [System.Collections.Generic.List[object]]::new()
foreach ($t in $config.default) { $selected.Add($t) }

# Validate names explicitly ($config.profiles.$name returns member values like Count, not $null)
$validProfiles = $config.profiles.PSObject.Properties.Name
foreach ($name in $requestedProfiles) {
    if ($validProfiles -notcontains $name) {
        Write-Host "ERROR: unknown profile '$name'. Available: $($validProfiles -join ', ')" -ForegroundColor Red
        exit 1
    }
    foreach ($t in $config.profiles.$name) { $selected.Add($t) }
}

# De-duplicate by wingetId (fall back to name for manual tools).
$seen = [System.Collections.Generic.HashSet[string]]::new()
$resolved = foreach ($t in $selected) {
    $key = if ($t.wingetId) { $t.wingetId } else { $t.name }
    if ($seen.Add($key)) { $t }
}

# Write UTF-8 WITHOUT BOM (Windows PowerShell 5.1's "-Encoding UTF8" adds a BOM, which can
# break the .wsb parser; .NET's WriteAllText with UTF8Encoding($false) is BOM-less everywhere).
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

$resolvedJson = @{ tools = @($resolved) } | ConvertTo-Json -Depth 6
$toolsOut = [System.IO.Path]::Combine($PSScriptRoot, 'scripts', 'tools.json')
[System.IO.File]::WriteAllText($toolsOut, $resolvedJson, $utf8NoBom)

# XML-escape the host path so a clone path containing '&' does not corrupt the .wsb.
# Offline mode disables networking + clipboard and passes -Offline to the launcher.
$escapedRoot = [System.Security.SecurityElement]::Escape($PSScriptRoot)
$networking = if ($Offline) { 'Disable' } else { 'Enable' }
$clipboard = if ($Offline) { 'Disable' } else { 'Enable' }
$launchArgs = if ($Offline) { ' -Offline' } else { '' }
$wsbContent = (Get-Content $template -Raw).Replace('__SANDBOX__', $escapedRoot)
$wsbContent = $wsbContent.Replace('__NETWORKING__', $networking)
$wsbContent = $wsbContent.Replace('__CLIPBOARD__', $clipboard)
$wsbContent = $wsbContent.Replace('__LAUNCHARGS__', $launchArgs)
$wsbOut = [System.IO.Path]::Combine($PSScriptRoot, 'sandbox.wsb')
[System.IO.File]::WriteAllText($wsbOut, $wsbContent, $utf8NoBom)

$profileLabel = if ($requestedProfiles) { "default + $($requestedProfiles -join ', ')" } else { "default" }
$mode = if ($Offline) { " [offline / network-disabled]" } else { "" }
Write-Host "Ready: $(@($resolved).Count) tools ($profileLabel)$mode. Launch with: start sandbox.wsb" -ForegroundColor Green
