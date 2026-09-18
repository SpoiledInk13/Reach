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
$Publish = Join-Path $PSScriptRoot 'Publish.ps1'
$Made = New-Object System.Collections.Generic.List[string]

function Add-Remote {
    # A bare repository beside the fixture, wired as origin. It returns the bare path so a control can
    # look at what actually arrived instead of trusting the push's own exit code.
    param([string]$Repo)
    $bare = Join-Path (Split-Path -Parent $Repo) 'remote.git'
    Invoke-Git -Path (Split-Path -Parent $Repo) -Arguments @('init', '-q', '--bare', $bare) | Out-Null
    Invoke-Git -Path $Repo -Arguments @('remote', 'add', 'origin', $bare) | Out-Null
    return $bare
}

function New-Fixture {
    param([string]$Mode = 'objects', [string]$LaneDir = 'build', [switch]$PublishAll)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("reach-lane-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $Made.Add($root) | Out-Null

    Invoke-Git -Path $repo -Arguments @('init', '-q', '-b', 'working') | Out-Null
    Invoke-Git -Path $repo -Arguments @('config', 'user.email', 'f@example.invalid') | Out-Null
    Invoke-Git -Path $repo -Arguments @('config', 'user.name', 'Fixture') | Out-Null

    $integration = @{ branch = 'develop'; primary = 'working'; mode = $Mode; remote = 'origin' }
    if ($PublishAll) { $integration['publishAll'] = $true }
    $config = @{
        project     = 'fixture'
        integration = $integration
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
    $launch = Get-PowerShellArgs
    $output = & (Get-PowerShellExe) @launch -File $Script @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

function New-Message {
    param([string]$Repo, [string]$Text = 'land')
    $path = Join-Path (Split-Path -Parent $Repo) 'msg.txt'
    [System.IO.File]::WriteAllText($path, "$Text`n", (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Set-ProcessField {
    # One top-level field in a fixture's process.json, leaving everything else as it was.
    param([string]$Repo, [string]$Name, $Value)
    $path = Join-Path $Repo 'process.json'
    $config = Read-TextUtf8 $path | ConvertFrom-Json
    if ($config.PSObject.Properties.Match($Name).Count) { $config.$Name = $Value }
    else { $config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    [System.IO.File]::WriteAllText($path, ($config | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
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

Test-Control 'sync does not call a lane''s own lock uncommitted work' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'

    # A supervisor holding its lane is the ordinary state, not an unusual one -- and it used to make
    # the lane unsyncable, because the lock file is untracked and sat in the way of the guard.
    $held = Enter-LaneLock -LaneWorktree $worktree -Owner 'supervisor'
    if (-not $held.Ok) { return 'could not take the lock' }
    try {
        # develop must have moved, or sync short-circuits as up to date before reaching the guard.
        Invoke-Git -Path $repo -Arguments @('checkout', '-q', 'develop') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'b.txt'), 'b')
        Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
        Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'on develop') | Out-Null
        Invoke-Git -Path $repo -Arguments @('checkout', '-q', 'working') | Out-Null

        $sync = Invoke-Script $Lane @('sync', 'build', '-Root', $repo)
        if ($sync.Code -ne 0) { return "sync refused a lane holding only its own lock: $($sync.Output)" }
    } finally {
        Exit-LaneLock -LaneWorktree $worktree
    }
    return $true
}

Test-Control 'status does not count reach''s own files as uncommitted, and still counts everything else' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'

    $held = Enter-LaneLock -LaneWorktree $worktree -Owner 'supervisor'
    if (-not $held.Ok) { return 'could not take the lock' }
    try {
        # Where Run-Lane writes them: inside the primary checkout's working tree.
        New-Item -ItemType Directory -Path (Join-Path $repo 'Logs/reach-lane/build') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'Logs/reach-lane/build/status.txt'), "running`n")

        $quiet = Invoke-Script $Lane @('status', '-Root', $repo)
        if ($quiet.Output -match 'uncommitted') { return "reach's own files were counted: $($quiet.Output)" }

        # The other half: a filter that swallowed everything would have passed the line above. Real
        # work in the same trees must still be reported, or the guard has been turned off rather
        # than corrected.
        [System.IO.File]::WriteAllText((Join-Path $repo 'mine.txt'), "mine`n")
        [System.IO.File]::WriteAllText((Join-Path $worktree 'theirs.txt'), "theirs`n")
        $loud = Invoke-Script $Lane @('status', '-Root', $repo)
        if ($loud.Output -notmatch 'uncommitted') { return "real uncommitted work went unreported: $($loud.Output)" }
    } finally {
        Exit-LaneLock -LaneWorktree $worktree
    }
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

# --------------------------------------------------------------------------------- publishing

Test-Control 'a land publishes the integration branch without being asked' {
    $repo = New-Fixture
    $bare = Add-Remote $repo
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null

    $land = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -ne 0) { return "land exited $($land.Code): $($land.Output)" }
    $there = Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/develop')
    if (-not $there) { return 'the integration branch never reached the remote' }
    if ($there -ne (Get-GitValue -Path $repo -Arguments @('rev-parse', 'develop'))) { return 'the remote is at a different commit' }
    return $true
}

Test-Control 'a diverged lane branch does not block publication of the integration branch' {
    $repo = New-Fixture
    $bare = Add-Remote $repo
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'

    # The lane goes one way and the remote's copy of it goes another, so pushing 'build' can only be
    # refused. This used to be one --atomic push of develop, working and build together, so an
    # abandoned lane branch held the integration branch hostage -- and `publish` recomputed the same
    # doomed list every time it was run.
    [System.IO.File]::WriteAllText((Join-Path $worktree 'lane.md'), 'lane work')
    Invoke-Git -Path $worktree -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('commit', '-qm', 'in the lane') | Out-Null

    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null
    Invoke-Git -Path $repo -Arguments @('push', 'origin', 'working:build') | Out-Null

    $land = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -ne 0) { return "a diverged lane branch failed the whole land: $($land.Output)" }

    $there = Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/develop')
    if (-not $there) { return 'the integration branch never reached the remote' }
    if ($there -ne (Get-GitValue -Path $repo -Arguments @('rev-parse', 'develop'))) { return 'the remote is at a different commit' }

    # And it must say so rather than passing in silence: that branch really did not publish.
    if ($land.Output -notmatch 'WARNING') { return "it published nothing for the lane and said nothing: $($land.Output)" }
    return $true
}

Test-Control 'a land whose publish is refused fails, and keeps the merge it already made' {
    $repo = New-Fixture
    # A remote that resolves to nothing. The merge is local and succeeds; only the push can fail,
    # which is the one ordering that makes "landed" and "published" come apart.
    Invoke-Git -Path $repo -Arguments @('remote', 'add', 'origin', (Join-Path (Split-Path -Parent $repo) 'not-a-repository.git')) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null
    $tip = Get-GitValue -Path $repo -Arguments @('rev-parse', 'working')

    $land = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -eq 0) { return 'it reported a clean land with nothing published' }
    if ($land.Output -notmatch 'FAILED: publishing') { return 'it failed for another reason' }
    # The merge is not rolled back -- only the publish is owed, and `publish` is what pays it. Without
    # this line the control would pass just as happily on a land that threw the work away.
    $contains = Invoke-Git -Path $repo -Arguments @('merge-base', '--is-ancestor', $tip, 'develop')
    if ($contains.Code -ne 0) { return 'it lost the merge as well' }
    return $true
}

Test-Control 'publish pays the debt a failed land left' {
    $repo = New-Fixture
    Invoke-Git -Path $repo -Arguments @('remote', 'add', 'origin', (Join-Path (Split-Path -Parent $repo) 'not-a-repository.git')) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null
    Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo) | Out-Null

    # The remote comes back. Nothing needs re-landing; the publish is retried on its own.
    $bare = Join-Path (Split-Path -Parent $repo) 'remote.git'
    Invoke-Git -Path (Split-Path -Parent $repo) -Arguments @('init', '-q', '--bare', $bare) | Out-Null
    Invoke-Git -Path $repo -Arguments @('remote', 'set-url', 'origin', $bare) | Out-Null

    # $paid, not $publish -- see the shadowing note below; the same casing trap applies to $Publish.
    $paid = Invoke-Script $Publish @('-Root', $repo)
    if ($paid.Code -ne 0) { return "publish exited $($paid.Code): $($paid.Output)" }
    if (-not (Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/develop'))) { return 'still unpublished' }
    return $true
}

Test-Control 'landing again after a refused publish publishes, rather than reporting a clean no-op' {
    $repo = New-Fixture
    Invoke-Git -Path $repo -Arguments @('remote', 'add', 'origin', (Join-Path (Split-Path -Parent $repo) 'not-a-repository.git')) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null
    $first = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($first.Code -eq 0) { return 'the first land did not fail' }

    $bare = Join-Path (Split-Path -Parent $repo) 'remote.git'
    Invoke-Git -Path (Split-Path -Parent $repo) -Arguments @('init', '-q', '--bare', $bare) | Out-Null
    Invoke-Git -Path $repo -Arguments @('remote', 'set-url', 'origin', $bare) | Out-Null

    # The merge is already on the integration branch, so this is the NOTHING TO LAND path. Exiting
    # green there without retrying the push would confirm the exact state that went wrong.
    $again = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($again.Code -ne 0) { return "second land exited $($again.Code): $($again.Output)" }
    if (-not (Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/develop'))) { return 'it reported no-op and left it unpublished' }
    return $true
}

Test-Control 'a lane declared but never seeded does not block the publish' {
    $repo = New-Fixture
    $bare = Add-Remote $repo
    # Naming a ref that does not exist makes git refuse the whole atomic push, so an unseeded lane
    # would take every other ref down with it rather than being skipped.
    $config = Read-TextUtf8 (Join-Path $repo 'process.json') | ConvertFrom-Json
    $config.lanes = @($config.lanes) + @([pscustomobject]@{ name = 'ghost'; branch = 'never-seeded'; worktree = '../lanes/ghost'; command = '/reach:build' })
    [System.IO.File]::WriteAllText((Join-Path $repo 'process.json'), ($config | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'declare a lane nobody seeded') | Out-Null

    $land = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -ne 0) { return "land exited $($land.Code): $($land.Output)" }
    if ($land.Output -notmatch 'PUBLISHED') { return 'nothing was published' }
    if (Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/never-seeded')) { return 'it invented the branch' }
    return $true
}

Test-Control 'a repository with no remote still lands, and says it published nothing' {
    $repo = New-Fixture
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null

    $land = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -ne 0) { return "land exited $($land.Code): $($land.Output)" }
    # Silence here would read exactly like a successful publish, which is the failure this whole
    # mechanism exists to stop.
    if ($land.Output -notmatch 'NOT PUBLISHED') { return 'it did not say so' }
    return $true
}

Test-Control 'a branch carrying no part of the process is left alone, until publishAll' {
    $repo = New-Fixture
    $bare = Add-Remote $repo
    Invoke-Git -Path $repo -Arguments @('branch', 'scratch') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null
    # Not $land: PowerShell variables are case-insensitive, so assigning $land here would shadow the
    # $Land script path for the second Invoke-Script below and run the result object as a file.
    $plain = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($plain.Code -ne 0) { return "land exited $($plain.Code): $($plain.Output)" }
    if (Get-GitValue -Path $bare -Arguments @('rev-parse', '--verify', 'refs/heads/scratch')) { return 'it published a branch nobody asked it to' }

    $opted = New-Fixture -PublishAll
    $optedBare = Add-Remote $opted
    Invoke-Git -Path $opted -Arguments @('branch', 'scratch') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $opted 'note.md'), 'a decision')
    Invoke-Git -Path $opted -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $opted -Arguments @('commit', '-qm', 'a decision') | Out-Null
    $second = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $opted), '-Root', $opted)
    if ($second.Code -ne 0) { return "opted-in land exited $($second.Code): $($second.Output)" }
    if (-not (Get-GitValue -Path $optedBare -Arguments @('rev-parse', '--verify', 'refs/heads/scratch'))) { return 'publishAll took nothing extra' }
    return $true
}

