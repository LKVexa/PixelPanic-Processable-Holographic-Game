@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"
title Pixel Panic - External WebView2 Adapter Setup 0.4.4
rem Clear Mark-of-the-Web only from this package's own PowerShell helpers.
rem This does NOT change the machine/user execution policy and does NOT use Bypass.
set "PP_HOLOGRAM_ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -Command "$root=[Environment]::GetEnvironmentVariable('PP_HOLOGRAM_ROOT'); Get-ChildItem -LiteralPath (Join-Path $root 'native') -Filter '*.ps1' -File | Unblock-File -ErrorAction Stop"
if errorlevel 1 (
  echo.
  echo Unable to clear the downloaded-file mark from the package-owned PowerShell helpers.
  echo No Windows execution policy was changed.
  echo If your organization enforces AllSigned by Group Policy, these unsigned helpers cannot run.
  echo Run VERIFY.cmd after resolving the policy/trust requirement.
  pause
  exit /b 71
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0native\Setup-WebView2.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" echo WebView2 SDK adapter setup completed.
if not "%RESULT%"=="0" echo WebView2 SDK adapter setup failed or was cancelled.
pause
exit /b %RESULT%
