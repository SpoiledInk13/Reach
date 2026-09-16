#Requires -Version 5.1
<#
.SYNOPSIS
    Reports what this repository's reach setup is missing, against the version installed now.

.DESCRIPTION
    Adoption happens once, but reach keeps changing. A repository adopted against an earlier version
    is missing whatever arrived since, and nothing about that is visible: the gate passes, the tiers
    run, and a mechanism that was never wired in simply never fires. A check nobody exercises is
    indistinguishable from a check that finds nothing.

    So the gap is measured rather than remembered. This is what /reach:adopt reads when it is run
    against a repository that has already adopted -- which turns filling in what is missing from a
    judgement call into a list.

    Exit 0 when nothing is missing, 1 when something is, 2 when it could not look.

.PARAMETER Root
    The repository. Defaults to the git root of the current directory.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) {
    Write-Host 'NOT ADOPTED: there is no process.json here. Run /reach:adopt.' -ForegroundColor Yellow
    exit 1
}

$installed = '0.0.0'
$manifest = Join-Path (Split-Path -Parent $PSScriptRoot) '.claude-plugin/plugin.json'
if (Test-Path -LiteralPath $manifest) {
    $installed = [string](Get-Field (Read-TextUtf8 $manifest | ConvertFrom-Json) 'version' '0.0.0')
}

$gaps = New-Object System.Collections.Generic.List[object]
function Add-Gap {
    param([string]$What, [string]$Why, [string]$Fix)
    $gaps.Add([pscustomobject]@{ What = $What; Why = $Why; Fix = $Fix }) | Out-Null
}

# ------------------------------------------------------------------------------------ the config

$adoptedAt = [string](Get-Field $Process 'reach' '')
if (-not $adoptedAt) {
    Add-Gap 'process.json records no reach version' `
            'Nothing can tell what this repository was set up against, so nothing can tell what it is missing.' `
            ("add `"reach`": `"{0}`"" -f $installed)
}

if (-not (Get-Field $Process 'spine' $null)) {
    Add-Gap 'no spine declared' 'The architecture document is what every other document is checked against, and its cap is unenforced without this.' 'add spine { path, cap }'
}
if (-not (Get-Field $Process 'unit' $null)) {
    Add-Gap 'no unit documents declared' 'The roster is the backlog. Without it the build command has nothing to read.' 'add unit { noun, dir, cap }'
}
if (-not (Get-Field $Process 'evidence' $null)) {
    Add-Gap 'no evidence declared' 'Nothing connects a claim to the test that proves it, so built means written.' 'add evidence { noun, mark, search }'
}
if (-not (Get-Field $Process 'archive' $null)) {
    Add-Gap 'no archive declared' 'Replacing is only safe because what it replaced is still there, read-only.' 'add archive'
}

$tiers = ConvertTo-Array (Get-Field $Process 'tiers' @())
if ($tiers.Count -eq 0) {
    Add-Gap 'no tiers declared' 'Verify-All has nothing to run, so a green verdict covers only the gate.' 'add tiers, cheapest first'
} else {
    $runnable = @($tiers | Where-Object { (Get-Field $_ 'run' '') -and -not (Get-Field $_ 'human' $false) })
    if ($runnable.Count -eq 0) {
        Add-Gap 'no tier has a command' 'Every tier is declared and none can run. That reports as skipped, which is honest, but nothing is being verified.' 'give each non-human tier a run command'
    }
}

# ---------------------------------------------------------------------------------- the lane model

$integration = Get-Field $Process 'integration' $null
$lanes = ConvertTo-Array (Get-Field $Process 'lanes' @())

if (-not $integration) {
    Add-Gap 'no integration branch declared' 'Landing has no target, so work cannot leave a lane by any route this understands.' 'add integration { branch, primary, mode }'
} else {
    $resolved = Get-Integration $Process
    if ($resolved.Mode -eq 'objects') {
        $exists = Invoke-Git -Path $RepoRoot -Arguments @('rev-parse', '--verify', "refs/heads/$($resolved.Branch)")
        if ($exists.Code -ne 0) {
            Add-Gap ("the integration branch '{0}' does not exist" -f $resolved.Branch) 'Nothing can land.' ("git branch {0}" -f $resolved.Branch)
        } else {
            $checkedOut = Get-WorktreeFor -Path $RepoRoot -Branch $resolved.Branch
            if ($checkedOut) {
                Add-Gap ("'{0}' is checked out at {1}" -f $resolved.Branch, $checkedOut) `
                        'Landing advances it by ref; doing that to a branch some worktree has checked out leaves that worktree describing a commit that is no longer its HEAD.' `
                        ("move that checkout to '{0}'" -f $resolved.Primary)
            }
        }
    }
}

if ($lanes.Count -eq 0) {
    Add-Gap 'no lanes declared' 'Commands run in the checkout you are working in, so two agents share one index and one working tree, and a run tests a tree other than the one that lands.' 'add lanes'
} else {
    foreach ($lane in $lanes) {
        $name = Get-Field $lane 'name' '?'
        $config = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $name
        if (-not $config) { continue }
        if (-not (Test-Path -LiteralPath $config.Worktree)) {
            Add-Gap ("lane '{0}' is declared but not seeded" -f $name) 'It cannot run.' ("Scripts/reach.ps1 lane seed {0}" -f $name)
        }
        if (-not $config.Command) {
            Add-Gap ("lane '{0}' names no command" -f $name) 'The supervisor has nothing to run in it.' 'add command'
        }
    }
}

# ------------------------------------------------------------------------------------ the files

$shim = Join-Path $RepoRoot 'Scripts/reach.ps1'
if (-not (Test-Path -LiteralPath $shim)) {
    Add-Gap 'no Scripts/reach.ps1' 'Every documented command names a path that moves with the plugin version.' 'copy templates/reach.ps1 from the plugin and commit it'
}

$spine = Get-Field $Process 'spine' $null
if ($spine) {
    $path = Join-Path $RepoRoot (Get-Field $spine 'path' '')
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Gap ("the spine document does not exist at {0}" -f (Get-Field $spine 'path' '')) 'Everything else is checked against a document that is not there.' 'start it from templates/spine.md'
    } elseif ([int](Get-Field $spine 'cap' 0) -le 0) {
        Add-Gap 'the spine has no cap' 'A document with no ceiling grows, because adding is always cheaper than reconciling.' 'set it from the current size plus a small margin'
    }
}

