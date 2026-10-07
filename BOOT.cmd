@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"
title Pixel Panic - TIFF/GIF Processable Hologram 0.4.4
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
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0native\Start-Hologram.ps1" -Cartridge "%~1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo Hologram boot failed. The TIFF/GIF remains the authoritative software cartridge.
  echo If the SDK adapter could not be provisioned, run SETUP.cmd and retry.
  echo If the Evergreen Runtime is missing, install the official Microsoft Edge WebView2 Runtime and retry.
  echo If Windows reports AllSigned or an organization policy, the unsigned helper scripts must be trusted/signed under that policy.
  echo You can run VERIFY.cmd before BOOT.cmd for a dependency and cartridge preflight.
  pause
)
exit /b %RESULT%
