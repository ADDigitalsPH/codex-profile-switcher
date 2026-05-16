@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::EnableVisualStyles(); [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false); & '%SCRIPT_DIR%CodexProfileSwitcher.ps1'"
if errorlevel 1 pause
