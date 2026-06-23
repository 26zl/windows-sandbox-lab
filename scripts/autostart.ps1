# Windows Sandbox auto-setup script.
# Installs tools from tools.json and configures monitoring. Pass -Offline for the
# network-disabled variant (no winget; pre-stage tools + sysmonconfig.xml in scripts/).
param([switch]$Offline)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$scriptDir = $PSScriptRoot
$logFile = Join-Path $env:TEMP "sandbox-install.log"
$setupErrors = 0

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

# Wait for network before starting (LogonCommand can run before network is ready).
# Probe HTTPS, not ICMP (Sandbox NAT often blocks ping). Skipped in offline mode.
if ($Offline) {
    Write-SetupLog "INFO" "Offline mode - network and winget steps skipped"
}
else {
    $maxWait = 120
    $waited = 0
    $networkUp = $false
    while ($waited -lt $maxWait) {
        try {
            Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -Method Head -TimeoutSec 5 | Out-Null
            $networkUp = $true
            break
        }
        catch {
            # any HTTP response means the network is up
            if ($_.Exception.Response) { $networkUp = $true; break }
        }
        Start-Sleep -Seconds 2
        $waited += 2
    }
    if (-not $networkUp) {
        Write-SetupLog "FAIL" "Network not available after ${maxWait}s - cannot continue"
        Read-Host "Setup cannot continue (no network). Log: $logFile. Press Enter to close"
        exit 1
    }
    Write-SetupLog "OK" "Network available"
}

# Phase 1: Environment setup
Write-SetupLog "INFO" "=== Phase 1: Environment setup ==="

# Force English UI
try {
    Set-WinUILanguageOverride -Language "en-US"
    Set-WinSystemLocale -SystemLocale "en-US"
    Set-Culture -CultureInfo "en-US"
    Set-WinHomeLocation -GeoId 244
    Write-SetupLog "OK" "User culture set to en-US (system locale / UI override are staged but need a reboot the Sandbox never performs)"
}
catch {
    Write-SetupLog "FAIL" "Failed to set locale: $_"
    $setupErrors++
}

# Fix slow MSI installs (best-effort)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v "VerifiedAndReputablePolicyState" /t REG_DWORD /d 0 /f | Out-Null
if ($LASTEXITCODE -eq 0) { Write-SetupLog "OK" "MSI install speedup policy set" }
else { Write-SetupLog "WARN" "MSI speedup policy write failed (installs may be slower)" }
if (Get-Command CiTool.exe -ErrorAction SilentlyContinue) {
    CiTool.exe --refresh --json | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-SetupLog "WARN" "CiTool --refresh failed (exit $LASTEXITCODE) - non-fatal" }
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
try {
    New-Item -Path "HKCU:\Software\Microsoft\Clipboard" -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord -Force -ErrorAction Stop
    Write-SetupLog "OK" "Clipboard history enabled"
}
catch {
    Write-SetupLog "WARN" "Clipboard history: $_"
}

# RemoteSigned for shells opened later (this window stays Bypass, from launch.cmd)
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
    Write-SetupLog "OK" "Execution policy set to RemoteSigned (LocalMachine)"
}
catch {
    Write-SetupLog "WARN" "Failed to set execution policy: $_"
}

# Dark mode
try {
    $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-ItemProperty -Path $themePath -Name "AppsUseLightTheme" -Value 0 -Type DWord -ErrorAction Stop
    Set-ItemProperty -Path $themePath -Name "SystemUsesLightTheme" -Value 0 -Type DWord -ErrorAction Stop
    Write-SetupLog "OK" "Dark mode enabled"
}
catch {
    Write-SetupLog "WARN" "Dark mode: $_"
}

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
try {
    Start-Process explorer -ErrorAction Stop
    Write-SetupLog "OK" "Explorer restarted"
}
catch {
    Write-SetupLog "WARN" "Explorer restart: $_"
}

# Phase 2: Install winget (online only)
if (-not $Offline) {
    Write-SetupLog "INFO" "=== Phase 2: Installing winget ==="
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        # retry the bootstrap on transient network failures
        $bootstrapped = $false
        for ($attempt = 1; $attempt -le 3 -and -not $bootstrapped; $attempt++) {
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
                Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop
                Repair-WinGetPackageManager -Latest -ErrorAction Stop
                $bootstrapped = $true
            }
            catch {
                Write-SetupLog "WARN" "winget bootstrap attempt $attempt/3 failed: $_"
                if ($attempt -lt 3) { Start-Sleep -Seconds ($attempt * 5) }
            }
        }
        if (-not $bootstrapped) {
            Write-SetupLog "FAIL" "winget installation failed after 3 attempts - cannot continue"
            Read-Host "Setup cannot continue (winget bootstrap failed). Log: $logFile. Press Enter to close"
            exit 1
        }
        Write-SetupLog "OK" "winget installed"

        # Refresh PATH so winget is available in this session
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
        "$env:LOCALAPPDATA\Microsoft\WindowsApps"
    }
    else {
        Write-SetupLog "OK" "winget already available"
    }
}