# ----------------------------------------------------------------------------- the primary tree

function Update-Integration {
    # A land, in miniature: the integration ref moves from objects while the primary keeps its own
    # branch checked out, so no file in that working tree changes to say the documents moved.
    param([string]$Repo, [string]$Branch = 'develop')
    $head = Get-GitValue -Path $Repo -Arguments @('rev-parse', $Branch)
    $tree = Get-GitValue -Path $Repo -Arguments @('rev-parse', ($Branch + '^{tree}'))
    $landed = Get-GitValue -Path $Repo -Arguments @('commit-tree', $tree, '-p', $head, '-m', 'a lane landed')
    Invoke-Git -Path $Repo -Arguments @('branch', '-f', $Branch, $landed) | Out-Null
}

Test-Control 'sync -Primary brings the primary checkout up to the integration branch' {
    $repo = New-Fixture
    Update-Integration $repo
    $behind = Invoke-Git -Path $repo -Arguments @('merge-base', '--is-ancestor', 'develop', 'HEAD')
    if ($behind.Code -eq 0) { return 'the fixture was not stale to begin with' }

    $sync = Invoke-Script $Lane @('sync', '-Primary', '-Root', $repo)
    if ($sync.Code -ne 0) { return "sync exited $($sync.Code): $($sync.Output)" }
    $contains = Invoke-Git -Path $repo -Arguments @('merge-base', '--is-ancestor', 'develop', 'HEAD')
    if ($contains.Code -ne 0) { return 'the primary still does not contain the integration branch' }
    return $true
}

