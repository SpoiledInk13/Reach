#Requires -Version 5.1
<#
.SYNOPSIS
    The blocking gate. A driver plus whatever checks the project has opted into.

.DESCRIPTION
    This file contains no checks. It finds them: the generic ones ship beside it under
    gate-checks/, and the project's own live wherever process.json says. Every check is one
    .ps1 file defining exactly one function named Test-<filename>, so a check is found by
    reading the directory rather than by editing a list here.

    Two rules govern what may live in either folder, and they are the whole reason this stays
    small. A check is added when a real defect proves one is wanted, never pre-emptively. And
    every check is negative-controllable: break the thing on purpose, watch this go red, restore.
    A check whose failure path has never been observed is decoration, and decoration is how a gate
    reaches eight thousand lines and still misses a file growing 85% under its own watch.

    Written to the PowerShell 5.1 subset so it runs on Windows PowerShell and on pwsh anywhere,
    which is what lets the same gate run locally and in CI.

.PARAMETER Root
    The repository to check. Defaults to the git root of the current directory.

.PARAMETER Check
    Run one check by name instead of all of them. Names are listed by -List.

.PARAMETER List
    Print the check names, where each came from, and exit.

.EXAMPLE
    Verify-Gate.ps1
    Verify-Gate.ps1 -Check DocumentCaps
    Verify-Gate.ps1 -Root C:\Projects\thing -List
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Check,
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

# $PSScriptRoot is empty inside param() defaults on 5.1, so everything resolves here instead.
$ScriptRoot = $PSScriptRoot





# ------------------------------------------------------------------------------- the repository

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) {
    Write-Host "REFUSED: not in a git repository, and no -Root given." -ForegroundColor Red
    exit 2
}

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) {
    Write-Host ("REFUSED: no process.json in {0}. Run /reach:adopt first." -f $RepoRoot) -ForegroundColor Red
    exit 2
}

# ------------------------------------------------------------------------------------- failures

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:CurrentCheck = ''

function Add-Failure {
    # The check name is implicit so a check cannot mislabel its own failures, which is a thing that
    # happened: a copied check kept the name it was copied from and the fix went to the wrong file.
    param([string]$Message)
    $script:Failures.Add(("[{0}] {1}" -f $script:CurrentCheck, $Message)) | Out-Null
}

# -------------------------------------------------------------------------------- finding checks

function Get-ChecksIn {
    param([string]$Directory, [string]$Origin)
    $found = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Directory)) { return $found }

    foreach ($file in (Get-ChildItem -LiteralPath $Directory -Filter *.ps1 -File | Sort-Object Name)) {
        $name = $file.BaseName
        . $file.FullName
        $function = Get-Item -LiteralPath ("function:Test-{0}" -f $name) -ErrorAction SilentlyContinue
        if (-not $function) {
            Write-Host ("REFUSED: {0} defines no function Test-{1}. A check file is named for the function it defines." -f $file.FullName, $name) -ForegroundColor Red
            exit 2
        }
        $found.Add([pscustomobject]@{ Name = $name; Origin = $Origin; Run = $function.ScriptBlock }) | Out-Null
    }
    return $found
}

$Checks = New-Object System.Collections.Generic.List[object]
# Names kept separately: a property access across an empty generic List throws under StrictMode, so
# `$Checks.Name -contains ...` is clean on the second folder and fatal on a project with no checks
# of its own -- which is every project on the day it adopts.
$Named = New-Object System.Collections.Generic.HashSet[string]

# Two traps, both of which present as the same unhelpful "property 'Name' cannot be found".
#
# The loop variable is $entry and never $check, because PowerShell variable names are case
# insensitive: `foreach ($check in ...)` assigns to the -Check PARAMETER, which is declared [string],
# and the type constraint silently stringifies every object as it goes past. The loop then runs the
# right number of times over the wrong things, which is a long way from where the error surfaces.
#
# And @() around every call, because `return $list` on an EMPTY list emits nothing, the call site
# sees $null, and `foreach ($x in $null)` runs its body ONCE with $x unset -- so a project with no
# checks of its own, which is every project on the day it adopts, would enter the loop anyway.
foreach ($entry in @(Get-ChecksIn (Join-Path $ScriptRoot 'gate-checks') 'reach')) {
    $Checks.Add($entry) | Out-Null
    $Named.Add($entry.Name) | Out-Null
}

$projectChecks = Get-Field $Process 'checks' 'Scripts/gate-checks'
foreach ($entry in @(Get-ChecksIn (Join-Path $RepoRoot $projectChecks) 'project')) {
    if ($Named.Contains($entry.Name)) {
        Write-Host ("REFUSED: project check '{0}' has the same name as a reach check. Rename it; two checks answering to one name means -Check runs only one of them." -f $entry.Name) -ForegroundColor Red
        exit 2
    }
    $Checks.Add($entry) | Out-Null
    $Named.Add($entry.Name) | Out-Null
}

if ($Checks.Count -eq 0) {
    Write-Host "REFUSED: no checks found. A gate with no checks passes everything." -ForegroundColor Red
    exit 2
}

if ($List) {
    foreach ($entry in $Checks) { Write-Host ("{0,-24} {1}" -f $entry.Name, $entry.Origin) }
    exit 0
}

# ---------------------------------------------------------------------------------------- run

# Assigned inside the branches and cast, never captured from an if-expression: a single-element
# array written to the output stream is unwrapped to a scalar, and .Count on a scalar string throws
# under StrictMode Latest. That turns a whole negative-control run into a probe that cannot tell a
# firing check from a broken one.
[object[]]$toRun = @()
if ($Check) {
    $match = $Checks | Where-Object { $_.Name -eq $Check }
    if (-not $match) {
        Write-Host ("REFUSED: no check named '{0}'. Use -List." -f $Check) -ForegroundColor Red
        exit 2
    }
    [object[]]$toRun = @($match)
} else {
    [object[]]$toRun = $Checks.ToArray()
}

Write-Host ("Verify-Gate -- {0} check(s) over {1}" -f $toRun.Count, $RepoRoot) -ForegroundColor Cyan
foreach ($entry in $toRun) {
    $script:CurrentCheck = $entry.Name
    & $entry.Run
}

if ($script:Failures.Count -gt 0) {
    Write-Host ""
    Write-Host ("BLOCKING: {0} failure(s)" -f $script:Failures.Count) -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host ("  {0}" -f $failure) -ForegroundColor Red }
    exit 1
}

Write-Host ("PASS -- {0} check(s) clean" -f $toRun.Count) -ForegroundColor Green
exit 0
