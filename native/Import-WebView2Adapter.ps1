param(
    [Parameter(Mandatory=$true)]
    [object]$Adapter,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function New-JA21AdapterResult {
    param(
        [bool]$Ready,
        [string]$ErrorText = '',
        [object]$CoreAssembly = $null,
        [object]$WpfAssembly = $null,
        [object]$WinFormsAssembly = $null,
        [bool]$RuntimeReady = $false,
        [string]$RuntimeVersion = '',
        [string]$RuntimeError = ''
    )
    return [pscustomobject]@{
        Ready          = $Ready
        Error          = $ErrorText
        CoreAssembly   = $CoreAssembly
        WpfAssembly    = $WpfAssembly
        WinFormsAssembly = $WinFormsAssembly
        RuntimeReady   = $RuntimeReady
        RuntimeVersion = $RuntimeVersion
        RuntimeError   = $RuntimeError
    }
}

function Get-JA21FullFile([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label path is empty." }
    $Full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $Full -PathType Leaf)) { throw "$Label is missing: $Full" }
    return $Full
}

function Assert-JA21ContainedFile([string]$Root, [string]$Path, [string]$Label) {
    $RootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $PathFull = Get-JA21FullFile $Path $Label
    $Prefix = $RootFull + '\'
    if (-not $PathFull.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped the adapter directory: $PathFull"
    }
    return $PathFull
}

function Get-JA21LoadedAssemblyByIdentity([System.Reflection.AssemblyName]$Identity) {
    foreach ($Assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        try {
            if ($Assembly.GetName().FullName -eq $Identity.FullName) { return $Assembly }
        } catch { }
    }
    return $null
}

