@echo off
REM Bypass is required here: the default Restricted policy prevents autostart.ps1 from running at all.
REM This launcher window stays Bypass; autostart.ps1 sets RemoteSigned at LocalMachine for shells opened later.
REM Args (e.g. -Offline) are forwarded to autostart.ps1.
start "" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0autostart.ps1" %*
