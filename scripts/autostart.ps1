# Windows Sandbox auto-setup script
# Installs winget, then installs all enabled tools from tools.json

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$scriptDir = $PSScriptRoot
$logFile = Join-Path $env:TEMP "sandbox-install.log"
$setupErrors = 0

# Wait for network before starting (LogonCommand can run before network is ready)
$maxWait = 60
$waited = 0
while ($waited -lt $maxWait) {
    if (Test-Connection -ComputerName "github.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2
    $waited += 2
}
if ($waited -ge $maxWait) {
    Write-SetupLog "FAIL" "Network not available after ${maxWait}s — cannot continue"
    exit 1
}
Write-SetupLog "OK" "Network available"

function Write-SetupLog {
    param(
        [string]$Level,
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    switch ($Level) {
        "OK" { Write-Host $line -ForegroundColor Green }
        "FAIL" { Write-Host $line -ForegroundColor Red }
        "WARN" { Write-Host $line -ForegroundColor Yellow }
        "SKIP" { Write-Host $line -ForegroundColor DarkGray }
        default { Write-Host $line -ForegroundColor Cyan }
    }
}

function Assert-ExitCode {
    param([string]$StepName)
    if ($LASTEXITCODE -eq 0) {
        Write-SetupLog "OK" $StepName
    }
    else {
        Write-SetupLog "FAIL" "$StepName (exit code $LASTEXITCODE)"
        $script:setupErrors++
    }
}

# Phase 1: Environment setup
Write-SetupLog "INFO" "=== Phase 1: Environment setup ==="

# Force English UI
try {
    Set-WinUILanguageOverride -Language "en-US"
    Set-WinSystemLocale -SystemLocale "en-US"
    Set-Culture -CultureInfo "en-US"
    Set-WinHomeLocation -GeoId 244
    Write-SetupLog "OK" "Language forced to English (en-US)"
}
catch {
    Write-SetupLog "FAIL" "Failed to set locale: $_"
    $setupErrors++
}

# Fix slow MSI installs
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v "VerifiedAndReputablePolicyState" /t REG_DWORD /d 0 /f | Out-Null
if (Get-Command CiTool.exe -ErrorAction SilentlyContinue) {
    CiTool.exe --refresh --json | Out-Null
}

# Show file extensions
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f | Out-Null
Assert-ExitCode "File extensions visible"

# Show hidden files
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Hidden" /t REG_DWORD /d 1 /f | Out-Null
Assert-ExitCode "Hidden files visible"

# Show protected OS files
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSuperHidden" /t REG_DWORD /d 1 /f | Out-Null
Assert-ExitCode "Protected OS files visible"

# Classic context menu (Windows 11)
reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null
Assert-ExitCode "Classic context menu enabled"

# Long path support
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v "LongPathsEnabled" /t REG_DWORD /d 1 /f | Out-Null
Assert-ExitCode "Long path support enabled"

# Clipboard history
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord -Force
Write-SetupLog "OK" "Clipboard history enabled"

# RemoteSigned execution policy (least-privilege that allows local scripts)
try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -ErrorAction Stop | Out-Null }
catch { Write-SetupLog "WARN" "Failed to set execution policy: $_" }

# Dark mode
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
Write-SetupLog "OK" "Dark mode enabled"

# Open PowerShell Here context menu
$regOk = $true
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\MyPowerShell" /ve /d "Open PowerShell Here" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\MyPowerShell" /v "Icon" /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe,0" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\MyPowerShell\command" /ve /d "powershell.exe -noexit -command Set-Location -literalPath '%V'" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }

# Open CMD Here context menu
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\Mycmd" /ve /d "Open CMD Here" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\Mycmd" /v "Icon" /t REG_SZ /d "C:\Windows\System32\cmd.exe,0" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\Mycmd\command" /ve /d "cmd.exe /s /k cd /d `"\`"%V`"\`"" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
if ($regOk) { Write-SetupLog "OK" "PowerShell/CMD context menu added" }
else { Write-SetupLog "FAIL" "PowerShell/CMD context menu (partial failure)"; $setupErrors++ }

# New Text Document in context menu
$regOk = $true
reg add "HKEY_CLASSES_ROOT\txtfile" /ve /d "Text Document" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\.txt\ShellNew" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
cmd /c 'reg add "HKEY_CLASSES_ROOT\.txt\ShellNew" /v "NullFile" /t REG_SZ /d "" /f' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\.txt\ShellNew" /v "ItemName" /t REG_SZ /d "New Text Document" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }

