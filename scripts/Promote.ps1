#Requires -Version 5.1
<#
.SYNOPSIS
    Pushes the task branch's commit for review, once every tier has passed on exactly that commit.

.DESCRIPTION
    The land of a personal overlay. On a repository somebody else owns, nothing reach advances is
    shared: the reviewers merge, and what reaches them is a branch. So the land becomes "every tier
    passed on this exact commit, so move the branch they read to it" -- and this is the whole of it.

    A task branch is `<prefix><name>`, where the prefix is integration.prefix and `<name>` is the
    branch the team's tracker made for the issue. It promotes to `<name>` on integration.remote.

    In order, and each refusal changes nothing:

      1. integration.mode is promote, and this is a task branch.
      2. The working tree is clean. The tiers read the tree, so with anything uncommitted they would
         pass on a tree that is not the commit being pushed.
      3. Every tier runs, whole. A failure refuses, and so does a skip: a skip is a tier that did not
         run, and pushing over it puts work in front of reviewers that a tier was meant to see first.
      4. HEAD and the tree are still what was verified.
      5. The commit is recorded in the git directory as promoted to `<name>`, which is what the
         pre-push hook reads to let it through.
      6. It is pushed, never forced. A refusal means the branch moved on the remote -- a reviewer's
         fixup, a rebase in the tracker -- and the answer is to bring that in and promote again.

    The merge request is opened by hand, from `<name>`.

    Exit 0 promoted. 1 a tier did not pass, or the push was refused. 2 refused to start.

.PARAMETER Root
    The process root. Defaults to the one Resolve-RepoRoot finds.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }

$integration = Get-Integration $Process
if ($integration.Mode -ne 'promote') {
    Write-Host ("REFUSED: integration.mode is '{0}'. Promotion is how an overlay reaches its reviewers; this repository lands." -f $integration.Mode) -ForegroundColor Red
    exit 2
}
if (-not $integration.Prefix) {
    Write-Host 'REFUSED: integration.prefix is not set, so no branch here can be told from the one it promotes to.' -ForegroundColor Red
    exit 2
}

# ------------------------------------------------------------------------------------ the branch

$branch = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
if (-not $branch -or $branch -eq 'HEAD') {
    Write-Host 'REFUSED: HEAD is detached. Promote from a task branch.' -ForegroundColor Red
    exit 2
}
if (-not $branch.StartsWith($integration.Prefix) -or $branch.Length -le $integration.Prefix.Length) {
    Write-Host ("REFUSED: '{0}' is not a task branch. Promotion runs from '{1}<name>' and pushes to '<name>'." -f $branch, $integration.Prefix) -ForegroundColor Red
    exit 2
}
$target = $branch.Substring($integration.Prefix.Length)

$remotes = Invoke-Git -Path $RepoRoot -Arguments @('remote')
if ($remotes.Code -ne 0 -or @($remotes.Lines | ForEach-Object { $_.Trim() }) -notcontains $integration.Remote) {
    Write-Host ("REFUSED: no remote '{0}' here, so there is nowhere to promote to." -f $integration.Remote) -ForegroundColor Red
    exit 2
}

# ------------------------------------------------------------------------------------ the tree

function Get-Dirt {
    $status = Invoke-Git -Path $RepoRoot -Arguments @('status', '--porcelain')
    return @($status.Lines | Where-Object { $_ })
}

$dirt = @(Get-Dirt)
if ($dirt.Count -gt 0) {
    Write-Host ("REFUSED: the working tree has {0} uncommitted change(s). The tiers read the tree, so they would pass on something other than the commit being pushed. Commit or stash, then promote." -f $dirt.Count) -ForegroundColor Red
    foreach ($line in ($dirt | Select-Object -First 10)) { Write-Host "  $line" -ForegroundColor DarkGray }
    exit 2
}

$sha = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', 'HEAD')
Write-Host ("Promote -- {0} at {1}, to {2}/{3}" -f $branch, $sha.Substring(0, 12), $integration.Remote, $target) -ForegroundColor Cyan

# ----------------------------------------------------------------------------------- the tiers

& (Join-Path $PSScriptRoot 'Verify-All.ps1') -Root $RepoRoot -Whole
$code = $LASTEXITCODE
if ($code -ne 0) {
    $why = switch ($code) { 3 { 'a tier was skipped, so it never saw this commit' } 2 { 'verification refused to start' } default { 'a tier failed' } }
    Write-Host ("NOT PROMOTED: {0}. Nothing was recorded and nothing was pushed." -f $why) -ForegroundColor Red
    exit 1
}

$now = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', 'HEAD')
if ($now -ne $sha -or @(Get-Dirt).Count -gt 0) {
    Write-Host 'REFUSED: HEAD or the working tree changed while the tiers ran, so what passed is not what would be pushed. Promote again.' -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------------------- the record

# In the git directory, beside the hooks that read it, so it is this clone's and never the tree's.
# One line per promotion; the hook matches whole lines, so LF and nothing else.
$common = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--path-format=absolute', '--git-common-dir')
$record = Join-Path $common 'reach-promoted'
[System.IO.File]::AppendAllText($record, ("{0} {1}`n" -f $sha, $target), (New-Object System.Text.UTF8Encoding($false)))

# -------------------------------------------------------------------------------------- the push

$push = Invoke-Git -Path $RepoRoot -Arguments @('push', $integration.Remote, ("{0}:refs/heads/{1}" -f $sha, $target))
foreach ($line in $push.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
if ($push.Code -ne 0) {
    Write-Host ("FAILED: '{0}' on '{1}' has moved, or refused this. Fetch it, bring it into '{2}', and promote again. Never force: what is there may be a reviewer's." -f $target, $integration.Remote, $branch) -ForegroundColor Red
    exit 1
}

Write-Host ("PROMOTED: {0} -> {1}/{2}. Open the merge request from '{2}'." -f $sha.Substring(0, 12), $integration.Remote, $target) -ForegroundColor Green
exit 0
