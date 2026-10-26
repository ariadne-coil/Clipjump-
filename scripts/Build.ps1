[CmdletBinding()]
param([ValidateSet('x64', 'x86')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dependencies = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json
$downloadRoot = Join-Path $projectRoot '.tools\downloads'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

function Get-VerifiedArchive($Specification, [string]$Name) {
    $archivePath = Join-Path $downloadRoot $Name
    if (!(Test-Path -LiteralPath $archivePath)) {
        Invoke-WebRequest -Uri $Specification.url -OutFile $archivePath
    }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne $Specification.sha256) {
        throw "Checksum mismatch for $Name. The archive was not executed or extracted."
    }
    return $archivePath
}

$ahkArchive = Get-VerifiedArchive $dependencies.autohotkey "autohotkey-$($dependencies.autohotkey.version).zip"
$sqliteSpec = $dependencies.sqlite.$Architecture
$sqliteArchive = Get-VerifiedArchive $sqliteSpec "sqlite-$($dependencies.sqlite.version)-$Architecture.zip"
$ahkExtract = Join-Path $downloadRoot 'autohotkey-v2'
$sqliteExtract = Join-Path $downloadRoot "sqlite-$Architecture"
Expand-Archive -LiteralPath $ahkArchive -DestinationPath $ahkExtract -Force
Expand-Archive -LiteralPath $sqliteArchive -DestinationPath $sqliteExtract -Force

$runtimeRoot = Join-Path $projectRoot "runtime-v2\$Architecture"
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$ahkBinary = if ($Architecture -eq 'x64') { 'AutoHotkey64.exe' } else { 'AutoHotkey32.exe' }
Copy-Item -LiteralPath (Join-Path $ahkExtract $ahkBinary) -Destination (Join-Path $runtimeRoot 'AutoHotkey.exe') -Force
Copy-Item -LiteralPath (Join-Path $sqliteExtract 'sqlite3.dll') -Destination (Join-Path $runtimeRoot 'sqlite3.dll') -Force
Copy-Item -LiteralPath (Join-Path $ahkExtract 'license.txt') -Destination (Join-Path $runtimeRoot 'AutoHotkey-LICENSE.txt') -Force

# Assemble a new directory on every build. No developer cache, user settings,
# clipboard history, or stale files from previous builds enter the package.
$buildId = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$packageRoot = Join-Path $projectRoot "dist\Clipjump-Modern-$Architecture-$buildId"
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
foreach ($source in @('Clipjump.ahk', 'publicAPI.ahk', 'Readme.md', 'NOTICE.txt', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'Start-Clipjump.cmd')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $source) -Destination $packageRoot
}
foreach ($directory in @('v2', 'icons', 'languages', 'docs')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $packageRoot -Recurse
}
$packagePlugins = Join-Path $packageRoot 'plugins-v2'
New-Item -ItemType Directory -Path $packagePlugins -Force | Out-Null
foreach ($example in @('README.md', 'User.example.ahk')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "plugins-v2\$example") -Destination $packagePlugins
}
$packageRuntime = Join-Path $packageRoot "runtime-v2\$Architecture"
New-Item -ItemType Directory -Path $packageRuntime -Force | Out-Null
Copy-Item -Path (Join-Path $runtimeRoot '*') -Destination $packageRuntime
$archiveOutput = Join-Path $projectRoot "dist\Clipjump-Modern-13.0.0-beta.1-$Architecture.zip"
Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $archiveOutput -Force
Get-FileHash -LiteralPath $archiveOutput -Algorithm SHA256 | Format-List
Write-Output "Package directory: $packageRoot"
