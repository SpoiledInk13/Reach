#Requires -Version 5.1
<#
.SYNOPSIS
    How an integrator and its builders share the work: who holds which unit, which tips are ready,
    which were sent back.

.DESCRIPTION
    A lane that declares `builders` in process.json runs as one INTEGRATOR -- the only lane holding
    the scarce verifier (an editor, an emulator, a device, a warm database), and the only one that
    lands -- and any number of BUILDERS, `<lane>-1`, `<lane>-2`, ..., which prove every tier that
    needs no such harness. The split exists because most proofs need none: one project found nine in
    ten of its proofs ran without the harness, while its one lane spent half its wall clock waiting
    on serial sweeps in it.

    Three facts pass between them, and this script is the only thing that writes any of them:

      a claim      one lane per unit. A lane takes a unit before writing in it, so two lanes never
                   edit one document or one unit's code at once. Taking is atomic: the second lane
                   to ask is refused and told who holds it.
      ready        refs/ready/<builder> points at the tip a builder has proven and wants landed. The
                   integrator merges what is ready; a half-done unit is simply not marked.
      a rejection  the integrator sending a ready tip back, with why -- a red sweep, a conflict. It
                   is keyed by the tip, so marking a new tip ready supersedes it.

    Claims and rejections live under the shared git directory, so every worktree sees the same ones
    and none is ever committed: they are coordination, not history.

    Run it from inside a lane: the lane is read off the checkout's branch, and `ready` marks THAT
    checkout's HEAD -- run from the primary checkout it would mark the primary's. -Lane names one
    explicitly where a verb needs no HEAD.

      Builders.ps1 take <unit>           hold a unit for this lane
      Builders.ps1 drop <unit>           let it go -- only the holder may
      Builders.ps1 held                  every unit held, and by whom
      Builders.ps1 ready                 mark this builder's committed HEAD ready
      Builders.ps1 pending               the ready tips the integrator has to merge
      Builders.ps1 reject <builder> -Reason <why>   send a ready tip back
      Builders.ps1 rejection             whether this builder's ready tip was sent back
      Builders.ps1 state                 none, pending or rejected, for this builder's tip

    Exit codes: 0 done, or nothing to report; 1 refused, or a rejection stands; 2 could not run.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet('take', 'drop', 'held', 'ready', 'pending', 'reject', 'rejection', 'state')][string]$Verb,
    [Parameter(Position = 1)][string]$Target,
    [string]$Lane,
    [string]$Reason,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'COULD NOT RUN: not a git repository.' -ForegroundColor Red; exit 2 }
