param([switch]$SkipConsent)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Runtime = Join-Path $Root 'runtime'
$SdkVersion = '1.0.4191.47'
$Sdk = Join-Path $Runtime 'webview2-sdk'
$Temp = Join-Path $Runtime ('.webview2-setup-' + [Guid]::NewGuid().ToString('N'))
$Url = 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/' + $SdkVersion
$Required = @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.Wpf.dll','Microsoft.Web.WebView2.WinForms.dll','WebView2Loader.dll')

if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell; this hologram console profile is x64.' }
function Test-CompleteAdapter {
    if (!(Test-Path -LiteralPath $Sdk -PathType Container)) { return $false }
    foreach ($Name in $Required) {
        if (!(Test-Path -LiteralPath (Join-Path $Sdk $Name) -PathType Leaf)) { return $false }
    }
    return $true
}
if (Test-CompleteAdapter) {
    Write-Host "WebView2 SDK adapter is already present: $Sdk" -ForegroundColor Green
    return
}

if (-not $SkipConsent) {
    Write-Host "Pixel Panic needs the external Microsoft.Web.WebView2 $SdkVersion SDK adapter for the C# virtual-console harness."
    Write-Host 'This adapter is NOT game/runtime content; the game, rules, guest runtime, HERMIT console, and state remain inside the TIFF/GIF.'
    Write-Host "Setup downloads the official NuGet package from nuget.org and extracts only the x64 WPF/Core/Loader adapter files into:`n  $Sdk"
    Write-Host 'No administrator elevation, system SDK installation, or browser fallback is performed.'
    if ((Read-Host 'Type YES to provision this external adapter') -cne 'YES') { throw 'WebView2 SDK adapter setup cancelled; no download was authorized.' }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $Runtime | Out-Null
New-Item -ItemType Directory -Force -Path $Temp | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Extract-Entry([string]$Archive,[string]$Entry,[string]$Target) {
    $Zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $Item = $Zip.GetEntry($Entry)
        if ($null -eq $Item -or $Item.Length -le 0 -or $Item.Length -gt 150MB) { throw "Expected bounded archive entry missing: $Entry" }
        $Input = $Item.Open()
        try {
            $Output = [IO.File]::Open($Target,[IO.FileMode]::CreateNew)
            try { $Input.CopyTo($Output) } finally { $Output.Dispose() }
        } finally { $Input.Dispose() }
    } finally { $Zip.Dispose() }
}
function Assert-MicrosoftPublisher([string]$File) {
    $Signature = Get-AuthenticodeSignature -LiteralPath $File
    if ($Signature.Status -ne 'Valid' -or $null -eq $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Microsoft publisher signature validation failed: $File ($($Signature.Status)). No trust bypass is provided."
    }
}

try {
    $Archive = Join-Path $Temp 'Microsoft.Web.WebView2.nupkg'
    Write-Host "Downloading pinned WebView2 SDK adapter $SdkVersion from Microsoft/NuGet..."
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Archive
    if (!(Test-Path -LiteralPath $Archive -PathType Leaf) -or (Get-Item -LiteralPath $Archive).Length -lt 1MB) { throw 'Downloaded NuGet package is unexpectedly small or missing.' }

    $Stage = Join-Path $Temp 'webview2-sdk'
    New-Item -ItemType Directory -Path $Stage | Out-Null
    $Mapping = @{
        'Microsoft.Web.WebView2.Core.dll' = 'lib/net462/Microsoft.Web.WebView2.Core.dll'
        'Microsoft.Web.WebView2.Wpf.dll'      = 'lib/net462/Microsoft.Web.WebView2.Wpf.dll'
        'Microsoft.Web.WebView2.WinForms.dll' = 'lib/net462/Microsoft.Web.WebView2.WinForms.dll'
        'WebView2Loader.dll'              = 'runtimes/win-x64/native/WebView2Loader.dll'
    }
    foreach ($Name in $Mapping.Keys) {
        $Target = Join-Path $Stage $Name
        Extract-Entry $Archive $Mapping[$Name] $Target
        Assert-MicrosoftPublisher $Target
    }

    foreach ($Name in @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.Wpf.dll','Microsoft.Web.WebView2.WinForms.dll')) {
        $Version = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $Stage $Name)).Version.ToString()
        if ($Version -ne $SdkVersion) { throw "WebView2 managed assembly version mismatch for $Name. Expected $SdkVersion, found $Version." }
    }

    # Preserve any top-level license/notice files found in the official package.
    $NoticeEntries = @()
    $Zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($Item in $Zip.Entries) {
            if ($Item.FullName -notmatch '/' -and $Item.FullName -match '(?i)^(license|notice|third.?party).*(\.txt|\.md|\.rtf)$') {
                $NoticeEntries += $Item.FullName
            }
        }
    } finally { $Zip.Dispose() }
    foreach ($EntryName in $NoticeEntries) {
        $Target = Join-Path $Stage ([IO.Path]::GetFileName($EntryName))
        if (!(Test-Path -LiteralPath $Target)) { Extract-Entry $Archive $EntryName $Target }
    }

    $Receipt = [ordered]@{
        schema = 'pixel-panic-webview2-adapter/1'
        version = $SdkVersion
        source = $Url
        package_sha256 = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
        provisioned_utc = [DateTime]::UtcNow.ToString('o')
        files = @()
    }
    foreach ($Name in $Required) {
        $Path = Join-Path $Stage $Name
        $Receipt.files += [ordered]@{
            name = $Name
            bytes = (Get-Item -LiteralPath $Path).Length
            sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $Receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Stage 'PROVISIONED.json') -Encoding UTF8

    if (Test-Path -LiteralPath $Sdk) { Remove-Item -LiteralPath $Sdk -Recurse -Force }
    Move-Item -LiteralPath $Stage -Destination $Sdk
    Write-Host "PASS: external WebView2 SDK adapter $SdkVersion provisioned under runtime\webview2-sdk." -ForegroundColor Green
    Write-Host 'The separate Microsoft Edge WebView2 Evergreen Runtime must also be installed on Windows; BOOT/VERIFY checks it next.'
}
finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force }
}