try {
    if ($null -eq $Adapter -or -not $Adapter.Ready) {
        return (New-JA21AdapterResult -Ready $false -ErrorText 'WebView2 adapter was not provisioned.')
    }

    $AdapterRoot = [System.IO.Path]::GetFullPath([string]$Adapter.Root).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $AdapterRoot -PathType Container)) {
        throw "WebView2 adapter directory is missing: $AdapterRoot"
    }

    $Core = Assert-JA21ContainedFile $AdapterRoot ([string]$Adapter.Core) 'Microsoft.Web.WebView2.Core.dll'
    $Wpf = Assert-JA21ContainedFile $AdapterRoot ([string]$Adapter.Wpf) 'Microsoft.Web.WebView2.Wpf.dll'
    $WinForms = Assert-JA21ContainedFile $AdapterRoot ([string]$Adapter.WinForms) 'Microsoft.Web.WebView2.WinForms.dll'
    $Loader = Assert-JA21ContainedFile $AdapterRoot ([string]$Adapter.Loader) 'WebView2Loader.dll'
    $ExpectedVersion = [string]$Adapter.Version
    if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { throw 'WebView2 adapter version is empty.' }

    $CoreIdentity = [System.Reflection.AssemblyName]::GetAssemblyName($Core)
    $WpfIdentity = [System.Reflection.AssemblyName]::GetAssemblyName($Wpf)
    $WinFormsIdentity = [System.Reflection.AssemblyName]::GetAssemblyName($WinForms)
    if ($CoreIdentity.Name -ne 'Microsoft.Web.WebView2.Core') {
        throw "Unexpected Core assembly identity: $($CoreIdentity.FullName)"
    }
    if ($WpfIdentity.Name -ne 'Microsoft.Web.WebView2.Wpf') {
        throw "Unexpected WPF assembly identity: $($WpfIdentity.FullName)"
    }
    if ($WinFormsIdentity.Name -ne 'Microsoft.Web.WebView2.WinForms') {
        throw "Unexpected WinForms assembly identity: $($WinFormsIdentity.FullName)"
    }
    if ($CoreIdentity.Version.ToString() -ne $ExpectedVersion) {
        throw "WebView2 Core assembly version mismatch. Expected $ExpectedVersion, found $($CoreIdentity.Version)."
    }
    if ($WpfIdentity.Version.ToString() -ne $ExpectedVersion) {
        throw "WebView2 WPF assembly version mismatch. Expected $ExpectedVersion, found $($WpfIdentity.Version)."
    }
    if ($WinFormsIdentity.Version.ToString() -ne $ExpectedVersion) {
        throw "WebView2 WinForms assembly version mismatch. Expected $ExpectedVersion, found $($WinFormsIdentity.Version)."
    }

    # WebView2Loader.dll is native. Put the exact adapter directory first in this process's DLL
    # search PATH before any WebView2 API can P/Invoke it. This affects only the current launcher.
    $PathParts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:PATH)) { $PathParts = @($env:PATH -split ';') }
    $AlreadyOnPath = $false
    foreach ($Part in $PathParts) {
        if ([string]::IsNullOrWhiteSpace($Part)) { continue }
        try {
            if ([System.IO.Path]::GetFullPath($Part.Trim('"')).TrimEnd('\').Equals($AdapterRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $AlreadyOnPath = $true
                break
            }
        } catch { }
    }
    if (-not $AlreadyOnPath) {
        if ([string]::IsNullOrWhiteSpace($env:PATH)) { $env:PATH = $AdapterRoot }
        else { $env:PATH = $AdapterRoot + ';' + $env:PATH }
    }

    # Add-Type's -ReferencedAssemblies switch is a *compiler* reference. It does not guarantee
    # that the CLR can resolve those strong-named assemblies later when Program.Run executes.
    # Explicitly load Core first, then WPF, into the current AppDomain before compiling JA21.
    $CoreAssembly = Get-JA21LoadedAssemblyByIdentity $CoreIdentity
    if ($null -eq $CoreAssembly) { $CoreAssembly = [System.Reflection.Assembly]::LoadFrom($Core) }
    if ($CoreAssembly.GetName().FullName -ne $CoreIdentity.FullName) {
        throw "Loaded WebView2 Core identity differs from the pinned adapter: $($CoreAssembly.GetName().FullName)"
    }

    $WinFormsAssembly = Get-JA21LoadedAssemblyByIdentity $WinFormsIdentity
    if ($null -eq $WinFormsAssembly) { $WinFormsAssembly = [System.Reflection.Assembly]::LoadFrom($WinForms) }
    if ($WinFormsAssembly.GetName().FullName -ne $WinFormsIdentity.FullName) {
        throw "Loaded WebView2 WinForms identity differs from the pinned adapter: $($WinFormsAssembly.GetName().FullName)"
    }

    $WpfAssembly = Get-JA21LoadedAssemblyByIdentity $WpfIdentity
    if ($null -eq $WpfAssembly) { $WpfAssembly = [System.Reflection.Assembly]::LoadFrom($Wpf) }
    if ($WpfAssembly.GetName().FullName -ne $WpfIdentity.FullName) {
        throw "Loaded WebView2 WPF identity differs from the pinned adapter: $($WpfAssembly.GetName().FullName)"
    }

    # Runtime discovery is explicit. The hologram console has no ordinary-browser or native-document
    # fallback; Start-Hologram.ps1 requires a compatible Evergreen Runtime before opening the guest.
    $RuntimeReady = $false
    $RuntimeVersion = ''
    $RuntimeError = ''
    try {
        $EnvironmentType = $CoreAssembly.GetType('Microsoft.Web.WebView2.Core.CoreWebView2Environment', $true)
        $Candidates = @($EnvironmentType.GetMethods([System.Reflection.BindingFlags]'Public,Static') | Where-Object { $_.Name -eq 'GetAvailableBrowserVersionString' } | Sort-Object { $_.GetParameters().Count })
        if ($Candidates.Count -lt 1) { throw 'CoreWebView2Environment.GetAvailableBrowserVersionString was not found.' }
        $Method = $Candidates[0]
        $ParameterCount = $Method.GetParameters().Count
        if ($ParameterCount -eq 0) {
            $RuntimeVersion = [string]$Method.Invoke($null, $null)
        } elseif ($ParameterCount -eq 1) {
            [object[]]$InvokeArgs = New-Object object[] 1
            $InvokeArgs[0] = $null
            $RuntimeVersion = [string]$Method.Invoke($null, $InvokeArgs)
        } else {
            throw "Unexpected WebView2 runtime-discovery signature with $ParameterCount parameters."
        }
        $RuntimeReady = -not [string]::IsNullOrWhiteSpace($RuntimeVersion)
    }
    catch {
        $RuntimeError = $_.Exception.Message
    }

    if (-not $Quiet) {
        Write-Host "WebView2 managed adapter loaded: $ExpectedVersion" -ForegroundColor Green
        Write-Host "  Core:   $Core"
        Write-Host "  WPF:    $Wpf"
        Write-Host "  WinForms: $WinForms"
        Write-Host "  Loader: $Loader"
        if ($RuntimeReady) { Write-Host "  Evergreen runtime: $RuntimeVersion" -ForegroundColor Green }
        else { Write-Warning "Evergreen runtime was not detected. Pixel Panic will not fall back to an ordinary browser. $RuntimeError" }
    }

    return (New-JA21AdapterResult -Ready $true -CoreAssembly $CoreAssembly -WpfAssembly $WpfAssembly -WinFormsAssembly $WinFormsAssembly -RuntimeReady $RuntimeReady -RuntimeVersion $RuntimeVersion -RuntimeError $RuntimeError)
}
catch {
    $Message = $_.Exception.Message
    if (-not $Quiet) { Write-Warning "WebView2 managed adapter load failed. Pixel Panic will not use an ordinary-browser fallback. $Message" }
    return (New-JA21AdapterResult -Ready $false -ErrorText $Message)
}
