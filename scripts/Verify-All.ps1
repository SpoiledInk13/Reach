#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the gate and every tier the project declares, and reports one verdict.

.DESCRIPTION
    The tiers come from process.json. Their number and their content are the project's business --
    a compiled project has a cheap unit tier and an expensive artifact tier; a web project has unit,
    integration and browser; a mod has tests and a load into the host application. What is not the
    project's business is the contract between them, which is this:

      * They run cheapest first, so the fast red arrives in seconds rather than minutes.
      * A non-zero exit is never a pass. Exit 0 is not always one either -- several build tools exit
        0 after doing nothing at all -- which is why a tier may declare a `proves` pattern its output
        has to contain before its zero is believed.
      * A tier that could not run is reported SKIPPED and the whole run exits 3. It is never folded
        into a pass, because a pass that silently covers less than it did yesterday is worse than a
        failure: it is a failure you will not look for.
      * A tier marked human is never run here. If an outcome can only be verified by looking at it or
        listening to it, no script can report on it, and one that pretends to is lying.

    Exit 0 all tiers passed. 1 something failed. 3 something was skipped. 2 refused to start.

.PARAMETER Root
    The repository to verify. Defaults to the git root of the current directory.

.PARAMETER Tier
    Run one tier by id, and the gate. Ids are listed by -List.

.PARAMETER List
    Print the tiers and exit.

.PARAMETER SkipGate
    Run the tiers without the gate. For a tight inner loop only; a land runs both.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Tier,
    [switch]$List,
    [switch]$SkipGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$ScriptRoot = $PSScriptRoot
$OnWindows = (-not (Test-Path variable:IsWindows)) -or $IsWindows



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

$Tiers = New-Object System.Collections.Generic.List[object]
foreach ($t in (Get-Field $Process 'tiers' @())) { $Tiers.Add($t) | Out-Null }

if ($List) {
    foreach ($t in $Tiers) {
        $how = if (Get-Field $t 'human' $false) { 'the owner, on a build they run' } else { Get-Field $t 'run' '(nothing declared)' }
        Write-Host ("{0,-4} {1,-34} {2,-10} {3}" -f (Get-Field $t 'id' '?'), (Get-Field $t 'what' ''), (Get-Field $t 'cost' ''), $how)
    }
    exit 0
}

# --------------------------------------------------------------------------------- running one

function Invoke-Shell {
    param([string]$Command)
    Push-Location -LiteralPath $RepoRoot
    try {
        if ($OnWindows) {
            $output = & cmd /c $Command 2>&1
        } else {
            $output = & /bin/sh -c $Command 2>&1
        }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($output | Out-String) }
    } finally {
        Pop-Location
    }
}

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Name, [string]$Verdict, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Name = $Name; Verdict = $Verdict; Detail = $Detail }) | Out-Null
    $colour = switch ($Verdict) {
        'PASS'    { 'Green' }
        'FAIL'    { 'Red' }
        'SKIPPED' { 'Yellow' }
        default   { 'Gray' }
    }
    Write-Host ("  {0,-9} {1} {2}" -f $Verdict, $Name, $Detail) -ForegroundColor $colour
}

Write-Host ("Verify-All -- {0}" -f $RepoRoot) -ForegroundColor Cyan

if (-not $SkipGate -and -not $Tier) {
    # The gate prints its own failures, and they are left visible on purpose: sending someone away to
    # re-run a second command to find out what broke costs more than the few lines it saves. Piping
    # this to Out-Null would not have suppressed them anyway -- the gate writes with Write-Host, which
    # goes to the host rather than down the pipeline.
    $gate = Join-Path $ScriptRoot 'Verify-Gate.ps1'
    & $gate -Root $RepoRoot
    $code = $LASTEXITCODE
    if ($code -eq 0) { Add-Result 'gate' 'PASS' }
    elseif ($code -eq 2) { Add-Result 'gate' 'SKIPPED' 'refused to start' }
    else { Add-Result 'gate' 'FAIL' 'the failures are listed above' }
}

foreach ($t in $Tiers) {
    $id = Get-Field $t 'id' '?'
    $name = "tier {0} -- {1}" -f $id, (Get-Field $t 'what' '')
    if ($Tier -and $id -ne $Tier) { continue }

    if (Get-Field $t 'human' $false) {
        Add-Result $name 'HUMAN' 'not verifiable here, and nothing that runs may say otherwise'
        continue
    }

    $command = Get-Field $t 'run' $null
    if (-not $command) {
        Add-Result $name 'SKIPPED' 'no command declared'
        continue
    }

    # A tier can be genuinely unavailable -- no editor resident, no device attached, no network. That
    # is a skip, and a skip is loud, because the alternative is a green run that quietly covers less.
    $requires = Get-Field $t 'requires' $null
    if ($requires) {
        $probe = Invoke-Shell $requires
        if ($probe.Code -ne 0) {
            Add-Result $name 'SKIPPED' ("'{0}' says this tier cannot run here" -f $requires)
            continue
        }
    }

    $result = Invoke-Shell $command
    if ($result.Code -ne 0) {
        Add-Result $name 'FAIL' ("exit {0}" -f $result.Code)
        continue
    }

    # Exit 0 is not always a pass. Some build tools print Succeeded having recompiled nothing, and
    # some test runners exit 0 when a filter matched no tests at all -- both of which read as green
    # and cover nothing. A tier that has been bitten by that declares what its output must contain.
    $proves = Get-Field $t 'proves' $null
    if ($proves -and $result.Output -notmatch $proves) {
        Add-Result $name 'FAIL' ("exit 0, but its output does not match /{0}/ -- exit 0 here does not mean the work happened" -f $proves)
        continue
    }

    Add-Result $name 'PASS'
}

# ------------------------------------------------------------------------------------- verdict

$failed  = @($results | Where-Object { $_.Verdict -eq 'FAIL' })
$skipped = @($results | Where-Object { $_.Verdict -eq 'SKIPPED' })

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host ("VERDICT: FAIL -- {0} of {1} failed" -f $failed.Count, $results.Count) -ForegroundColor Red
    exit 1
}
if ($skipped.Count -gt 0) {
    Write-Host ("VERDICT: INCOMPLETE -- {0} skipped, nothing failed. A skip is not a pass." -f $skipped.Count) -ForegroundColor Yellow
    exit 3
}
Write-Host ("VERDICT: PASS -- {0} clean" -f $results.Count) -ForegroundColor Green
exit 0
