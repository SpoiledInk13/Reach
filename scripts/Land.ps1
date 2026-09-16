#Requires -Version 5.1
<#
.SYNOPSIS
    Lands a lane's branch onto the integration branch, as a merge commit, safely against other lanes.

.DESCRIPTION
    A land is always a merge commit, never a fast-forward. Each land is then one entry on the
    integration branch's first-parent history, so the log reads as the list of lands and
    `git revert -m 1 <merge>` undoes one as a unit.

    The integration branch is checked out nowhere, so the merge is built from objects rather than in
    a working tree. That is what lets a land happen while every lane is busy, and it is why two lanes
    can land minutes apart without either waiting.

    The compare-and-swap is the whole safety property. The integration SHA is read ONCE, the merge is
    built against that SHA, and the ref is swapped only if it is still that SHA. Read it twice -- once
    to merge and once to swap -- and the swap can succeed against a commit you never merged, silently
    discarding whatever landed in between. That has happened, and the other agent's publish pushed the
    result to the remote a second later.

    In `push` mode nothing is merged locally: the lane branch is pushed and a human or CI merges it.
    That is the mode for a repository you do not own.

    In `objects` mode the land then publishes -- the integration branch, the primary's and every
    lane's, in one atomic push. Merging from objects touches nothing outside this disk, so without
    that step the integration branch advances here and nowhere else, which from here is
    indistinguishable from published work. A refused push fails the land without undoing the merge:
    what is owed is the push, and `Publish.ps1` is what pays it.

.PARAMETER Lane
    The lane to land. Its branch is the tip, and it is fast-forwarded to the result afterwards.

.PARAMETER Branch
    Land a branch that is not a lane -- the primary checkout's own branch, which is how the ideate
    command publishes a decision. Exactly one of -Lane or -Branch.

.PARAMETER Message
    Path to a file holding the merge commit message. A message goes through a file because a
    here-string breaks on quotes and turns words into pathspecs.

.PARAMETER Verified
    The tree you actually ran the tiers against, as a SHA. If the merge produces a different tree,
    the land is refused: what you verified is not what would land.

.PARAMETER Root
    The repository. Defaults to the git root of the current directory.
#>
[CmdletBinding()]
param(
    [string]$Lane,
    [string]$Branch,
    [string]$Message,
    [string]$Verified,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }

$integration = Get-Integration $Process

if (($Lane -and $Branch) -or (-not $Lane -and -not $Branch)) {
    Write-Host 'REFUSED: name exactly one of -Lane or -Branch.' -ForegroundColor Red
    exit 2
}

$laneConfig = $null
if ($Lane) {
    $laneConfig = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $Lane
    if (-not $laneConfig) {
        Write-Host ("REFUSED: no lane named '{0}' in process.json. Known: {1}" -f $Lane, ((Get-LaneNames $Process) -join ', ')) -ForegroundColor Red
        exit 2
    }
    $tipRef = $laneConfig.Branch
} else {
    $tipRef = $Branch
}

# Landing the integration branch into itself is not a merge, it is a loop. Worth naming, because
# `-Branch develop` is an easy thing to type while thinking about publishing.
if ($tipRef -eq $integration.Branch) {
    Write-Host ("REFUSED: '{0}' is the integration branch. There is nothing to land it onto." -f $tipRef) -ForegroundColor Red
    exit 2
}

# --------------------------------------------------------------------------------------- push mode

