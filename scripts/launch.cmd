@echo off
REM Bypass is required here: the default Restricted policy prevents autostart.ps1 from running at all.
REM Once running, autostart.ps1 sets RemoteSigned as the persistent policy for the sandbox session.
start "" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0autostart.ps1"
