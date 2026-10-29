#Requires -Version 7

<#
.SYNOPSIS
Build a portable Windows x64 package of eSpeak NG from the official MSI release.

.DESCRIPTION
Downloads the official installer, checks its SHA-256, unpacks it without installing anything, and
zips the program, all of its language data, the Visual C++ runtime DLLs it needs, and its license
files into dist/espeak-ng-<version>-windows-x64.zip.

Needs Visual Studio 2022 or its Build Tools with the C++ workload, for the runtime DLLs.
#>

[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path $PSScriptRoot '..' 'dist'),
    [string] $WorkDir = (Join-Path $PSScriptRoot '..' 'work' 'windows')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$VcRuntimeFiles = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

function Get-VerifiedDownload {
    <#
    .SYNOPSIS
    Download a file unless a copy with the expected SHA-256 is already there, then check its hash.
    #>
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Sha256,
        [Parameter(Mandatory)] [string] $Path
    )

    $isCached = (Test-Path $Path) -and ((Get-FileHash $Path -Algorithm SHA256).Hash -eq $Sha256)

    if (-not $isCached) {
        Write-Host "Downloading $Url"
        Invoke-WebRequest -Uri $Url -OutFile $Path
    }

    $actualHash = (Get-FileHash $Path -Algorithm SHA256).Hash

    if ($actualHash -ne $Sha256) {
        throw "SHA-256 mismatch for $Url`n  expected $Sha256`n  actual   $actualHash"
    }
}

function Expand-Msi {
    <#
    .SYNOPSIS
    Unpack an MSI's files into a folder with an administrative install, which installs nothing on the machine.
    #>
    param(
        [Parameter(Mandatory)] [string] $MsiPath,
        [Parameter(Mandatory)] [string] $Destination
    )

    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }

    $arguments = @('/a', "`"$MsiPath`"", '/qn', "TARGETDIR=`"$Destination`"")

    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "msiexec failed to unpack $MsiPath (exit code $($process.ExitCode))"
    }
}

function Get-VcRuntimeFolder {
    <#
    .SYNOPSIS
    Find the newest x64 Visual C++ runtime folder in Visual Studio's redistributable files.
    #>
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio' 'Installer' 'vswhere.exe'

    if (-not (Test-Path $vswhere)) {
        throw 'Visual Studio was not found (vswhere.exe is missing).'
    }

    $installations = & $vswhere -products '*' -sort -property installationPath

    foreach ($installation in $installations) {
        $redistRoot = Join-Path $installation 'VC' 'Redist' 'MSVC'

        if (-not (Test-Path $redistRoot)) {
            continue
        }

        $newestRedist = Get-ChildItem $redistRoot -Directory |
            Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
            Sort-Object { [version] $_.Name } -Descending |
            Select-Object -First 1

        if ($null -eq $newestRedist) {
            continue
        }

        $runtimeFolder = Get-ChildItem (Join-Path $newestRedist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
            Select-Object -First 1

        if ($null -ne $runtimeFolder) {
            return $runtimeFolder.FullName
        }
    }

    throw 'No Visual C++ x64 runtime found. Install Visual Studio or its Build Tools with the C++ workload.'
}

function Write-Notice {
    <#
    .SYNOPSIS
    Write NOTICE.txt, which says what is in the package, where it came from, and under which licenses.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [string] $Path
    )

    $otherLicenses = ($Config.licenseFiles | Where-Object { $_ -ne 'COPYING' }) -join ', '

    $notice = @"
eSpeak NG $($Config.version) for Windows (x64)

This folder contains the official eSpeak NG $($Config.version) Windows release, unmodified, repackaged
so it runs from any folder without installation.

espeak-ng.exe, libespeak-ng.dll, espeak-ng-data\
    eSpeak NG, licensed under the GNU General Public License v3.0 or later (see COPYING).
    Some parts are under other licenses: see $otherLicenses.
    Original installer: $($Config.windows.msiUrl)
    Source code:        $($Config.sourceUrl)

$($VcRuntimeFiles -join ', ')
    Microsoft Visual C++ runtime, redistributed under the Microsoft Visual Studio license terms.

Usage
    espeak-ng.exe --path="<this folder>" [options]

    Always pass --path so the bundled data is used instead of an installed copy.
"@

    Set-Content -Path $Path -Value $notice -Encoding utf8NoBOM
}

function Test-Package {
    <#
    .SYNOPSIS
    Check the packaged program runs from its folder and converts a known phrase to the expected phonemes.
    #>
    param(
        [Parameter(Mandatory)] [string] $PackageDir,
        [Parameter(Mandatory)] [string] $WorkDir
    )

    $inputFile = Join-Path $WorkDir 'smoke-test.txt'

    Set-Content -Path $inputFile -Value 'hello world' -Encoding utf8NoBOM -NoNewline

    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        $output = & (Join-Path $PackageDir 'espeak-ng.exe') "--path=$PackageDir" -q --ipa -v en-us -b 1 -f $inputFile
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Smoke test failed: espeak-ng.exe exited with code $LASTEXITCODE"
    }

    $phonemes = ($output -join ' ').Trim()
    $expected = 'həlˈoʊ wˈɜːld'

    if ($phonemes -ne $expected) {
        throw "Smoke test failed: expected '$expected', got '$phonemes'"
    }

    Write-Host "Smoke test passed: 'hello world' -> $phonemes"
}

# Build --------------------------------------------------------------------------------------------

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$config = Get-Content (Join-Path $repoRoot 'espeak-ng.json') -Raw | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $OutputDir, $WorkDir | Out-Null

$OutputDir = (Resolve-Path $OutputDir).Path
$WorkDir = (Resolve-Path $WorkDir).Path

$msiPath = Join-Path $WorkDir 'espeak-ng.msi'

Get-VerifiedDownload -Url $config.windows.msiUrl -Sha256 $config.windows.msiSha256 -Path $msiPath

$extractDir = Join-Path $WorkDir 'msi'

Expand-Msi -MsiPath $msiPath -Destination $extractDir

$programDir = Join-Path $extractDir 'eSpeak NG'
$packageDir = Join-Path $WorkDir 'espeak-ng'

if (Test-Path $packageDir) {
    Remove-Item $packageDir -Recurse -Force
}

New-Item -ItemType Directory -Path $packageDir | Out-Null

foreach ($item in @('espeak-ng.exe', 'libespeak-ng.dll', 'espeak-ng-data')) {
    Copy-Item -Path (Join-Path $programDir $item) -Destination $packageDir -Recurse
}

$vcRuntimeFolder = Get-VcRuntimeFolder

Write-Host "Using Visual C++ runtime from $vcRuntimeFolder"

foreach ($file in $VcRuntimeFiles) {
    Copy-Item -Path (Join-Path $vcRuntimeFolder $file) -Destination $packageDir
}

foreach ($file in $config.licenseFiles) {
    Invoke-WebRequest -Uri "$($config.licenseBaseUrl)/$file" -OutFile (Join-Path $packageDir $file)
}

Write-Notice -Config $config -Path (Join-Path $packageDir 'NOTICE.txt')

Test-Package -PackageDir $packageDir -WorkDir $WorkDir

$zipPath = Join-Path $OutputDir "espeak-ng-$($config.version)-windows-x64.zip"

Compress-Archive -Path $packageDir -DestinationPath $zipPath -Force

$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "Created $zipPath"
Write-Host "SHA-256 $zipHash"
