param(
    [string]$Cartridge = '',
    [switch]$VerifyOnly,
    [switch]$NoProvision
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Work = Join-Path $Root 'workspace'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
if ([string]::IsNullOrWhiteSpace($Cartridge)) {
    $Cartridge = Join-Path $Root 'cartridges\PixelPanic-Hologram.tiff'
}
$Cartridge = [IO.Path]::GetFullPath($Cartridge)
if (!(Test-Path -LiteralPath $Cartridge -PathType Leaf)) { throw 'TIFF/GIF cartridge not found.' }

$SdkVersion = '1.0.4191.47'
$Sdk = Join-Path $Root 'runtime\webview2-sdk'
$Required = @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.Wpf.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')
function Test-AdapterLayout {
    foreach ($Name in $Required) {
        if (!(Test-Path -LiteralPath (Join-Path $Sdk $Name) -PathType Leaf)) { return $false }
    }
    return $true
}

if (-not (Test-AdapterLayout)) {
    if ($NoProvision) {
        throw "WebView2 SDK adapter $SdkVersion is missing under runtime\webview2-sdk. Run SETUP.cmd."
    }
    Write-Host 'The external WebView2 SDK adapter is missing. The TIFF/GIF game/runtime is intact.' -ForegroundColor Yellow
    Write-Host "Pixel Panic will provision the pinned Microsoft.Web.WebView2 $SdkVersion adapter into this package's runtime folder."
    & (Join-Path $PSScriptRoot 'Setup-WebView2.ps1')
    if (-not (Test-AdapterLayout)) { throw 'WebView2 SDK adapter provisioning did not produce the required files.' }
}

. (Join-Path $PSScriptRoot 'Wpf-CompileReferences.ps1')
$Refs = Get-JA21WpfCompileReferences
$Adapter = [pscustomobject]@{
    Ready   = $true
    Version = $SdkVersion
    Root    = $Sdk
    Core    = (Join-Path $Sdk 'Microsoft.Web.WebView2.Core.dll')
    Wpf     = (Join-Path $Sdk 'Microsoft.Web.WebView2.Wpf.dll')
    WinForms = (Join-Path $Sdk 'Microsoft.Web.WebView2.WinForms.dll')
    Loader  = (Join-Path $Sdk 'WebView2Loader.dll')
}
$Loaded = & (Join-Path $PSScriptRoot 'Import-WebView2Adapter.ps1') -Adapter $Adapter -Quiet
if (-not $Loaded.Ready) {
    throw "WebView2 SDK adapter load failed: $($Loaded.Error)"
}
if (-not $Loaded.RuntimeReady) {
    throw "Microsoft Edge WebView2 Evergreen Runtime was not detected. Install the official x64 Evergreen Runtime, then rerun BOOT.cmd. Runtime discovery detail: $($Loaded.RuntimeError)"
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions
Add-Type -AssemblyName System.Windows.Forms
$Refs = @($Refs) + @(
    $Adapter.Core,
    $Adapter.Wpf,
    $Adapter.WinForms,
    [System.Drawing.Image].Assembly.Location,
    [System.Windows.Forms.Control].Assembly.Location,
    [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location
) | Select-Object -Unique
Add-Type -Path (Join-Path $PSScriptRoot 'HologramHarness.cs') -ReferencedAssemblies $Refs

if ($VerifyOnly) {
    [PixelPanic.Hologram.Program]::Verify($Cartridge) | Out-Null
    Write-Host 'PASS: C# harness compiled, WebView2 adapter/runtime resolved, and TIFF/GIF cartridge verified.' -ForegroundColor Green
    Write-Host "WebView2 SDK: $SdkVersion"
    Write-Host "WebView2 Runtime: $($Loaded.RuntimeVersion)"
    Write-Host "Cartridge: $Cartridge"
    return
}

[PixelPanic.Hologram.Program]::Run($Cartridge,$Work) | Out-Null