$unit = Get-Field $Process 'unit' $null
if ($unit) {
    $dir = Join-Path $RepoRoot (Get-Field $unit 'dir' '')
    if (-not (Test-Path -LiteralPath $dir)) {
        Add-Gap ("the unit documents directory does not exist at {0}" -f (Get-Field $unit 'dir' '')) 'The backlog is empty because it is absent, which reads identically to being finished.' 'create it and start one from templates/unit.md'
    } else {
        $documents = @(Get-ChildItem -LiteralPath $dir -Filter *.md -File)
        if ($documents.Count -eq 0) {
            Add-Gap 'there are no unit documents' 'The build command has nothing to read, and the gate measures nothing.' 'write the first from templates/unit.md'
        }
    }
    if ([int](Get-Field $unit 'cap' 0) -le 0) {
        Add-Gap 'unit documents have no cap' 'Without one they grow, and a unit that outgrows its cap is the signal that it is two units.' 'set it'
    }
}

$human = Get-Field $Process 'human' $null
if ($human) {
    $doc = Join-Path $RepoRoot (Get-Field $human 'doc' '')
    if (-not (Test-Path -LiteralPath $doc)) {
        Add-Gap ("the walkthrough document does not exist at {0}" -f (Get-Field $human 'doc' '')) 'The milestone command has nothing to read.' 'start it from templates/walkthroughs.md'
    }
}

# A check that can never fire is the decoration this whole process condemns. AdoptionCounts reads the
# `adoption` field, so a repository with a corpus still to distil and no map gets a silent no-op.
$adoption = Get-Field $Process 'adoption' $null
if ($adoption -and -not (Test-Path -LiteralPath (Join-Path $RepoRoot $adoption))) {
    Add-Gap ("process.json names an adoption map at {0}, which does not exist" -f $adoption) `
            'AdoptionCounts reads that path and silently does nothing, so a stalled distillation stays invisible.' `
            'create it, or remove the field'
}

# --------------------------------------------------------------------------------------- report

Write-Host ("reach audit -- {0}" -f $RepoRoot) -ForegroundColor Cyan
Write-Host ("  installed {0}   this repository was set up against {1}" -f $installed, $(if ($adoptedAt) { $adoptedAt } else { 'an unrecorded version' })) -ForegroundColor DarkGray
Write-Host ''

if ($gaps.Count -eq 0) {
    Write-Host 'COMPLETE -- nothing this version expects is missing.' -ForegroundColor Green
    exit 0
}

foreach ($gap in $gaps) {
    Write-Host ("  MISSING  {0}" -f $gap.What) -ForegroundColor Yellow
    Write-Host ("           {0}" -f $gap.Why) -ForegroundColor DarkGray
    Write-Host ("           -> {0}" -f $gap.Fix) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host ("{0} gap(s). Run /reach:adopt to fill them -- it reads this and asks before writing." -f $gaps.Count) -ForegroundColor Yellow
exit 1
