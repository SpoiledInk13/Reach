#Requires -Version 5.1
<#
.SYNOPSIS
    Proves the lane and landing guards refuse what they claim to refuse.

.DESCRIPTION
    Landing is the most dangerous thing in this plugin: it advances a shared ref from objects, while
    other work may be arriving. Every guard around it is therefore broken on purpose here and watched
    to refuse, and each control also checks the refusal came from the guard it names -- a script that
    exits non-zero for the wrong reason is a script whose guard is untested.

    Each control builds its own throwaway repository. Nothing here touches your work.

.PARAMETER Keep
    Leave the fixtures on disk.
#>
[CmdletBinding()]
param([switch]$Keep)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$Lane = Join-Path $PSScriptRoot 'Lane.ps1'
$Land = Join-Path $PSScriptRoot 'Land.ps1'
$Run  = Join-Path $PSScriptRoot 'Run-Lane.ps1'
$Made = New-Object System.Collections.Generic.List[string]

function New-Fixture {
    param([string]$Mode = 'objects', [string]$LaneDir = 'build')
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("reach-lane-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $Made.Add($root) | Out-Null

    Invoke-Git -Path $repo -Arguments @('init', '-q', '-b', 'working') | Out-Null
    Invoke-Git -Path $repo -Arguments @('config', 'user.email', 'f@example.invalid') | Out-Null
    Invoke-Git -Path $repo -Arguments @('config', 'user.name', 'Fixture') | Out-Null

    $config = @{
        project     = 'fixture'
        integration = @{ branch = 'develop'; primary = 'working'; mode = $Mode; remote = 'origin' }
        lanes       = @(@{ name = 'build'; branch = 'build'; worktree = "../lanes/$LaneDir"; command = '/reach:build' })
    } | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText((Join-Path $repo 'process.json'), $config, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "one`n", (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'base') | Out-Null
    Invoke-Git -Path $repo -Arguments @('branch', 'develop') | Out-Null
    return $repo
}

function Invoke-Script {
    param([string]$Script, [string[]]$Arguments)
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

function New-Message {
    param([string]$Repo, [string]$Text = 'land')
    $path = Join-Path (Split-Path -Parent $Repo) 'msg.txt'
    [System.IO.File]::WriteAllText($path, "$Text`n", (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

$results = New-Object System.Collections.Generic.List[object]

function Test-Control {
    param([string]$Name, [scriptblock]$Body)
    try {
        $verdict = & $Body
        if ($verdict -eq $true) {
            Write-Host ("  proven      {0}" -f $Name) -ForegroundColor Green
            $results.Add([pscustomobject]@{ Name = $Name; Ok = $true }) | Out-Null
        } else {
            Write-Host ("  DID NOT     {0}   ({1})" -f $Name, $verdict) -ForegroundColor Red
            $results.Add([pscustomobject]@{ Name = $Name; Ok = $false }) | Out-Null
        }
    } catch {
        Write-Host ("  ERRORED     {0}   ({1})" -f $Name, $_.Exception.Message) -ForegroundColor Red
        $results.Add([pscustomobject]@{ Name = $Name; Ok = $false }) | Out-Null
    }
}

Write-Host 'Prove-Lanes' -ForegroundColor Cyan

# ------------------------------------------------------------------------------------ the lane

Test-Control 'seed creates the worktree and its branch' {
    $repo = New-Fixture
    $seed = Invoke-Script $Lane @('seed', 'build', '-Root', $repo)
    if ($seed.Code -ne 0) { return "seed exited $($seed.Code)" }
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    if (-not (Test-Path -LiteralPath $worktree)) { return 'no worktree' }
    if ((Get-GitValue -Path $worktree -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')) -ne 'build') { return 'wrong branch' }
    return $true
}

Test-Control 'seed refuses a lane directory long enough to break MAX_PATH' {
    $repo = New-Fixture -LaneDir 'a-really-long-lane-directory-name'
    $seed = Invoke-Script $Lane @('seed', 'build', '-Root', $repo)
    if ($seed.Code -eq 0) { return 'it was allowed' }
    if ($seed.Output -notmatch 'characters') { return 'refused for another reason' }
    return $true
}

Test-Control 'sync refuses a lane with uncommitted work' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'dirty.txt'), 'x')
    # develop must have moved, or sync short-circuits as up to date before reaching the guard.
    Invoke-Git -Path $repo -Arguments @('checkout', '-q', 'develop') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'b.txt'), 'b')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'on develop') | Out-Null
    Invoke-Git -Path $repo -Arguments @('checkout', '-q', 'working') | Out-Null

    $sync = Invoke-Script $Lane @('sync', 'build', '-Root', $repo)
    if ($sync.Code -eq 0) { return 'it was allowed' }
    if ($sync.Output -notmatch 'uncommitted') { return 'refused for another reason' }
    return $true
}

Test-Control 'the lock refuses a second holder and releases on exit' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    $first = Enter-LaneLock -LaneWorktree $worktree -Owner 'first'
    if (-not $first.Ok) { return 'the first holder could not take it' }
    $second = Enter-LaneLock -LaneWorktree $worktree -Owner 'second'
    if ($second.Ok) { return 'a second holder took it' }
    Exit-LaneLock -LaneWorktree $worktree
    $third = Enter-LaneLock -LaneWorktree $worktree -Owner 'third'
    if (-not $third.Ok) { return 'it stayed locked after release' }
    Exit-LaneLock -LaneWorktree $worktree
    return $true
}

# --------------------------------------------------------------------------------- the landing

Test-Control 'land refuses while the integration branch is checked out' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'b.txt'), 'b')
    Invoke-Git -Path $worktree -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('commit', '-qm', 'lane work') | Out-Null

    # The thing that makes the object-merge unsafe: somebody has develop checked out.
    Invoke-Git -Path $repo -Arguments @('checkout', '-q', 'develop') | Out-Null

    $land = Invoke-Script $Land @('-Lane', 'build', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -eq 0) { return 'it landed anyway' }
    if ($land.Output -notmatch 'checked out') { return 'refused for another reason' }
    return $true
}

