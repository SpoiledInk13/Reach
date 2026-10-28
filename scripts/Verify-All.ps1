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
      * In a BUILDER lane, a tier marked `"builders": false` is never run either: it needs the harness
        only the integrator holds, and the integrator's sweep over the merged batch runs it. It is
        reported INTEGRATOR -- not a skip, which would hold the builder on a tier it may never run,
        and never a pass, which would claim a proof nobody made.

      * A change no tier reads runs the gate alone. process.json's `unread` lists the path prefixes
        no tier reads -- process documents, say -- and when every path changed since this tree met the
        integration branch starts with one of them, the tiers are not run and the verdict says why. No
        change at all is not this case: that tree's verification is a run this one cannot see. Empty
        by default, so nothing is skipped until a project measures what its tiers read.

      * Every tier runs from the process root with REACH_BASE set to what "changed" is measured from:
        `integration.base`, or the integration branch when there is none. A tier that diffs -- a linter
        on changed lines, a style check on added files -- reads it rather than hard-coding a branch,
        which is what an overlay's tiers did until it was named here.

    Exit 0 all tiers passed. 1 something failed. 3 something was skipped. 2 refused to start.

.PARAMETER Root
    The repository to verify. Defaults to the git root of the current directory.

.PARAMETER Tier
    Run one tier by id, and the gate. Ids are listed by -List.

.PARAMETER List
    Print the tiers and exit.

.PARAMETER SkipGate
    Run the tiers without the gate. For a tight inner loop only; a land runs both.

.PARAMETER Whole
    Run every tier whatever changed.

.PARAMETER Plan
    Print what changed since the integration branch and what a run would cover, and run nothing.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Tier,
    [switch]$List,
    [switch]$SkipGate,
    [switch]$Whole,
    [switch]$Plan
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

# ------------------------------------------------------------------------------------- scope

# A walkthrough verdict landed behind every tier, an hour of them, though no tier read the one file it
# changed -- half of one lane's lands, measured. What changed is the merge base with the integration
# branch to HEAD, plus whatever is uncommitted, and a rename counts on both sides.
$Unread = @(Get-Field $Process 'unread' @() | Where-Object { $_ })
$IntegrationBranch = (Get-Integration $Process).Base
$env:REACH_BASE = $IntegrationBranch
$Changed = $null
if (-not $Whole -and -not $Tier -and -not $SkipGate -and $Unread.Count -gt 0) {
    $mergeBase = Get-GitValue -Path $RepoRoot -Arguments @('merge-base', $IntegrationBranch, 'HEAD')
    if ($mergeBase) {
        $paths = @()
        foreach ($a in @(@('diff', '--name-only', '--no-renames', $mergeBase, 'HEAD'),
                         @('diff', '--name-only', '--no-renames', 'HEAD'),
                         @('ls-files', '--others', '--exclude-standard'))) {
            $paths += @((Invoke-Git -Path $RepoRoot -Arguments (@('-c', 'core.quotepath=off') + $a)).Lines)
        }
        $Changed = @($paths | Where-Object { $_ } | Sort-Object -Unique)
    }
}
function Test-Unread([string]$Path) { foreach ($u in $Unread) { if ($Path.StartsWith($u)) { return $true } }; return $false }
$Read = @($Changed | Where-Object { $_ -and -not (Test-Unread $_) })
$GateOnly = $null -ne $Changed -and $Changed.Count -gt 0 -and $Read.Count -eq 0

if ($Plan) {
    $why = if ($Unread.Count -eq 0) { 'process.json declares no unread paths' }
           elseif ($null -eq $Changed) { 'no comparison with the integration branch was made' }
           elseif ($Changed.Count -eq 0) { "nothing changed since $IntegrationBranch" }
           else { "{0} of {1} changed path(s) read by a tier" -f $Read.Count, $Changed.Count }
    Write-Host ("Verify-All plan -- {0}" -f $(if ($GateOnly) { "the gate alone: none of $($Changed.Count) changed path(s) is read by a tier" } else { "every tier: $why" }))
    foreach ($p in @($Changed | Where-Object { $_ })) { Write-Host ("  {0} {1}" -f $(if (Test-Unread $p) { 'unread' } else { 'READ  ' }), $p) }
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

# Whether this checkout is a builder, read off its own branch rather than a flag, so a builder that
# forgets to say so still leaves the integrator's tiers alone.
$Builder = Get-LaneOfBranch -Process $Process -RepoRoot $RepoRoot -Branch (Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD'))
if ($Builder -and $Builder.Builder -le 0) { $Builder = $null }

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

if ($GateOnly) {
    Add-Result 'tiers' 'GATE' ("none of {0} changed path(s) since {1} is read by a tier" -f $Changed.Count, $IntegrationBranch)
    $Tiers.Clear()
}

foreach ($t in $Tiers) {
    $id = Get-Field $t 'id' '?'
    $name = "tier {0} -- {1}" -f $id, (Get-Field $t 'what' '')
    if ($Tier -and $id -ne $Tier) { continue }

    if (Get-Field $t 'human' $false) {
        Add-Result $name 'HUMAN' 'not verifiable here, and nothing that runs may say otherwise'
        continue
    }

    if ($Builder -and -not (Get-Field $t 'builders' $true)) {
        Add-Result $name 'INTEGRATOR' ("{0} is a builder; the integrator's sweep runs this tier" -f $Builder.Name)
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
if ($GateOnly) {
    Write-Host "VERDICT: PASS -- the gate passed, and nothing any tier reads has changed" -ForegroundColor Green
    exit 0
}
$left = @($results | Where-Object { $_.Verdict -eq 'INTEGRATOR' })
if ($left.Count -gt 0) {
    Write-Host ("VERDICT: PASS -- {0} clean in this builder, {1} left to the integrator's sweep" -f ($results.Count - $left.Count), $left.Count) -ForegroundColor Green
    exit 0
}
Write-Host ("VERDICT: PASS -- {0} clean" -f $results.Count) -ForegroundColor Green
exit 0
