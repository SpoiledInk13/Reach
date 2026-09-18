#Requires -Version 5.1
<#
.SYNOPSIS
    Creates and maintains lanes: a persistent worktree per command, each on its own branch.

.DESCRIPTION
    A lane removes the two collisions that come from two agents sharing one checkout -- one index they
    both stage into, and one working tree one of them edits while the other is mid-task. It also means
    a command runs its tiers against exactly the tree that will land, where a lane that merely mirrored
    the primary's source would be testing something else.

    The model it requires, and which /reach:adopt sets up:

      * the integration branch is checked out NOWHERE, so a land can advance it by ref while every
        lane is busy;
      * the primary checkout sits on its own branch, yours and /reach:ideate's;
      * each lane is a worktree on its own long-lived branch.

    Verbs: seed, sync, status, remove.

      Lane.ps1 seed build          create the worktree and branch, and warm it
      Lane.ps1 sync build          bring the integration branch into the lane
      Lane.ps1 sync -Primary       bring it into the primary checkout, which nothing else syncs
      Lane.ps1 status              the primary and every lane: branch, lock, dirt, ahead or behind
      Lane.ps1 remove build        remove the worktree; the branch stays

    `sync -Primary` is here rather than in a verb of its own because it is the same operation on the
    one working tree that is not a lane -- and the tree whose staleness is invisible, since no land
    touches it and nothing in it changes when the ref it does not hold moves.

.PARAMETER Root
    The repository. Defaults to the git root of the current directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet('seed', 'sync', 'status', 'remove')][string]$Verb,
    [Parameter(Position = 1)][string]$Lane,
    [string]$Root,
    [switch]$Force,
    [switch]$Primary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }

$integration = Get-Integration $Process
$names = Get-LaneNames $Process

function Get-Lane {
    param([string]$Name)
    if (-not $Name) {
        Write-Host ("REFUSED: name a lane. Known: {0}" -f ($names -join ', ')) -ForegroundColor Red
        exit 2
    }
    $lane = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $Name
    if (-not $lane) {
        Write-Host ("REFUSED: no lane named '{0}' in process.json. Known: {1}" -f $Name, ($names -join ', ')) -ForegroundColor Red
        exit 2
    }
    return $lane
}

# ------------------------------------------------------------------------------------------ seed