Test-Control 'a clean land is a merge commit on first-parent history' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'b.txt'), 'b')
    Invoke-Git -Path $worktree -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('commit', '-qm', 'lane work') | Out-Null

    $land = Invoke-Script $Land @('-Lane', 'build', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -ne 0) { return "land exited $($land.Code): $($land.Output)" }

    $head = Get-GitValue -Path $repo -Arguments @('rev-parse', 'develop')
    $parents = Get-GitValue -Path $repo -Arguments @('rev-list', '--parents', '-n', '1', $head)
    if (($parents -split ' ').Count -ne 3) { return 'not a merge commit' }
    return $true
}

Test-Control 'land refuses a tree the lane did not verify' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'b.txt'), 'b')
    Invoke-Git -Path $worktree -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('commit', '-qm', 'lane work') | Out-Null
    $verified = Get-GitValue -Path $worktree -Arguments @('rev-parse', 'HEAD')

    # Something else lands on develop after the lane ran its tiers. The merge now produces a tree
    # nobody has tested, which is exactly the case a green run must not be allowed to claim.
    Invoke-Git -Path $repo -Arguments @('worktree', 'add', '-q', (Join-Path (Split-Path -Parent $repo) 'other'), 'develop') | Out-Null
    $other = Join-Path (Split-Path -Parent $repo) 'other'
    [System.IO.File]::WriteAllText((Join-Path $other 'c.txt'), 'c')
    Invoke-Git -Path $other -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $other -Arguments @('commit', '-qm', 'someone else') | Out-Null
    Invoke-Git -Path $other -Arguments @('checkout', '-q', '--detach') | Out-Null

    $land = Invoke-Script $Land @('-Lane', 'build', '-Message', (New-Message $repo), '-Verified', $verified, '-Root', $repo)
    if ($land.Code -eq 0) { return 'it landed a tree nobody tested' }
    if ($land.Output -notmatch 'did not verify') { return 'refused for another reason' }
    return $true
}