# New PowerShell Script in context menu
reg add "HKEY_CLASSES_ROOT\.ps1" /ve /d "ps1file" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\ps1file" /ve /d "PowerShell Script" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\ps1file\DefaultIcon" /ve /d "%SystemRoot%\System32\imageres.dll,-5372" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /ve /d "ps1file" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
cmd /c 'reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /v "NullFile" /t REG_SZ /d "" /f' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /v "ItemName" /t REG_SZ /d "script" /f | Out-Null
if ($LASTEXITCODE -ne 0) { $regOk = $false }
if ($regOk) { Write-SetupLog "OK" "Shell new items added (.txt, .ps1)" }
else { Write-SetupLog "FAIL" "Shell new items (partial failure)"; $setupErrors++ }

# Security hardening

# PowerShell script block logging
try {
    $sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    New-Item -Path $sbPath -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -ErrorAction Stop
    Write-SetupLog "OK" "PowerShell script block logging enabled"
}
catch {
    Write-SetupLog "FAIL" "PowerShell script block logging: $_"
    $setupErrors++
}

# PowerShell module logging
try {
    $mlPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    New-Item -Path $mlPath -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord -ErrorAction Stop
    $mnPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
    New-Item -Path $mnPath -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path $mnPath -Name "*" -Value "*" -Type String -ErrorAction Stop
    Write-SetupLog "OK" "PowerShell module logging enabled"
}
catch {
    Write-SetupLog "FAIL" "PowerShell module logging: $_"
    $setupErrors++
}

# Process creation auditing with command-line capture
$auditOk = $true
auditpol /set /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable | Out-Null
if ($LASTEXITCODE -ne 0) { $auditOk = $false }
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v "ProcessCreationIncludeCmdLine_Enabled" /t REG_DWORD /d 1 /f | Out-Null
if ($LASTEXITCODE -ne 0) { $auditOk = $false }
if ($auditOk) { Write-SetupLog "OK" "Process creation auditing enabled" }
else { Write-SetupLog "FAIL" "Process creation auditing (partial failure)"; $setupErrors++ }

# Disable telemetry
try {
    $dcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    New-Item -Path $dcPath -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path $dcPath -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction Stop
    Write-SetupLog "OK" "Telemetry disabled"
}
catch {
    Write-SetupLog "FAIL" "Disable telemetry: $_"
    $setupErrors++
}

# Disable Windows Error Reporting
try {
    $werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
    New-Item -Path $werPath -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path $werPath -Name "Disabled" -Value 1 -Type DWord -ErrorAction Stop
    Write-SetupLog "OK" "Windows Error Reporting disabled"
}
catch {
    Write-SetupLog "FAIL" "Disable Windows Error Reporting: $_"
    $setupErrors++
}

# Restart Explorer to apply shell/theme changes
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer
Write-SetupLog "OK" "Explorer restarted"

# Phase 2: Install winget
Write-SetupLog "INFO" "=== Phase 2: Installing winget ==="

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Write-SetupLog "OK" "NuGet provider installed"

        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop
        Write-SetupLog "OK" "Microsoft.WinGet.Client module installed"

        Repair-WinGetPackageManager -Latest -ErrorAction Stop
        Write-SetupLog "OK" "winget installed"

        # Refresh PATH so winget is available in this session
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
        "$env:LOCALAPPDATA\Microsoft\WindowsApps"
    }
    catch {
        Write-SetupLog "FAIL" "winget installation failed: $_"
        exit 1
    }
}
else {
    Write-SetupLog "OK" "winget already available"
}

# Phase 3: Tool installation
Write-SetupLog "INFO" "=== Phase 3: Tool installation ==="

$configPath = Join-Path $scriptDir "tools.json"
if (-not (Test-Path $configPath)) {
    Write-SetupLog "FAIL" "tools.json not found at $configPath"
    exit 1
}

$toolsConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$tools = $toolsConfig.tools | Where-Object { $_.enabled -eq $true }

$succeeded = 0
$failedTools = @()
$total = $tools.Count
$current = 0