Test-Control 'sync -Primary refuses to write the integration delta over uncommitted work' {
    $repo = New-Fixture
    Update-Integration $repo
    [System.IO.File]::WriteAllText((Join-Path $repo 'dirty.txt'), 'half a decision')

    $sync = Invoke-Script $Lane @('sync', '-Primary', '-Root', $repo)
    if ($sync.Code -eq 0) { return 'it synced over them' }
    if ($sync.Output -notmatch 'uncommitted') { return 'refused for another reason' }
    return $true
}

Test-Control 'status gives the primary a row, and calls it stale' {
    $repo = New-Fixture
    Update-Integration $repo
    $status = Invoke-Script $Lane @('status', '-Root', $repo)
    if ($status.Code -ne 0) { return "status exited $($status.Code): $($status.Output)" }
    # Without a row of its own the primary's drift is invisible in the one command an agent runs to
    # see where everything stands, which is how it stayed invisible.
    if ($status.Output -notmatch 'primary') { return 'no primary row' }
    if ($status.Output -notmatch 'STALE') { return 'it did not say the primary was stale' }
    return $true
}

Test-Control 'sync refuses -Primary and a lane name together' {
    $repo = New-Fixture
    $sync = Invoke-Script $Lane @('sync', 'build', '-Primary', '-Root', $repo)
    if ($sync.Code -eq 0) { return 'it picked one silently' }
    if ($sync.Output -notmatch 'two different things') { return 'refused for another reason' }
    return $true
}

