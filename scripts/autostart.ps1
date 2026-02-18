# Windows Sandbox auto-setup script
# Installs winget, then installs all enabled tools from tools.json

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$scriptDir = $PSScriptRoot
$logFile = Join-Path $env:TEMP "sandbox-install.log"

function Write-Log {
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

# Phase 1: Environment setup
Write-Log "INFO" "=== Phase 1: Environment setup ==="

# Fix slow MSI installs
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v "VerifiedAndReputablePolicyState" /t REG_DWORD /d 0 /f | Out-Null
CiTool.exe --refresh --json | Out-Null

# Show file extensions
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f | Out-Null
Write-Log "OK" "File extensions visible"

# Show hidden files
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Hidden" /t REG_DWORD /d 1 /f | Out-Null
Write-Log "OK" "Hidden files visible"

# Show protected OS files
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSuperHidden" /t REG_DWORD /d 1 /f | Out-Null
Write-Log "OK" "Protected OS files visible"

# Classic context menu (Windows 11)
reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null
Write-Log "OK" "Classic context menu enabled"

# Long path support
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v "LongPathsEnabled" /t REG_DWORD /d 1 /f | Out-Null
Write-Log "OK" "Long path support enabled"

# Clipboard history
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord -Force
Write-Log "OK" "Clipboard history enabled"

# Unrestricted execution policy
try { Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -ErrorAction Stop | Out-Null } catch {}

# Dark mode
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
Write-Log "OK" "Dark mode enabled"

# Open PowerShell Here context menu
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\MyPowerShell" /ve /d "Open PowerShell Here" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\MyPowerShell" /v "Icon" /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe,0" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\MyPowerShell\command" /ve /d "powershell.exe -noexit -command Set-Location -literalPath '%V'" /f | Out-Null

# Open CMD Here context menu
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\Mycmd" /ve /d "Open CMD Here" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\Mycmd" /v "Icon" /t REG_SZ /d "C:\Windows\System32\cmd.exe,0" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\Mycmd\command" /ve /d "cmd.exe /s /k cd /d `"\`"%V`"\`"" /f | Out-Null
Write-Log "OK" "PowerShell/CMD context menu added"

# New Text Document in context menu
reg add "HKEY_CLASSES_ROOT\txtfile" /ve /d "Text Document" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\.txt\ShellNew" /f | Out-Null
reg --% add "HKEY_CLASSES_ROOT\.txt\ShellNew" /v "NullFile" /t REG_SZ /d "" /f
reg add "HKEY_CLASSES_ROOT\.txt\ShellNew" /v "ItemName" /t REG_SZ /d "New Text Document" /f | Out-Null

# New PowerShell Script in context menu
reg add "HKEY_CLASSES_ROOT\.ps1" /ve /d "ps1file" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\ps1file" /ve /d "PowerShell Script" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\ps1file\DefaultIcon" /ve /d "%SystemRoot%\System32\imageres.dll,-5372" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /ve /d "ps1file" /f | Out-Null
reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /f | Out-Null
reg --% add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /v "NullFile" /t REG_SZ /d "" /f
reg add "HKEY_CLASSES_ROOT\.ps1\ShellNew" /v "ItemName" /t REG_SZ /d "script" /f | Out-Null
Write-Log "OK" "Shell new items added (.txt, .ps1)"

# Security hardening 

# PowerShell script block logging
$sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
New-Item -Path $sbPath -Force | Out-Null
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
Write-Log "OK" "PowerShell script block logging enabled"

# PowerShell module logging
$mlPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
New-Item -Path $mlPath -Force | Out-Null
Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord
$mnPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
New-Item -Path $mnPath -Force | Out-Null
Set-ItemProperty -Path $mnPath -Name "*" -Value "*" -Type String
Write-Log "OK" "PowerShell module logging enabled"

# Process creation auditing with command-line capture
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v "ProcessCreationIncludeCmdLine_Enabled" /t REG_DWORD /d 1 /f | Out-Null
Write-Log "OK" "Process creation auditing enabled"

# Disable telemetry
$dcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
New-Item -Path $dcPath -Force | Out-Null
Set-ItemProperty -Path $dcPath -Name "AllowTelemetry" -Value 0 -Type DWord
Write-Log "OK" "Telemetry disabled"

# Disable Windows Error Reporting
$werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
New-Item -Path $werPath -Force | Out-Null
Set-ItemProperty -Path $werPath -Name "Disabled" -Value 1 -Type DWord
Write-Log "OK" "Windows Error Reporting disabled"

# Restart Explorer to apply shell/theme changes
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer
Write-Log "OK" "Explorer restarted"

# Phase 2: Install winget
Write-Log "INFO" "=== Phase 2: Installing winget ==="

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    try {
        # VCLibs dependency
        $vcLibsPath = Join-Path $env:TEMP "Microsoft.VCLibs.appx"
        Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $vcLibsPath
        Add-AppxPackage -Path $vcLibsPath
        Write-Log "OK" "VCLibs installed"

        # UI.Xaml dependency (from NuGet)
        $uiXamlZip = Join-Path $env:TEMP "microsoft.ui.xaml.zip"
        $uiXamlDir = Join-Path $env:TEMP "microsoft.ui.xaml"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6" -OutFile $uiXamlZip
        Expand-Archive -Path $uiXamlZip -DestinationPath $uiXamlDir -Force
        Add-AppxPackage -Path (Join-Path $uiXamlDir "tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx")
        Write-Log "OK" "UI.Xaml installed"

        # Winget itself
        $wingetPath = Join-Path $env:TEMP "winget.msixbundle"
        Invoke-WebRequest -Uri "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile $wingetPath
        Add-AppxPackage -Path $wingetPath
        Write-Log "OK" "winget installed"

        # Refresh PATH so winget is available in this session
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
        "$env:LOCALAPPDATA\Microsoft\WindowsApps"
    }
    catch {
        Write-Log "FAIL" "winget installation failed: $_"
        Read-Host "Press Enter to close"
        exit 1
    }
}
else {
    Write-Log "OK" "winget already available"
}

