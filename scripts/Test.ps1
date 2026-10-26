[CmdletBinding()]
param([ValidateSet('x64', 'x86')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $projectRoot "runtime\$Architecture\AutoHotkey.exe"
if (!(Test-Path -LiteralPath $runtime)) { throw 'Run scripts/Build.ps1 first.' }
$logRoot = Join-Path $projectRoot 'test-results'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Invoke-AhkCheck([string]$Name, [string]$Script, [string[]]$ExtraArguments = @()) {
    $stdoutPath = Join-Path $logRoot "$Name-$Architecture.log"
    $stderrPath = Join-Path $logRoot "$Name-$Architecture.err"
    $arguments = @('/ErrorStdOut=UTF-8', ('"' + $Script + '"')) + $ExtraArguments
    $checkProcess = Start-Process -FilePath $runtime -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if (!$checkProcess.WaitForExit(30000)) {
        Stop-Process -Id $checkProcess.Id
        throw "$Name exceeded the test deadline."
    }
    $checkProcess.Refresh()
    $output = Get-Content -LiteralPath $stdoutPath -Raw
    $errors = Get-Content -LiteralPath $stderrPath -Raw
    Write-Host $output
    if ($checkProcess.ExitCode -ne 0 -or $errors -or $output -match '(?m)^FAIL ' -or !$output) {
        throw "$Name failed with exit code $($checkProcess.ExitCode). $errors"
    }
    return $output
}

foreach ($suite in @('clipboard', 'history')) {
    $output = Invoke-AhkCheck $suite (Join-Path $projectRoot "tests\$suite-regression.ahk")
    if ($output -notmatch 'RESULT \d+ checks; 0 failures;') { throw "$suite did not report completion." }
}

$package = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'dist') -Directory -Filter "Clipjump-Modern-$Architecture-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!$package) { throw 'No portable package found. Build it first.' }
$smokeOutput = Invoke-AhkCheck 'startup' (Join-Path $package.FullName 'Clipjump.ahk') @('--smoke-test')
if ($smokeOutput -notmatch 'STARTUP_OK clipboard_unchanged=1') { throw 'Startup changed the live clipboard or failed.' }
Write-Output "All $Architecture checks passed."