function Invoke-Seed {
    $lane = Get-Lane $Lane

    if (Test-Path -LiteralPath $lane.Worktree) {
        Write-Host ("Already there: {0}" -f $lane.Worktree) -ForegroundColor Yellow
        exit 0
    }

    # Windows resolves paths against MAX_PATH, and a build cache nests deeply enough that a long lane
    # directory fails somewhere inside it rather than here -- as a file the toolchain cannot write,
    # which reads as a broken toolchain rather than a long path.
    $leaf = Split-Path -Leaf $lane.Worktree
    if ($leaf.Length -gt 18) {
        Write-Host ("REFUSED: the lane directory '{0}' is {1} characters. Keep it to 18 or fewer -- a deep build cache under a long path fails inside the toolchain, where it looks like anything but a path length." -f $leaf, $leaf.Length) -ForegroundColor Red
        exit 2
    }

    $exists = Invoke-Git -Path $RepoRoot -Arguments @('rev-parse', '--verify', "refs/heads/$($lane.Branch)")
    $arguments = if ($exists.Code -eq 0) {
        @('worktree', 'add', $lane.Worktree, $lane.Branch)
    } else {
        @('worktree', 'add', '-b', $lane.Branch, $lane.Worktree, $integration.Branch)
    }

    $result = Invoke-Git -Path $RepoRoot -Arguments $arguments
    foreach ($line in $result.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    if ($result.Code -ne 0) { Write-Host 'FAILED: could not create the worktree.' -ForegroundColor Red; exit 1 }

    Invoke-Warm -Lane $lane
    Write-Host ("SEEDED: {0} on '{1}'" -f $lane.Worktree, $lane.Branch) -ForegroundColor Green
}

function Invoke-Warm {
    <#
        A cold lane pays its whole dependency install or cache rebuild on the first run. Two ways to
        avoid that, and which is right depends on the cost:

          "warm": { "run": "npm ci" }              rebuild it -- correct for anything a package
                                                   manager can restore, and it stays honest
          "warm": { "copy": ["Library"] }          copy it -- only worth it for a cache that costs
                                                   minutes and is safe to copy between checkouts

        Copy from a checkout nothing is currently using. A cache copied out from under a running
        toolchain is a cache with a half-written file in it.
    #>
    param($Lane)
    if (-not $Lane.Warm) { return }

    foreach ($directory in (ConvertTo-Array (Get-Field $Lane.Warm 'copy' @()))) {
        $source = Join-Path $RepoRoot $directory
        $destination = Join-Path $Lane.Worktree $directory
        if (-not (Test-Path -LiteralPath $source)) {
            Write-Host ("  warm: no '{0}' to copy" -f $directory) -ForegroundColor DarkGray
            continue
        }
        Write-Host ("  warm: copying {0} ..." -f $directory) -ForegroundColor DarkGray
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Continue
    }

    $run = Get-Field $Lane.Warm 'run' $null
    if ($run) {
        Write-Host ("  warm: {0}" -f $run) -ForegroundColor DarkGray
        Push-Location -LiteralPath $Lane.Worktree
        try {
            if ((-not (Test-Path variable:IsWindows)) -or $IsWindows) { & cmd /c $run } else { & /bin/sh -c $run }
            if ($LASTEXITCODE -ne 0) { Write-Host ("  warm: '{0}' exited {1}; the lane will pay this on its first run." -f $run, $LASTEXITCODE) -ForegroundColor Yellow }
        } finally { Pop-Location }
    }
}

# ------------------------------------------------------------------------------------------ sync

function Invoke-Sync {
    $lane = Get-Lane $Lane
    if (-not (Test-Path -LiteralPath $lane.Worktree)) {
        Write-Host ("REFUSED: lane '{0}' is not seeded." -f $lane.Name) -ForegroundColor Red
        exit 2
    }

    $dirty = Get-WorktreeDirt -Path $lane.Worktree
    if ($dirty.Code -eq 0 -and $dirty.Lines.Count -gt 0 -and -not $Force) {
        Write-Host ("REFUSED: lane '{0}' has uncommitted changes. A sync writes the integration branch's whole delta over them." -f $lane.Name) -ForegroundColor Red
        foreach ($line in $dirty.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
        exit 2
    }

    # Syncing is not landing. A merge when the lane has unlanded commits, a fast-forward when it has
    # none: a merge with nothing on your side joins nothing, and every later land carries it.
    $behind = Invoke-Git -Path $lane.Worktree -Arguments @('merge-base', '--is-ancestor', $integration.Branch, 'HEAD')
    if ($behind.Code -eq 0) {
        Write-Host ("Up to date: '{0}' already contains '{1}'." -f $lane.Branch, $integration.Branch) -ForegroundColor Green
        exit 0
    }

    $ahead = Invoke-Git -Path $lane.Worktree -Arguments @('merge-base', '--is-ancestor', 'HEAD', $integration.Branch)
    $arguments = if ($ahead.Code -eq 0) {
        @('merge', '--ff-only', $integration.Branch)
    } else {
        @('merge', '--no-ff', '--no-edit', $integration.Branch)
    }

    $result = Invoke-Git -Path $lane.Worktree -Arguments $arguments
    foreach ($line in $result.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    if ($result.Code -ne 0) {
        Write-Host 'CONFLICT: resolve it here, in the lane, then re-run the tiers before landing.' -ForegroundColor Red
        exit 1
    }
    Write-Host ("SYNCED: '{0}' now contains '{1}'. Re-run the tiers -- this is not the tree you tested." -f $lane.Branch, $integration.Branch) -ForegroundColor Green
}

function Invoke-SyncPrimary {
    <#
        The primary checkout is the one working tree nothing else syncs. Lanes land onto the
        integration branch by ref, so the branch the owner has open falls behind by every land, and
        nothing in that tree changes to say so. Everything read there -- an inbox, a unit's state, a
        claim about to be rewritten -- is then from before those lands.

        Same shape as a lane's sync, and for the same reason: fast-forward when there is nothing
        unlanded on this side, a real merge when there is, and never over uncommitted work.
    #>
    $where = Get-WorktreeFor -Path $RepoRoot -Branch $integration.Primary
    if (-not $where) {
        Write-Host ("REFUSED: '{0}' is the primary branch in process.json and no working tree has it checked out." -f $integration.Primary) -ForegroundColor Red
        exit 2
    }

    $dirty = Get-WorktreeDirt -Path $where
    if ($dirty.Code -eq 0 -and $dirty.Lines.Count -gt 0 -and -not $Force) {
        Write-Host ("REFUSED: '{0}' has uncommitted changes. A sync writes the integration branch's whole delta over them." -f $integration.Primary) -ForegroundColor Red
        foreach ($line in $dirty.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
        exit 2
    }

    $behind = Invoke-Git -Path $where -Arguments @('merge-base', '--is-ancestor', $integration.Branch, 'HEAD')
    if ($behind.Code -eq 0) {
        Write-Host ("Up to date: '{0}' already contains '{1}'." -f $integration.Primary, $integration.Branch) -ForegroundColor Green
        exit 0
    }

    $ahead = Invoke-Git -Path $where -Arguments @('merge-base', '--is-ancestor', 'HEAD', $integration.Branch)
    $arguments = if ($ahead.Code -eq 0) {
        @('merge', '--ff-only', $integration.Branch)
    } else {
        @('merge', '--no-ff', '--no-edit', $integration.Branch)
    }

    $result = Invoke-Git -Path $where -Arguments $arguments
    foreach ($line in $result.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    if ($result.Code -ne 0) {
        Write-Host 'CONFLICT: resolve it here, in the primary checkout, before reading or writing anything else.' -ForegroundColor Red
        exit 1
    }
    Write-Host ("SYNCED: '{0}' now contains '{1}'. Re-read before deciding -- the documents just changed under you." -f $integration.Primary, $integration.Branch) -ForegroundColor Green
}

# ---------------------------------------------------------------------------------------- status

function Invoke-Status {
    Write-Host ("integration: {0}  (mode {1})" -f $integration.Branch, $integration.Mode) -ForegroundColor Cyan

    $checkedOut = Get-WorktreeFor -Path $RepoRoot -Branch $integration.Branch
    if ($checkedOut -and $integration.Mode -eq 'objects') {
        Write-Host ("  BROKEN: '{0}' is checked out at {1}. Landing by ref is unsafe while it is." -f $integration.Branch, $checkedOut) -ForegroundColor Red
    }

    # The primary gets a row of its own. It is not a lane, which is exactly why it was missing here --
    # and it is the tree whose staleness is invisible, because no land touches it and nothing in it
    # changes when the ref it does not hold moves.
    $primaryAt = Get-WorktreeFor -Path $RepoRoot -Branch $integration.Primary
    if (-not $primaryAt) {
        Write-Host ("  {0,-12} {1,-10} not checked out anywhere" -f 'primary', $integration.Primary) -ForegroundColor DarkGray
    } else {
        $notes = New-Object System.Collections.Generic.List[string]
        $dirty = Get-WorktreeDirt -Path $primaryAt
        if ($dirty.Lines.Count -gt 0) { $notes.Add("$($dirty.Lines.Count) uncommitted") | Out-Null }
        $counts = Get-GitValue -Path $primaryAt -Arguments @('rev-list', '--left-right', '--count', "$($integration.Branch)...HEAD")
        $stale = $false
        if ($counts) {
            $parts = $counts -split '\s+'
            if ($parts.Count -ge 2) {
                if ([int]$parts[0] -gt 0) { $notes.Add("$($parts[0]) behind -- STALE, sync before reading") | Out-Null; $stale = $true }
                if ([int]$parts[1] -gt 0) { $notes.Add("$($parts[1]) to land") | Out-Null }
            }
        }
        $colour = if ($stale) { 'Red' } elseif ($notes.Count -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-12} {1,-10} {2}" -f 'primary', $integration.Primary, ($notes -join ', ')) -ForegroundColor $colour
    }

    if ($names.Count -eq 0) { Write-Host '  no lanes declared in process.json' -ForegroundColor DarkGray; return }

    foreach ($name in $names) {
        $lane = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $name
        if (-not (Test-Path -LiteralPath $lane.Worktree)) {
            Write-Host ("  {0,-12} not seeded" -f $name) -ForegroundColor DarkGray
            continue
        }

        $branch = Get-GitValue -Path $lane.Worktree -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        $dirty = Get-WorktreeDirt -Path $lane.Worktree
        $counts = Get-GitValue -Path $lane.Worktree -Arguments @('rev-list', '--left-right', '--count', "$($integration.Branch)...HEAD")

        $notes = New-Object System.Collections.Generic.List[string]
        if ($branch -ne $lane.Branch) { $notes.Add("on '$branch', expected '$($lane.Branch)'") | Out-Null }
        if ($dirty.Lines.Count -gt 0) { $notes.Add("$($dirty.Lines.Count) uncommitted") | Out-Null }
        if ($counts) {
            $parts = $counts -split '\s+'
            if ($parts.Count -ge 2) {
                if ([int]$parts[0] -gt 0) { $notes.Add("$($parts[0]) behind") | Out-Null }
                if ([int]$parts[1] -gt 0) { $notes.Add("$($parts[1]) to land") | Out-Null }
            }
        }
        $lockPath = Get-LockPath $lane.Worktree
        if (Test-Path -LiteralPath $lockPath) { $notes.Add('LOCKED') | Out-Null }

        $colour = if ($branch -ne $lane.Branch) { 'Red' } elseif ($notes.Count -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-12} {1,-10} {2}" -f $name, $branch, ($notes -join ', ')) -ForegroundColor $colour
    }
}

# ---------------------------------------------------------------------------------------- remove

function Invoke-Remove {
    $lane = Get-Lane $Lane
    $arguments = @('worktree', 'remove', $lane.Worktree)
    if ($Force) { $arguments += '--force' }
    $result = Invoke-Git -Path $RepoRoot -Arguments $arguments
    foreach ($line in $result.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    if ($result.Code -ne 0) { Write-Host 'FAILED: -Force removes one with uncommitted changes.' -ForegroundColor Red; exit 1 }
    Write-Host ("REMOVED: {0}. The branch '{1}' is untouched." -f $lane.Worktree, $lane.Branch) -ForegroundColor Green
}

switch ($Verb) {
    'seed'   { Invoke-Seed }
    'sync'   {
        if ($Primary -and $Lane) {
            Write-Host "REFUSED: -Primary syncs the primary checkout; naming a lane as well says two different things." -ForegroundColor Red
            exit 2
        }
        if ($Primary) { Invoke-SyncPrimary } else { Invoke-Sync }
    }
    'status' { Invoke-Status }
    'remove' { Invoke-Remove }
}
exit 0