# Phase 3: Tools
$configPath = Join-Path $scriptDir "tools.json"
if (-not (Test-Path $configPath)) {
    Write-SetupLog "FAIL" "tools.json not found at $configPath"
    Read-Host "Setup cannot continue (tools.json missing). Log: $logFile. Press Enter to close"
    exit 1
}

$toolsConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$enabledTools = @($toolsConfig.tools | Where-Object { $_.enabled -eq $true })

$succeeded = 0
$total = 0
$failedTools = @()
$manualTools = @()

if ($Offline) {
    # No winget offline - just list what to pre-stage on the host.
    Write-SetupLog "INFO" "=== Phase 3: Tools to pre-stage (no network) ==="
    foreach ($t in $enabledTools) {
        $hint = if ($t.url) { $t.url } elseif ($t.wingetId) { "winget id: $($t.wingetId) (download installer on host)" } else { "" }
        Write-SetupLog "INFO" "  $($t.name): $hint"
    }
}
else {
    Write-SetupLog "INFO" "=== Phase 3: Tool installation ==="
    # manual tools (no winget package) are listed at the end, not installed
    $manualTools = @($enabledTools | Where-Object { $_.source -eq 'manual' -or -not $_.wingetId })
    $tools = @($enabledTools | Where-Object { $_.source -ne 'manual' -and $_.wingetId })
    $total = $tools.Count
    $current = 0

    foreach ($tool in $tools) {
        $current++
        # flag long installs (e.g. Build Tools) so they aren't mistaken for a hang
        $note = if ($tool.override) { " (large install - several minutes, no output is normal)" } else { "" }
        Write-SetupLog "INFO" "[$current/$total] $($tool.name)...$note"

        $installed = $false
        $lastCode = $null
        $lastOut = ""
        for ($attempt = 1; $attempt -le 3 -and -not $installed; $attempt++) {
            try {
                if ($tool.override) {
                    $lastOut = & winget install --id $tool.wingetId --source winget --silent --accept-package-agreements --accept-source-agreements --override $tool.override 2>&1
                }
                else {
                    $lastOut = & winget install --id $tool.wingetId --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1
                }
                $lastCode = $LASTEXITCODE
                # 0 = installed; -1978335189 / -1978335188 = already installed / no applicable update
                if ($lastCode -eq 0 -or $lastCode -eq -1978335189 -or $lastCode -eq -1978335188) {
                    if ($lastCode -eq 0) { Write-SetupLog "OK" "$($tool.name) installed" }
                    else { Write-SetupLog "OK" "$($tool.name) already installed" }
                    $succeeded++; $installed = $true; break
                }
                # non-zero can still mean "installed, reboot required" - confirm with an exact list lookup
                & winget list --id $tool.wingetId --exact --source winget --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-SetupLog "OK" "$($tool.name) installed (winget exit $lastCode; package present, reboot flag ignored)"
                    $succeeded++; $installed = $true; break
                }
                Write-SetupLog "WARN" "$($tool.name): exit code $lastCode (attempt $attempt/3)"
            }
            catch {
                $lastCode = 'exception'; $lastOut = $_
                Write-SetupLog "WARN" "$($tool.name): $_ (attempt $attempt/3)"
            }
            if ($attempt -lt 3) { Start-Sleep -Seconds ($attempt * 5) }
        }

        if (-not $installed) {
            Write-SetupLog "FAIL" "$($tool.name): failed after 3 attempts (last exit $lastCode)"
            if ($lastOut) { Write-SetupLog "FAIL" "  winget: $(($lastOut | Out-String).Trim())" }
            $failedTools += $tool.name
        }
    }
}

# Phase 4: Sysmon (built-in Windows optional feature)
Write-SetupLog "INFO" "=== Phase 4: Sysmon configuration ==="

if (-not $Offline) {
    # Refresh PATH so winget-installed CLIs are on PATH in the kept-open window
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" +
    "$env:LOCALAPPDATA\Microsoft\WindowsApps"
}

