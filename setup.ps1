# Resolves tool profiles into scripts/tools.json and generates sandbox.wsb before launch.
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

$selected = [System.Collections.Generic.List[object]]::new()
foreach ($t in $config.default) { $selected.Add($t) }

# Validate requested profile names.
$validProfiles = $config.profiles.PSObject.Properties.Name
foreach ($name in $requestedProfiles) {
    if ($validProfiles -notcontains $name) {
        Write-Host "ERROR: unknown profile '$name'. Available: $($validProfiles -join ', ')" -ForegroundColor Red
        exit 1
    }
    foreach ($t in $config.profiles.$name) { $selected.Add($t) }
}

$seen = [System.Collections.Generic.HashSet[string]]::new()
$resolved = foreach ($t in $selected) {
    $key = if ($t.wingetId) { $t.wingetId } else { $t.name }
    if ($seen.Add($key)) { $t }
}

# Write BOM-less UTF-8 for the .wsb parser.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

$resolvedJson = @{ tools = @($resolved) } | ConvertTo-Json -Depth 6
$toolsOut = [System.IO.Path]::Combine($PSScriptRoot, 'scripts', 'tools.json')
[System.IO.File]::WriteAllText($toolsOut, $resolvedJson, $utf8NoBom)

# Generate sandbox settings and escape the host path for XML.
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
