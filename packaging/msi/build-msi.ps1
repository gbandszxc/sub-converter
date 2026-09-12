#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a per-machine x64 MSI installer for Subtitle Converter.

.DESCRIPTION
    Uses the WiX Toolset v3 (candle/heat/light). WiX is not required to be
    installed: if the portable binaries are missing they are downloaded once
    into packaging\msi\.tools\wix314 (git-ignored).

    The Flutter Release folder is harvested at build time by heat.exe, so new
    runtime files (DLLs, data\**, ...) are picked up automatically without
    editing a file list.

.PARAMETER SkipBuild
    Reuse an existing build\windows\x64\runner\<Configuration> folder instead of
    running "flutter build windows".

.PARAMETER Version
    MSI product version, numeric x.y.z (required by the MSI format). Defaults to
    the x.y.z part of the "version:" field in pubspec.yaml (e.g. 0.1.0).

.PARAMETER Configuration
    Flutter build configuration: release (default), profile or debug.

.PARAMETER FlutterExe
    Path to flutter.bat. Defaults to $env:FLUTTER_EXE, then to whatever
    "flutter" resolves to on the PATH.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1 -SkipBuild -Version 0.2.0
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$Version = '',
    [string]$Configuration = 'release',
    [string]$FlutterExe = ''
)

$ErrorActionPreference = 'Stop'

# --- Paths -----------------------------------------------------------------
$ScriptDir = $PSScriptRoot
$RepoRoot  = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$ToolsDir  = Join-Path $ScriptDir '.tools'
$WixDir    = Join-Path $ToolsDir 'wix314'
$WorkDir   = Join-Path $ScriptDir '.build'
$OutDir    = Join-Path $RepoRoot 'build\msi'

$ProductWxs = Join-Path $ScriptDir 'Product.wxs'
$AppExeName = 'sub_converter.exe'
$PackageName = 'sub-converter'
$WixZipUrl  = 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip'

# --- Helpers ---------------------------------------------------------------
function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]   $Step,
        [Parameter(Mandatory = $true)][string]   $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments
    )
    Write-Host ''
    Write-Host "==> $Step" -ForegroundColor Cyan
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}

function Resolve-FlutterExe {
    if (-not [string]::IsNullOrWhiteSpace($FlutterExe)) { return $FlutterExe }
    if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_EXE)) { return $env:FLUTTER_EXE }

    # Resolve "flutter" from the PATH so no machine-specific SDK location is
    # baked into this script.
    $cmd = Get-Command flutter.bat -CommandType Application -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue
    }
    if ($cmd) { return $cmd.Source }

    throw 'flutter.bat was not found on the PATH; pass -FlutterExe or set FLUTTER_EXE.'
}

function Resolve-Version {
    if (-not [string]::IsNullOrWhiteSpace($Version)) { return $Version }
    $pubspec = Join-Path $RepoRoot 'pubspec.yaml'
    if (-not (Test-Path -LiteralPath $pubspec)) {
        throw "pubspec.yaml not found at $pubspec; pass -Version explicitly."
    }
    $text  = Get-Content -LiteralPath $pubspec -Raw
    $match = [regex]::Match($text, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
    if (-not $match.Success) {
        throw "Could not parse an x.y.z version from $pubspec; pass -Version explicitly."
    }
    return $match.Groups[1].Value
}

function Ensure-Wix {
    $candle = Join-Path $WixDir 'candle.exe'
    $heat   = Join-Path $WixDir 'heat.exe'
    $light  = Join-Path $WixDir 'light.exe'
    if ((Test-Path -LiteralPath $candle) -and
        (Test-Path -LiteralPath $heat) -and
        (Test-Path -LiteralPath $light)) {
        Write-Host "Using WiX from $WixDir"
        return
    }

    Write-Host 'WiX v3.14 portable binaries not found; downloading...' -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $WixDir | Out-Null
    $zip = Join-Path $ToolsDir 'wix314-binaries.zip'

    # GitHub requires TLS 1.2, which is not the default on older PowerShell 5.1.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        (New-Object Net.WebClient).DownloadFile($WixZipUrl, $zip)
    }
    catch {
        throw "Failed to download WiX from $WixZipUrl : $($_.Exception.Message)"
    }

    Expand-Archive -LiteralPath $zip -DestinationPath $WixDir -Force
    Remove-Item -LiteralPath $zip -Force

    if (-not (Test-Path -LiteralPath $candle)) {
        throw "WiX download/extract did not produce $candle."
    }
    Write-Host "WiX extracted to $WixDir"
}