$feature = Get-WindowsOptionalFeature -Online -FeatureName Sysmon -ErrorAction SilentlyContinue
if (-not $feature) {
    Write-SetupLog "WARN" "Built-in Sysmon feature not available on this Windows build - skipping"
}
else {
    if ($feature.State -ne 'Enabled') {
        try { Enable-WindowsOptionalFeature -Online -FeatureName Sysmon -All -NoRestart -ErrorAction Stop | Out-Null }
        catch { Write-SetupLog "WARN" "Could not enable built-in Sysmon: $_" }
        $feature = Get-WindowsOptionalFeature -Online -FeatureName Sysmon -ErrorAction SilentlyContinue
    }

    if ($feature.State -ne 'Enabled') {
        Write-SetupLog "WARN" "Built-in Sysmon feature could not be enabled - skipping"
    }
    else {
        $sysmonConfig = $null
        $sysmonConfigValid = $false
        if ($Offline) {
            # use a pre-staged config from scripts/ if present (read-only mapped folder)
            $sysmonConfig = Join-Path $scriptDir "sysmonconfig.xml"
            $sysmonConfigValid = Test-Path $sysmonConfig
        }
        else {
            # Download + verify the SwiftOnSecurity config (pinned commit + SHA256)
            $sysmonConfigCommit = "1836897f12fbd6a0a473665ef6abc34a6b497e31"
            $sysmonConfigExpectedHash = "055FEBC600E6D7448CDF3812307275912927A62B1F94D0D933B64B294BC87162"
            $sysmonConfig = Join-Path $env:TEMP "sysmonconfig.xml"
            $sysmonConfigUrl = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/$sysmonConfigCommit/sysmonconfig-export.xml"
            for ($attempt = 1; $attempt -le 3 -and -not $sysmonConfigValid; $attempt++) {
                try {
                    Invoke-WebRequest -Uri $sysmonConfigUrl -OutFile $sysmonConfig -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                    $actualHash = (Get-FileHash -Path $sysmonConfig -Algorithm SHA256).Hash
                    if ($actualHash -ne $sysmonConfigExpectedHash) {
                        # hash mismatch - don't retry a changed file
                        Write-SetupLog "FAIL" "Sysmon config hash mismatch: expected=$sysmonConfigExpectedHash actual=$actualHash"
                        $setupErrors++
                        break
                    }
                    Write-SetupLog "OK" "Sysmon config downloaded and verified (SHA256: $actualHash)"
                    $sysmonConfigValid = $true
                }
                catch {
                    Write-SetupLog "WARN" "Sysmon config download attempt $attempt/3 failed: $_"
                    if ($attempt -lt 3) { Start-Sleep -Seconds ($attempt * 2) }
                }
            }
        }

        # Apply config with the on-PATH sysmon. Use the verified/pre-staged config if we have
        # one, else Sysmon's own default ruleset so monitoring still runs. Guard on Get-Command
        # (a command-not-found would NOT update $LASTEXITCODE -> stale value = false success),
        # and try with -accepteula first, then without (the built-in build may reject it).
        if (-not (Get-Command sysmon -ErrorAction SilentlyContinue)) {
            Write-SetupLog "FAIL" "Sysmon feature enabled but sysmon.exe not found on PATH"
            $setupErrors++
        }
        else {
            $op = if (Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue) { '-c' } else { '-i' }
            $sysmonArgs = if ($sysmonConfigValid) { @($op, $sysmonConfig) } else { @('-i') }
            $sysmonOk = $false
            try {
                sysmon -accepteula @sysmonArgs 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { sysmon @sysmonArgs 2>&1 | Out-Null }
                $sysmonOk = ($LASTEXITCODE -eq 0)
            }
            catch {
                Write-SetupLog "WARN" "Sysmon invocation error: $_"
            }
            if ($sysmonOk) {
                if ($sysmonConfigValid) { Write-SetupLog "OK" "Sysmon configured with SwiftOnSecurity config" }
                else { Write-SetupLog "WARN" "Sysmon enabled with its default config (SwiftOnSecurity config unavailable)" }
            }
            else {
                Write-SetupLog "FAIL" "Sysmon config failed (exit code $LASTEXITCODE)"
                $setupErrors++
            }
        }
    }
}

# Summary
Write-SetupLog "INFO" "=== Summary ==="
if (-not $Offline) {
    Write-SetupLog "INFO" "Tools: $succeeded / $total installed"
    if ($failedTools.Count -gt 0) {
        Write-SetupLog "FAIL" "Failed tools: $($failedTools -join ', ')"
    }
}
if ($setupErrors -gt 0) {
    Write-SetupLog "WARN" "Optional steps with issues: $setupErrors (monitoring/tweaks - see log above)"
}
if ($manualTools.Count -gt 0) {
    Write-SetupLog "INFO" "=== Manual tools (not on winget - grab these inside the sandbox) ==="
    foreach ($m in $manualTools) {
        Write-SetupLog "INFO" "  $($m.name): $($m.url)"
    }
}
Write-SetupLog "INFO" "Log: $logFile"
# "ready" depends only on tool installs, so optional hardening issues don't hide it
if ($Offline) {
    Write-SetupLog "INFO" "=== Offline sandbox ready (network disabled) ==="
}
elseif ($failedTools.Count -eq 0) {
    Write-SetupLog "INFO" "=== Sandbox ready ==="
}
else {
    Write-SetupLog "WARN" "=== Sandbox ready (with $($failedTools.Count) tool failure(s) - see above) ==="
}

Write-SetupLog "INFO" "Window kept open by -NoExit flag"