Test-Control 'land -Branch publishes a branch that is not a lane' {
    $repo = New-Fixture
    # The primary's own branch, which is how the ideate command publishes. It is not a lane, and
    # -Lane would refuse it -- which is exactly the hole this closes.
    [System.IO.File]::WriteAllText((Join-Path $repo 'note.md'), 'a decision')
    Invoke-Git -Path $repo -Arguments @('add', '-A') | Out-Null
    Invoke-Git -Path $repo -Arguments @('commit', '-qm', 'a decision') | Out-Null

    $land = Invoke-Script $Land @('-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -ne 0) { return "land exited $($land.Code): $($land.Output)" }
    $contains = Invoke-Git -Path $repo -Arguments @('merge-base', '--is-ancestor', 'working', 'develop')
    if ($contains.Code -ne 0) { return 'develop does not contain it' }
    return $true
}

Test-Control 'land refuses the integration branch as its own tip' {
    $repo = New-Fixture
    $land = Invoke-Script $Land @('-Branch', 'develop', '-Message', (New-Message $repo), '-Root', $repo)
    if ($land.Code -eq 0) { return 'it tried' }
    if ($land.Output -notmatch 'integration branch') { return 'refused for another reason' }
    return $true
}

Test-Control 'land refuses naming both a lane and a branch, or neither' {
    $repo = New-Fixture
    $both = Invoke-Script $Land @('-Lane', 'build', '-Branch', 'working', '-Message', (New-Message $repo), '-Root', $repo)
    if ($both.Code -eq 0) { return 'both was allowed' }
    $neither = Invoke-Script $Land @('-Message', (New-Message $repo), '-Root', $repo)
    if ($neither.Code -eq 0) { return 'neither was allowed' }
    return $true
}

# ------------------------------------------------------------------------------------ the audit

Test-Control 'audit reports an unseeded lane and a missing shim' {
    $repo = New-Fixture
    $audit = Invoke-Script (Join-Path $PSScriptRoot 'Audit.ps1') @('-Root', $repo)
    if ($audit.Code -eq 0) { return 'it reported complete on a bare fixture' }
    if ($audit.Output -notmatch 'not seeded') { return 'it did not notice the unseeded lane' }
    if ($audit.Output -notmatch 'reach.ps1') { return 'it did not notice the missing shim' }
    return $true
}

Test-Control 'audit notices the integration branch being checked out' {
    $repo = New-Fixture
    Invoke-Git -Path $repo -Arguments @('checkout', '-q', 'develop') | Out-Null
    $audit = Invoke-Script (Join-Path $PSScriptRoot 'Audit.ps1') @('-Root', $repo)
    if ($audit.Output -notmatch 'checked out') { return 'it did not notice' }
    return $true
}

Test-Control 'audit measures the reach version a repository records against the one installed' {
    # The field exists to make version drift visible. It used to gap only on absence and print the two
    # numbers with no verdict, so the state it was invented to catch read as up to date.
    $installed = [string](Get-Field (Read-TextUtf8 (Join-Path (Split-Path -Parent $PSScriptRoot) '.claude-plugin/plugin.json') | ConvertFrom-Json) 'version' '0.0.0')

    $behind = New-Fixture
    Set-ProcessField -Repo $behind -Name 'reach' -Value '0.0.1'
    $old = Invoke-Script (Join-Path $PSScriptRoot 'Audit.ps1') @('-Root', $behind)
    if ($old.Code -eq 0) { return 'a repository set up against an older reach reported complete' }
    if ($old.Output -notmatch 'set up against reach 0\.0\.1') { return "it did not name the drift: $($old.Output)" }

    $ahead = New-Fixture
    Set-ProcessField -Repo $ahead -Name 'reach' -Value '99.0.0'
    $new = Invoke-Script (Join-Path $PSScriptRoot 'Audit.ps1') @('-Root', $ahead)
    if ($new.Output -notmatch 'only .* is installed here') { return "it did not notice this clone is behind: $($new.Output)" }

    # And the other half: a matching version must not be reported as drift, or the check is just noise.
    $same = New-Fixture
    Set-ProcessField -Repo $same -Name 'reach' -Value $installed
    $match = Invoke-Script (Join-Path $PSScriptRoot 'Audit.ps1') @('-Root', $same)
    if ($match.Output -match 'set up against reach') { return "it reported drift against its own version: $($match.Output)" }
    return $true
}

Test-Control 'audit says not adopted when there is no process.json' {
    $repo = New-Fixture
    Remove-Item -LiteralPath (Join-Path $repo 'process.json') -Force
    $audit = Invoke-Script (Join-Path $PSScriptRoot 'Audit.ps1') @('-Root', $repo)
    if ($audit.Code -eq 0) { return 'it reported complete' }
    if ($audit.Output -notmatch 'NOT ADOPTED') { return 'it said something else' }
    return $true
}

# ------------------------------------------------------------------------------- the supervisor

Test-Control 'a lane whose reflog was expired is not reported as reflogs being off' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'

    # What gc does after gc.reflogExpire, and what a clone does for a branch it never checked out.
    # The branch is healthy and logging is on; only the entries are gone.
    Invoke-Git -Path $worktree -Arguments @('reflog', 'expire', '--expire=all', '--all') | Out-Null

    $count = Get-LaneWorkCount -Path $worktree -Branch 'build' -Since (Get-Date)
    if ($count -ne 0) { return "it counted $count commits from an empty reflog" }
    return $true
}