# Phase 3: Tool installation
Write-Log "INFO" "=== Phase 3: Tool installation ==="

$configPath = Join-Path $scriptDir "tools.json"
if (-not (Test-Path $configPath)) {
    Write-Log "FAIL" "tools.json not found at $configPath"
    Read-Host "Press Enter to close"
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
    Write-Log "INFO" "[$current/$total] $($tool.name)..."

    try {
        if ($tool.override) {
            $null = & winget install --id $tool.wingetId --silent --accept-package-agreements --accept-source-agreements --override $tool.override 2>&1
        }
        else {
            $null = & winget install --id $tool.wingetId --silent --accept-package-agreements --accept-source-agreements 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "OK" "$($tool.name) installed"
            $succeeded++
        }
        else {
            Write-Log "FAIL" "$($tool.name): exit code $LASTEXITCODE"
            $failedTools += $tool.name
        }
    }
    catch {
        Write-Log "FAIL" "$($tool.name): $_"
        $failedTools += $tool.name
    }
}

# Phase 4: Sysmon configuration
Write-Log "INFO" "=== Phase 4: Sysmon configuration ==="

# Refresh PATH after tool installs
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
[System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
"$env:LOCALAPPDATA\Microsoft\WindowsApps"

# Download SwiftOnSecurity Sysmon config
$sysmonConfig = Join-Path $env:TEMP "sysmonconfig.xml"
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -OutFile $sysmonConfig
    Write-Log "OK" "Sysmon config downloaded"
}
catch {
    Write-Log "FAIL" "Failed to download Sysmon config: $_"
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

if ($sysmonExe -and (Test-Path $sysmonConfig)) {
    & $sysmonExe -accepteula -i $sysmonConfig 2>&1 | Out-Null
    Write-Log "OK" "Sysmon installed with SwiftOnSecurity config"
}
else {
    Write-Log "WARN" "Sysmon not found or config missing — skipping"
}

# Summary
Write-Log "INFO" "=== Summary ==="
Write-Log "INFO" "Tools: $succeeded / $total installed"
if ($failedTools.Count -gt 0) {
    Write-Log "FAIL" "Failed: $($failedTools -join ', ')"
}
Write-Log "INFO" "Log: $logFile"
Write-Log "INFO" "=== Sandbox ready ==="

Read-Host "Press Enter to close"