if ($integration.Mode -eq 'push') {
    $result = Invoke-Git -Path $RepoRoot -Arguments @('push', $integration.Remote, ("{0}:{0}" -f $tipRef))
    foreach ($line in $result.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    if ($result.Code -ne 0) {
        Write-Host "FAILED: could not push '$tipRef'. A rejection means the remote moved: fetch, reconcile, re-verify, and push again. Never force." -ForegroundColor Red
        exit 1
    }
    Write-Host ("PUSHED: {0} -> {1}/{0}. Landing is the reviewer's; this lane does not merge." -f $tipRef, $integration.Remote) -ForegroundColor Green
    exit 0
}

# ------------------------------------------------------------------------------------ the guards

if ($integration.Mode -ne 'objects') {
    Write-Host ("REFUSED: integration.mode '{0}' is not one this understands ('objects' or 'push')." -f $integration.Mode) -ForegroundColor Red
    exit 2
}

# Advancing a ref that some worktree has checked out leaves that worktree's index describing a commit
# that is no longer its HEAD, and the next status there reports every file as deleted. The whole model
# depends on the integration branch belonging to no working tree.
$checkedOut = Get-WorktreeFor -Path $RepoRoot -Branch $integration.Branch
if ($checkedOut) {
    Write-Host ("REFUSED: '{0}' is checked out at {1}. The integration branch must belong to no working tree -- that is what lets a land happen while every lane is busy. Move that checkout to its own branch." -f $integration.Branch, $checkedOut) -ForegroundColor Red
    exit 2
}

$old = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--verify', "refs/heads/$($integration.Branch)")
if (-not $old) { Write-Host ("REFUSED: no branch '{0}'." -f $integration.Branch) -ForegroundColor Red; exit 2 }

$tip = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--verify', "refs/heads/$tipRef")
if (-not $tip) { Write-Host ("REFUSED: no branch '{0}'." -f $tipRef) -ForegroundColor Red; exit 2 }

$already = Invoke-Git -Path $RepoRoot -Arguments @('merge-base', '--is-ancestor', $tip, $old)
if ($already.Code -eq 0) {
    Write-Host ("NOTHING TO LAND: '{0}' is already contained in '{1}'." -f $tipRef, $integration.Branch) -ForegroundColor Yellow
    # It still publishes. The ordinary way to arrive here is a land whose merge succeeded and whose
    # push did not, followed by someone landing again -- and exiting green without retrying would
    # confirm precisely the state that went wrong.
    if ($integration.Publish) { exit (Invoke-ReachPublish -RepoRoot $RepoRoot -Process $Process) }
    exit 0
}

if (-not $Message -or -not (Test-Path -LiteralPath $Message)) {
    Write-Host 'REFUSED: -Message must be a file holding the merge message.' -ForegroundColor Red
    exit 2
}

# ------------------------------------------------------------------------------------- the merge

$merge = Invoke-Git -Path $RepoRoot -Arguments @('merge-tree', '--write-tree', $old, $tip)
if ($merge.Code -ne 0) {
    Write-Host ("CONFLICT: '{0}' and '{1}' do not merge cleanly." -f $tipRef, $integration.Branch) -ForegroundColor Red
    foreach ($line in $merge.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    Write-Host 'Resolve it in a temporary worktree at the integration SHA, then land that result. Never resolve it in a lane or in the primary checkout.' -ForegroundColor Red
    exit 1
}
$tree = $merge.Lines[0].Trim()

$tipTree = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', "$tip^{tree}")
$arrived = ($tree -ne $tipTree)

if ($Verified) {
    $verifiedTree = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', "$Verified^{tree}")
    if ($verifiedTree -and $verifiedTree -ne $tree) {
        Write-Host 'REFUSED: the merge produces a tree you did not verify.' -ForegroundColor Red
        Write-Host ("  verified {0}`n  would land {1}" -f $verifiedTree, $tree) -ForegroundColor DarkGray
        Write-Host 'Something arrived on the integration branch since you ran the tiers. Sync it into the lane, re-run them, and land again.' -ForegroundColor Red
        exit 1
    }
}
elseif ($arrived) {
    Write-Host 'WARNING: the merge brings in changes from the integration branch, so this tree is not the one the lane tested.' -ForegroundColor Yellow
    Write-Host '  Sync the integration branch into the lane, re-run the tiers there, and land again -- or pass -Verified <sha> to say which tree you proved.' -ForegroundColor Yellow
}

$new = Get-GitValue -Path $RepoRoot -Arguments @('commit-tree', $tree, '-p', $old, '-p', $tip, '-F', (Resolve-Path -LiteralPath $Message).Path)
if (-not $new) { Write-Host 'FAILED: could not write the merge commit.' -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------- compare-and-swap

# $old is the SHA that was merged, never a fresh read. This is the entire safety property.
$swap = Invoke-Git -Path $RepoRoot -Arguments @('update-ref', "refs/heads/$($integration.Branch)", $new, $old)
if ($swap.Code -ne 0) {
    Write-Host ("REFUSED: '{0}' moved while this land was being built." -f $integration.Branch) -ForegroundColor Red
    Write-Host '  Another lane landed. Sync it into this lane, re-run the tiers, and land again. Nothing has been changed.' -ForegroundColor Red
    exit 1
}

Write-Host ("LANDED: {0} -> {1}  ({2})" -f $tipRef, $integration.Branch, $new.Substring(0, 12)) -ForegroundColor Green
if ($arrived) { Write-Host '  (this land merged in work from the integration branch)' -ForegroundColor DarkGray }

# Whatever was landed fast-forwards to the result, so its next piece of work starts from the merged
# history rather than re-merging what it already landed. For a lane that is the lane's worktree; for
# a plain branch it is wherever that branch is checked out, which is normally the primary.
$where = if ($laneConfig) { $laneConfig.Worktree } else { Get-WorktreeFor -Path $RepoRoot -Branch $tipRef }
if ($where) {
    $ff = Invoke-Git -Path $where -Arguments @('merge', '--ff-only', $integration.Branch)
    if ($ff.Code -ne 0) {
        Write-Host ("  note: could not fast-forward '{0}' to {1}; sync it before the next piece of work." -f $tipRef, $integration.Branch) -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------------- publish

# A land that merged and then reached no remote is not a land that finished: the branch everyone else
# reads does not carry it, so the next agent parks on the question this one answered and the one after
# re-derives it. The merge has already happened by here and is not undone -- the non-zero code says
# the publish is owed, and `publish` is how it is paid.
if ($integration.Publish) {
    $published = Invoke-ReachPublish -RepoRoot $RepoRoot -Process $Process
    if ($published -ne 0) { exit $published }
}
exit 0
