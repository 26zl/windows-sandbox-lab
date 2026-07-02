@echo off
REM Run autostart with a process-scoped Bypass policy and forward launcher arguments.
start "" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0autostart.ps1" %*