Test-Control 'a lane with reflogs actually turned off still says so' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null
    $worktree = Join-Path (Split-Path -Parent $repo) 'lanes/build'

    # The other half. Counting zero here would be the false halt the reflog approach replaced, so
    # the cause that genuinely cannot be counted must still refuse.
    Invoke-Git -Path $worktree -Arguments @('config', 'core.logAllRefUpdates', 'false') | Out-Null
    Invoke-Git -Path $worktree -Arguments @('reflog', 'expire', '--expire=all', '--all') | Out-Null

    $threw = $null
    try { Get-LaneWorkCount -Path $worktree -Branch 'build' -Since (Get-Date) | Out-Null }
    catch { $threw = $_.Exception.Message }
    if (-not $threw) { return 'it counted instead of refusing' }
    if ($threw -notmatch 'logAllRefUpdates') { return "refused for another reason: $threw" }
    return $true
}

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

Test-Control 'the supervisor refuses a lane command no installed plugin defines' {
    $repo = New-Fixture
    Invoke-Script $Lane @('seed', 'build', '-Root', $repo) | Out-Null

    # A plugin name nothing could have installed. The lane is healthy in every other respect, so every
    # earlier guard passes and this is the one that has to speak -- otherwise the agent is handed a
    # slash command that resolves to nothing and left to improvise.
    Set-ProcessField -Repo $repo -Name 'lanes' -Value @(@{
        name = 'build'; branch = 'build'; worktree = '../lanes/build'; command = '/reach-not-installed:build'
    })

    $supervise = Invoke-Script $Run @('build', '-Root', $repo, '-DryRun')
    if ($supervise.Code -eq 0) { return 'it started anyway' }
    if ($supervise.Output -notmatch 'no plugin') { return "refused for another reason: $($supervise.Output)" }
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