$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'COULD NOT RUN: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }
$integration = Get-Integration $Process
try { $State = Get-BuilderStateDir -RepoRoot $RepoRoot }
catch { Write-Host "COULD NOT RUN: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

function Get-ThisLane {
    # The lane this verb acts for: -Lane, or the checkout's own branch. Refuses anything that is not
    # an integrator declaring builders or one of its builders.
    $config = $null
    if ($Lane) {
        $config = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $Lane
    } else {
        $branch = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        $config = Get-LaneOfBranch -Process $Process -RepoRoot $RepoRoot -Branch $branch
    }
    if (-not $config -or (-not $config.HasBuilders -and $config.Builder -le 0)) {
        Write-Host 'REFUSED: this is not a lane that shares its work -- run it inside an integrator that declares builders, or one of its builders, or pass -Lane.' -ForegroundColor Red
        exit 1
    }
    return $config
}

switch ($Verb) {
    'take' {
        $me = Get-ThisLane
        if (-not $Target) { Write-Host 'REFUSED: name the unit to take.' -ForegroundColor Red; exit 1 }
        $unitDir = Get-Field (Get-Field $Process 'unit' $null) 'dir' 'Docs/units'
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $RepoRoot $unitDir) "$Target.md"))) {
            Write-Host ("REFUSED: no unit document {0}/{1}.md" -f $unitDir, $Target) -ForegroundColor Red; exit 1
        }
        $path = Join-Path $State "claims/$Target"
        try {
            # CreateNew is the atomic part: of two lanes asking at once, exactly one creates the file.
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
            $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes("$($me.Name)`n$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`n")
            $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
            Write-Host ("TAKEN: {0} for {1}" -f $Target, $me.Name) -ForegroundColor Green; exit 0
        } catch [System.IO.IOException] {
            $record = Read-BuilderRecord $path
            if ($record.First -eq $me.Name) { Write-Host ("HELD: {0} is already {1}'s" -f $Target, $me.Name) -ForegroundColor Green; exit 0 }
            Write-Host ("REFUSED: {0} is held by {1} since {2}. Take another unit." -f $Target, $record.First, $record.Rest) -ForegroundColor Red; exit 1
        }
    }
    'drop' {
        $me = Get-ThisLane
        if (-not $Target) { Write-Host 'REFUSED: name the unit to drop.' -ForegroundColor Red; exit 1 }
        $path = Join-Path $State "claims/$Target"
        if (-not (Test-Path -LiteralPath $path)) { Write-Host ("FREE: {0} was not held" -f $Target) -ForegroundColor Green; exit 0 }
        $record = Read-BuilderRecord $path
        if ($record.First -ne $me.Name) {
            Write-Host ("REFUSED: {0} is {1}'s, not {2}'s" -f $Target, $record.First, $me.Name) -ForegroundColor Red; exit 1
        }
        Remove-Item -LiteralPath $path -Force
        Write-Host ("DROPPED: {0}" -f $Target) -ForegroundColor Green; exit 0
    }
    'held' {
        $claims = @(Get-ChildItem -LiteralPath (Join-Path $State 'claims') -File | Sort-Object Name)
        if ($claims.Count -eq 0) { Write-Host 'no unit is held'; exit 0 }
        foreach ($claim in $claims) {
            $record = Read-BuilderRecord $claim.FullName
            Write-Host ("{0,-24} {1,-12} since {2}" -f $claim.Name, $record.First, $record.Rest)
        }
        exit 0
    }
    'ready' {
        $me = Get-ThisLane
        if ($me.Builder -le 0) {
            Write-Host 'REFUSED: the integrator lands its own work; only a builder marks a tip ready.' -ForegroundColor Red; exit 1
        }
        # Tracked changes only: an untracked file changes nothing about what HEAD is.
        $dirt = Invoke-Git -Path $RepoRoot -Arguments @('status', '--porcelain', '--untracked-files=no')
        if ($dirt.Code -ne 0 -or $dirt.Lines.Count -gt 0) {
            Write-Host 'REFUSED: the tree has uncommitted changes, so HEAD is not what was proven -- commit first.' -ForegroundColor Red; exit 1
        }
        $head = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', 'HEAD')
        $branch = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($branch -ne $me.Branch) {
            Write-Host ("REFUSED: this checkout is on '{0}', not {1}'s branch '{2}' -- run it inside the builder, where HEAD is what it proved." -f $branch, $me.Name, $me.Branch) -ForegroundColor Red; exit 1
        }
        $update = Invoke-Git -Path $RepoRoot -Arguments @('update-ref', "refs/ready/$($me.Name)", $head)
        if ($update.Code -ne 0) { Write-Host "COULD NOT RUN: update-ref refs/ready/$($me.Name) failed" -ForegroundColor Red; exit 2 }
        # A rejection is keyed by the tip it names, so this new tip supersedes one without touching it.
        Write-Host ("READY: refs/ready/{0} -> {1}" -f $me.Name, $head.Substring(0, 10)) -ForegroundColor Green; exit 0
    }
    'pending' {
        $tips = @(Get-PendingTips -RepoRoot $RepoRoot -StateDir $State -IntegrationBranch $integration.Branch)
        if ($tips.Count -eq 0) { Write-Host 'nothing is ready'; exit 0 }
        foreach ($tip in $tips) { Write-Host ("{0}  {1}  {2}" -f $tip.Lane, $tip.Sha.Substring(0, 10), $tip.Subject) }
        exit 0
    }
    'reject' {
        if (-not $Target) { Write-Host 'REFUSED: name the builder whose tip goes back.' -ForegroundColor Red; exit 1 }
        $builder = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $Target
        if (-not $builder -or $builder.Builder -le 0) { Write-Host ("REFUSED: '{0}' is not a builder lane" -f $Target) -ForegroundColor Red; exit 1 }
        if (-not $Reason) { Write-Host 'REFUSED: a rejection says why (-Reason) -- the builder fixes what it is told.' -ForegroundColor Red; exit 1 }
        $sha = Get-ReadyTip -RepoRoot $RepoRoot -Name $Target
        if (-not $sha) { Write-Host ("REFUSED: {0} has no ready tip to send back" -f $Target) -ForegroundColor Red; exit 1 }
        [System.IO.File]::WriteAllText((Join-Path $State "rejected/$Target"), "$sha`n$Reason`n", (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("SENT BACK: {0} at {1}: {2}" -f $Target, $sha.Substring(0, 10), $Reason) -ForegroundColor Yellow; exit 0
    }
    'rejection' {
        $me = Get-ThisLane
        $record = Get-RejectionOf -RepoRoot $RepoRoot -StateDir $State -Name $me.Name
        if ($null -eq $record) { Write-Host 'no rejection stands'; exit 0 }
        Write-Host ("SENT BACK at {0}: {1}" -f $record.First.Substring(0, 10), $record.Rest) -ForegroundColor Red
        exit 1
    }
    'state' {
        $me = Get-ThisLane
        Write-Output (Get-TipState -RepoRoot $RepoRoot -StateDir $State -IntegrationBranch $integration.Branch -Name $me.Name)
        exit 0
    }
}
exit 2