Test-Control 'landing twice reports nothing to land rather than an empty merge' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'b.txt'), 'b')
    Invoke-Git -Path $worktree -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('commit', '-qm', 'lane work') | Out-Null

    Invoke-Script $Land @('-Lane', 'build', '-Message', (New-Message $repo), '-Root', $repo) | Out-Null
    $again = Invoke-Script $Land @('-Lane', 'build', '-Message', (New-Message $repo), '-Root', $repo)
    if ($again.Code -ne 0) { return "second land exited $($again.Code)" }
    if ($again.Output -notmatch 'NOTHING TO LAND') { return 'it did something' }
    return $true
}

Test-Control 'push mode pushes the lane branch and merges nothing locally' {
    $repo = New-Fixture -Mode 'push'
    $bare = Join-Path (Split-Path -Parent $repo) 'remote.git'
    Invoke-Git -Path (Split-Path -Parent $repo) -Arguments @('init', '-q', '--bare', $bare) | Out-Null
    Invoke-Git -Path $repo -Arguments @('remote', 'add', 'origin', $bare) | Out-Null
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'b.txt'), 'b')
    Invoke-Git -Path $worktree -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('commit', '-qm', 'lane work') | Out-Null

    $before = Get-GitValue -Path $repo -Arguments @('rev-parse', 'develop')
    $land = Invoke-Script $Land @('-Lane', 'build', '-Root', $repo)
    if ($land.Code -ne 0) { return "push exited $($land.Code): $($land.Output)" }
    if ((Get-GitValue -Path $repo -Arguments @('rev-parse', 'develop')) -ne $before) { return 'it merged locally in push mode' }
    if (-not (Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/build'))) { return 'nothing reached the remote' }
    return $true
}

# ------------------------------------------------------------------------------- the supervisor

Test-Control 'the supervisor refuses a lane on the wrong branch' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    Invoke-Git -Path $worktree -Arguments @('checkout', '-q', '-b', 'somewhere-else') | Out-Null

    $supervise = Invoke-Script $Run @('build', '-Root', $repo, '-DryRun')
    if ($supervise.Code -eq 0) { return 'it ran anyway' }
    if ($supervise.Output -notmatch 'not .build.') { return 'refused for another reason' }
    return $true
}

Test-Control 'the supervisor refuses to drive a lane from inside itself' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'
    # A lane worktree shares the repository's config, so pointing -Root at the lane makes the lane
    # both the driver and the driven -- where a sync would rewrite the scripts running the loop.
    Copy-Item -LiteralPath (Join-Path $repo 'process.json') -Destination (Join-Path $worktree 'process.json') -Force
    $config = Read-TextUtf8 (Join-Path $worktree 'process.json') | ConvertFrom-Json
    $config.lanes[0].worktree = '.'
    [System.IO.File]::WriteAllText((Join-Path $worktree 'process.json'), ($config | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

    $supervise = Invoke-Script $Run @('build', '-Root', $worktree, '-DryRun')
    if ($supervise.Code -eq 0) { return 'it ran anyway' }
    if ($supervise.Output -notmatch 'from inside itself') { return 'refused for another reason' }
    return $true
}

# ---------------------------------------------------------------------------------------- done

if (-not $Keep) {
    foreach ($path in $Made) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
}

$failed = @($results | Where-Object { -not $_.Ok })
Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ("FAIL -- {0} of {1} control(s) did not behave" -f $failed.Count, $results.Count) -ForegroundColor Red
    exit 1
}
Write-Host ("PASS -- all {0} lane control(s) refused what they claim to refuse" -f $results.Count) -ForegroundColor Green
exit 0