foreach ($tool in $tools) {
    $current++
    Write-SetupLog "INFO" "[$current/$total] $($tool.name)..."

    try {
        if ($tool.override) {
            $null = & winget install --id $tool.wingetId --source winget --silent --accept-package-agreements --accept-source-agreements --override $tool.override 2>&1
        }
        else {
            $null = & winget install --id $tool.wingetId --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1
        }
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189 -or $LASTEXITCODE -eq -1978335188) {
            if ($LASTEXITCODE -eq 0) {
                Write-SetupLog "OK" "$($tool.name) installed"
            }
            else {
                Write-SetupLog "OK" "$($tool.name) already installed"
            }
            $succeeded++
        }
        else {
            Write-SetupLog "FAIL" "$($tool.name): exit code $LASTEXITCODE"
            $failedTools += $tool.name
        }
    }
    catch {
        Write-SetupLog "FAIL" "$($tool.name): $_"
        $failedTools += $tool.name
    }
}

# Phase 4: Sysmon configuration
Write-SetupLog "INFO" "=== Phase 4: Sysmon configuration ==="

# Refresh PATH after tool installs
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
[System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
"$env:LOCALAPPDATA\Microsoft\WindowsApps"

# Download SwiftOnSecurity Sysmon config (pinned to a specific commit for supply-chain safety)
$sysmonConfigCommit = "1836897f12fbd6a0a473665ef6abc34a6b497e31"
$sysmonConfigExpectedHash = "055FEBC600E6D7448CDF3812307275912927A62B1F94D0D933B64B294BC87162"
$sysmonConfig = Join-Path $env:TEMP "sysmonconfig.xml"
$sysmonConfigValid = $false
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/$sysmonConfigCommit/sysmonconfig-export.xml" -OutFile $sysmonConfig
    $actualHash = (Get-FileHash -Path $sysmonConfig -Algorithm SHA256).Hash
    if ($actualHash -ne $sysmonConfigExpectedHash) {
        Write-SetupLog "FAIL" "Sysmon config hash mismatch: expected=$sysmonConfigExpectedHash actual=$actualHash"
        $setupErrors++
    }
    else {
        Write-SetupLog "OK" "Sysmon config downloaded and verified (SHA256: $actualHash)"
        $sysmonConfigValid = $true
    }
}
catch {
    Write-SetupLog "FAIL" "Failed to download Sysmon config: $_"
    $setupErrors++
}

# Find and configure Sysmon
$sysmonExe = $null
if (Get-Command Sysmon64.exe -ErrorAction SilentlyContinue) {
    $sysmonExe = "Sysmon64.exe"
}
elseif (Get-Command Sysmon.exe -ErrorAction SilentlyContinue) {
    $sysmonExe = "Sysmon.exe"
}
else {
    # Check common install paths
    $candidates = @(
        "${env:ProgramFiles}\Sysinternals\Sysmon64.exe",
        "${env:ProgramFiles}\SysinternalsSuite\Sysmon64.exe",
        "${env:LOCALAPPDATA}\Microsoft\WinGet\Packages\*\Sysmon64.exe"
    )
    foreach ($path in $candidates) {
        $found = Get-Item $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $sysmonExe = $found.FullName; break }
    }
}

if ($sysmonExe -and $sysmonConfigValid) {
    & $sysmonExe -accepteula -i $sysmonConfig 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-SetupLog "OK" "Sysmon installed with SwiftOnSecurity config"
    }
    else {
        Write-SetupLog "FAIL" "Sysmon install failed (exit code $LASTEXITCODE)"
        $setupErrors++
    }
}
else {
    Write-SetupLog "WARN" "Sysmon not found or config not valid - skipping"
    $setupErrors++
}

# Summary
Write-SetupLog "INFO" "=== Summary ==="
Write-SetupLog "INFO" "Tools: $succeeded / $total installed"
if ($failedTools.Count -gt 0) {
    Write-SetupLog "FAIL" "Failed tools: $($failedTools -join ', ')"
}
if ($setupErrors -gt 0) {
    Write-SetupLog "FAIL" "Setup errors: $setupErrors (see log above)"
}
Write-SetupLog "INFO" "Log: $logFile"
if ($failedTools.Count -eq 0 -and $setupErrors -eq 0) {
    Write-SetupLog "INFO" "=== Sandbox ready ==="
}
else {
    Write-SetupLog "WARN" "=== Sandbox setup completed with errors ==="
}

Write-SetupLog "INFO" "Window kept open by -NoExit flag"