# --- Main ------------------------------------------------------------------
try {
    $Version = Resolve-Version
    if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
        throw "Invalid version '$Version': the MSI format requires a numeric x.y.z version."
    }
    Write-Host "Subtitle Converter MSI build - version $Version, configuration $Configuration"

    # 1. WiX toolset (downloads on first use).
    Ensure-Wix

    $heatExe   = Join-Path $WixDir 'heat.exe'
    $candleExe = Join-Path $WixDir 'candle.exe'
    $lightExe  = Join-Path $WixDir 'light.exe'

    # 2. Flutter release build.
    $configDir  = $Configuration.Substring(0, 1).ToUpper() + $Configuration.Substring(1).ToLower()
    $releaseDir = Join-Path $RepoRoot "build\windows\x64\runner\$configDir"

    if ($SkipBuild) {
        Write-Host "-SkipBuild set; reusing $releaseDir"
    }
    else {
        $flutter = Resolve-FlutterExe
        if (-not (Test-Path -LiteralPath $flutter)) {
            throw "Flutter executable not found: $flutter (use -FlutterExe or FLUTTER_EXE)."
        }
        Push-Location $RepoRoot
        try {
            Invoke-Step -Step "flutter build windows --$Configuration" -FilePath $flutter `
                -Arguments @('build', 'windows', "--$Configuration")
        }
        finally {
            Pop-Location
        }
    }

    if (-not (Test-Path -LiteralPath $releaseDir)) {
        throw "Release folder not found: $releaseDir"
    }
    $appExe = Join-Path $releaseDir $AppExeName
    if (-not (Test-Path -LiteralPath $appExe)) {
        throw "$AppExeName not found in $releaseDir"
    }

    # 3. Harvest the Release folder. -var var.ReleaseDir keeps the generated
    #    Components.wxs free of build-machine absolute paths. -sreg keeps heat
    #    from probing each DLL for self-registration entries, which none of them
    #    have (it only produces HEAT5150 noise otherwise).
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $componentsWxs = Join-Path $WorkDir 'Components.wxs'
    Invoke-Step -Step 'heat.exe: harvesting the Release folder' -FilePath $heatExe -Arguments @(
        'dir', $releaseDir,
        '-cg', 'AppFiles',
        '-dr', 'INSTALLFOLDER',
        '-var', 'var.ReleaseDir',
        '-sreg', '-gg', '-sfrag', '-srd', '-g1',
        '-o', $componentsWxs
    )

    # heat does not emit Win64="yes"; a 64-bit package installing into
    # Program Files needs it on every component (otherwise ICE80).
    $components = Get-Content -LiteralPath $componentsWxs -Raw
    if ($components -notmatch 'Win64="yes"') {
        $components = $components -replace '<Component ', '<Component Win64="yes" '
        Set-Content -LiteralPath $componentsWxs -Value $components -Encoding UTF8
    }

    # 4. Compile.
    $candleCommon = @(
        '-nologo', '-arch', 'x64',
        "-dProductVersion=$Version",
        "-dReleaseDir=$releaseDir"
    )
    $licenseRtf = Join-Path $ScriptDir 'license.rtf'
    if (-not (Test-Path -LiteralPath $licenseRtf)) {
        throw "license.rtf not found at $licenseRtf"
    }
    $candleCommon += "-dLicenseRtf=$licenseRtf"

    $iconPath = Join-Path $RepoRoot 'windows\runner\resources\app_icon.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $candleCommon += "-dIconPath=$iconPath"
    }
    else {
        Write-Host 'app_icon.ico not found; building without an application icon.' -ForegroundColor Yellow
    }

    $productObj    = Join-Path $WorkDir 'Product.wixobj'
    $componentsObj = Join-Path $WorkDir 'Components.wixobj'

    Invoke-Step -Step 'candle.exe: compiling Product.wxs' -FilePath $candleExe `
        -Arguments ($candleCommon + @($ProductWxs, '-out', $productObj))
    Invoke-Step -Step 'candle.exe: compiling Components.wxs' -FilePath $candleExe `
        -Arguments ($candleCommon + @($componentsWxs, '-out', $componentsObj))

    # 5. Link the MSI.
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $msiPath = Join-Path $OutDir "$PackageName-$Version.msi"
    if (Test-Path -LiteralPath $msiPath) { Remove-Item -LiteralPath $msiPath -Force }

    # ICE38/ICE43 demand an HKCU key path for components ICE classifies as
    # "user profile" - which is how it sees ProgramMenuFolder. This package is
    # per-machine (InstallScope=perMachine, ALLUSERS=1), so that folder resolves
    # to the all-users Start Menu tree and a machine-scoped key path is correct.
    #
    # ICE60 is suppressed deliberately: it fires on the bundled
    # MaterialIcons-Regular.otf, which is a Flutter asset loaded by the engine
    # from data\flutter_assets, not a system font. Registering it in the Font
    # table (which is what silences ICE60) would install a private icon font
    # globally, so the warning is the correct state of affairs here.
    #
    # ICE61 is suppressed deliberately: it fires because AllowSameVersionUpgrades
    # makes the upgrade version range include the current product version, which
    # is exactly the point - a rebuilt MSI without a version bump must replace
    # the previous install (see Product.wxs, MajorUpgrade).
    Invoke-Step -Step 'light.exe: linking the MSI' -FilePath $lightExe `
        -Arguments @('-nologo', '-ext', 'WixUIExtension', '-sice:ICE38', '-sice:ICE43', '-sice:ICE60', '-sice:ICE61', '-out', $msiPath, $productObj, $componentsObj)

    if (-not (Test-Path -LiteralPath $msiPath)) {
        throw "light.exe reported success but $msiPath does not exist."
    }
    $sizeMb = [math]::Round((Get-Item -LiteralPath $msiPath).Length / 1MB, 1)
    Write-Host ''
    Write-Host "Built $msiPath ($sizeMb MB)" -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
