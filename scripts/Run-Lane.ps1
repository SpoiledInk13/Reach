#Requires -Version 5.1
<#
.SYNOPSIS
    Runs a lane unattended: a fresh agent process per run, until a run commits nothing.

.DESCRIPTION
    Each run is a NEW `claude -p` process in the lane's worktree, not another turn in one long
    session. That is the point rather than an implementation detail: several of the build command's
    stop conditions are "this session has run long enough to stop trusting its own memory of the
    documents", and a fresh process is the only thing that actually answers them. An in-session loop
    grows the same context until it compacts, which is the state those conditions exist to prevent.

    It stops when a run commits nothing to the lane branch, which means every claim whose dependencies
    are built is blocked on an answer. Past that the owner starts it and the owner stops it.

    Whether a run did anything is read from the lane branch's REFLOG, not from the shape of the commit
    graph. A reflog entry's subject says which operation moved the ref: the lane's own writes are
    `commit:`, everything else is a merge or a reset. Only the lane writes that ref, so `commit`
    entries are its work and nothing else's. Counting by comparing tips instead reports zero on
    exactly the runs that succeeded -- the ones that landed and fast-forwarded the lane afterwards.

    Every run has background tasks disabled. A `claude -p` process ends with its turn and kills
    whatever it left running, and a verification sweep longer than the Bash tool's ten-minute
    foreground cap gets backgrounded. Three runs in one day did exactly that: each started its sweep,
    said it would pick it up when it reported, and ended its turn. Each verification was killed, and
    each verified batch waited unlanded for the next run. A rule asking the run to wait cannot fix
    this, because the run is told it will be notified and nothing in -p ever notifies it. So
    CLAUDE_CODE_DISABLE_BACKGROUND_TASKS removes `run_in_background` from the tool schema, and
    BASH_MAX_TIMEOUT_MS is raised so that a whole sweep fits in one foreground call. A task killed
    after the run's final result is still written to the ledger as KILLED AT EXIT, because that is
    what this defect looks like if a later CLI stops honouring the variable.

.PARAMETER Lane
    The lane to run, by name from process.json.

.PARAMETER Status
    Print the current status line and exit. Answers "is it still going?" from another terminal.

.PARAMETER Follow
    With -Status, keep printing until the loop ends.

.PARAMETER Check
    Say whether anything holds the lane and exit: 0 nothing, 1 a supervisor is running. Read from the
    lane lock rather than a process table, and it also reports uncommitted work in the lane, which is
    the only trace a session started by hand leaves.

.PARAMETER Watch
    Follow the newest ledger as a short event stream, for a chat window rather than a terminal: run
    boundaries, verdicts and a `progress:` line when the lane branch moves, never the per-tool lines
    -Follow prints. Exits 0 when the supervisor finishes, 4 when it crashed, 2 when no supervisor
    holds the lane and its ledger never said it finished, 3 when -NewRun saw it never start, 1 when
    there is nothing to watch. A supervisor holding the lane through a long silent tool call is a
    `quiet:` line, never a stale one.

.PARAMETER NewRun
    With -Watch: wait up to two minutes for a ledger newer than this call, so a watch started in the
    same breath as the supervisor follows the new run rather than finding the previous one finished.

.PARAMETER FromEnd
    With -Watch: skip the lines already written, for re-arming a watch that expired. A last line
    written in the gap is still found and reported.

.PARAMETER Stop
    Ask the loop to stop after the run in flight, so that run still lands.

.PARAMETER SelfTest
    Exercise the decision, the guards, the stop request and the renderer against synthetic input.
    Seconds, and touches nothing.

.PARAMETER DryRun
    Run one whole iteration against the real lane, with a trivial prompt in place of the lane's
    command. This exists because -SelfTest cannot see the loop: in the original, every guard passed on
    the first real invocation and it died three lines into the loop body, and the first fix died three
    lines further on. A stand-in for the agent would have caught neither the launch nor the stream
    parsing, which is why this makes a real call.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Lane = 'build',
    [string]$Root,
    [switch]$Status,
    [switch]$Follow,
    [switch]$Check,
    [switch]$Watch,
    [switch]$NewRun,
    [switch]$FromEnd,
    [switch]$Stop,
    [switch]$SelfTest,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }

$integration = Get-Integration $Process
$laneConfig  = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $Lane
if (-not $laneConfig) {
    Write-Host ("REFUSED: no lane named '{0}'. Known: {1}" -f $Lane, ((Get-LaneNames $Process) -join ', ')) -ForegroundColor Red
    exit 2
}

$LogRoot    = Join-Path $RepoRoot ("Logs/reach-lane/" + $laneConfig.Name)
$StopFile   = Join-Path $LogRoot 'STOP'
$StatusFile = Join-Path $LogRoot 'status.txt'
$script:StaleAfter = [TimeSpan]::FromMinutes(20)

# ------------------------------------------------------------------------------ status and stop

function Write-StatusLine {
    param([int]$Run, [timespan]$Elapsed, [string]$Event, [bool]$StopPending)
    $line = "lane={0} run={1} elapsed={2:hh\:mm\:ss} committed={3} stop={4} at={5} :: {6}" -f `
        $laneConfig.Name, $Run, $Elapsed, $script:CommittedThisRun, $StopPending,
        (Get-Date -Format 'HH:mm:ss'), $Event
    try { [System.IO.File]::WriteAllText($StatusFile, $line, (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

function Show-Status {
    if (-not (Test-Path -LiteralPath $StatusFile)) {
        Write-Host ("No status for lane '{0}'. It has not run, or its logs were cleared." -f $laneConfig.Name) -ForegroundColor Yellow
        return $false
    }
    $line = (Read-TextUtf8 $StatusFile).Trim()
    $age = (Get-Date) - (Get-Item -LiteralPath $StatusFile).LastWriteTime
    $old = $age -gt $script:StaleAfter
    # Age alone cannot say dead: the status is written when the agent says something, and one long
    # tool call says nothing for as long as it runs. The lock says whether the supervisor is there.
    $holder = $null
    if ($old) { $holder = Get-LaneHolder -LaneWorktree $laneConfig.Worktree }
    $stale = $old -and -not $holder
    $colour = if ($stale) { 'Red' } elseif ($old) { 'Yellow' } else { 'Green' }
    Write-Host $line -ForegroundColor $colour
    if ($stale) {
        Write-Host ("  nothing has refreshed this for {0:hh\:mm\:ss} and nothing holds the lane -- that is a dead supervisor, not a quiet one." -f $age) -ForegroundColor Red
    } elseif ($old) {
        Write-Host ("  quiet for {0:hh\:mm\:ss}, but pid {1} still holds the lane -- most likely one long tool call." -f $age, (Get-Field $holder 'pid' '?')) -ForegroundColor Yellow
    }
    return (-not $stale)
}

if ($Status) {
    $alive = Show-Status
    if ($Follow) {
        while ($alive) { Start-Sleep -Seconds 10; $alive = Show-Status }
    }
    exit 0
}

if ($Stop) {
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    [System.IO.File]::WriteAllText($StopFile, (Get-Date).ToString('o'), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("Stop requested for lane '{0}'. The run in flight finishes and lands; nothing starts after it." -f $laneConfig.Name) -ForegroundColor Yellow
    Write-Host '  (Ctrl-C instead would kill the run and lose whatever it had not committed.)' -ForegroundColor DarkGray
    exit 0
}

# ------------------------------------------------------------------------------ check and watch

# The supervisor's last ledger lines: a finish (a halt and a stop both end in one) and a crash.
$script:EndPattern   = 'lane supervisor -- .+ -- finished after|supervisor CRASHED'
# The per-event lines: a terminal wants them, a chat window is flooded by them.
$script:NoisePattern = '^\[\d\d:\d\d:\d\d\]\s{3}(tool|say|done)\s{2}'
# Seams the self-test replaces: who holds the lane, where the lane branch is, the poll, the output.
$script:HolderProbe = { Get-LaneHolder -LaneWorktree $laneConfig.Worktree }
$script:TipProbe    = { Get-GitValue -Path $laneConfig.Worktree -Arguments @('log', '-1', '--format=%h %s', $laneConfig.Branch) }
$script:WatchPoll   = 5
$script:Captured    = $null
# Unbounded for a real watch. The self-test bounds it, so a watch that never sees its last line fails
# the test rather than hanging it.
$script:WatchMaxPolls = 0

function Out-Watch {
    # Flushed per line: a watcher whose lines sit in a buffer reports nothing until it exits.
    param([AllowEmptyString()][string]$Text)
    if ($null -ne $script:Captured) { $script:Captured.Add($Text) | Out-Null; return }
    [Console]::Out.WriteLine($Text)
    [Console]::Out.Flush()
}

function Read-LinesUtf8 {
    # Without the final newline: every ledger line ends in one, and splitting it in leaves an empty
    # last element that counts as a line read -- so the next line appended lands on an index the
    # watch has already passed, and a finish is never seen.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try { return @((Read-TextUtf8 $Path).TrimEnd("`r", "`n") -split "`r?`n") } catch { return @() }
}

function Find-Ledger {
    # The newest run directory's ledger. Directories are stamped yyyy-MM-dd_HHmmss, so name order is
    # time order; -Since keeps only one made after a launch.
    param([string]$Root, [Nullable[datetime]]$Since)
    if (-not (Test-Path -LiteralPath $Root)) { return $null }
    $dirs = @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name -Descending)
    foreach ($dir in $dirs) {
        $ledger = Join-Path $dir.FullName 'ledger.txt'
        if (-not (Test-Path -LiteralPath $ledger)) { continue }
        if ($Since -and $dir.CreationTime -lt $Since.Value.AddSeconds(-2)) { return $null }
        return $ledger
    }
    return $null
}

function Get-EndCode {
    param([string]$Line)
    if ($Line -match 'CRASHED') { return 4 }
    return 0
}

function Invoke-LaneWatch {
    param([string]$Root, [string]$StatusPath, [bool]$WaitForNew, [bool]$SkipWritten)

    $ledger = $null
    if ($WaitForNew) {
        $launched = Get-Date
        $deadline = $launched.AddMinutes(2)
        while (-not $ledger -and (Get-Date) -lt $deadline) {
            $ledger = Find-Ledger -Root $Root -Since $launched
            if (-not $ledger) { Start-Sleep -Seconds ([Math]::Max(1, $script:WatchPoll)) }
        }
        if (-not $ledger) {
            Out-Watch 'NOT STARTED: no new ledger within two minutes, so the supervisor stopped at a guard before its loop. Its console says which.'
            return 3
        }
    } else {
        $ledger = Find-Ledger -Root $Root
        if (-not $ledger) { Out-Watch "nothing to watch: no ledger under $Root."; return 1 }
    }
    Out-Watch "watching $ledger"

    $seen = 0
    if ($SkipWritten) {
        $lines = @(Read-LinesUtf8 $ledger)
        foreach ($line in $lines) {
            if ($line -match $script:EndPattern) { Out-Watch $line; return (Get-EndCode $line) }
        }
        $seen = $lines.Count
    }

    $lastTip = & $script:TipProbe
    $goneOnce = $false
    $quietSaid = $null
    $polls = 0
    while ($true) {
        $polls++
        if ($script:WatchMaxPolls -gt 0 -and $polls -gt $script:WatchMaxPolls) { Out-Watch 'GAVE UP: the poll limit was reached.'; return 5 }
        $lines = @(Read-LinesUtf8 $ledger)
        for ($i = $seen; $i -lt $lines.Count; $i++) {
            $line = [string]$lines[$i]
            if ($line.Trim().Length -eq 0) { continue }
            if ($line -match $script:EndPattern) { Out-Watch $line; return (Get-EndCode $line) }
            if ($line -match $script:NoisePattern) { continue }
            Out-Watch $line
        }
        if ($lines.Count -gt $seen) { $seen = $lines.Count }

        $tip = & $script:TipProbe
        if ($tip -and $tip -ne $lastTip) { Out-Watch "progress: $tip"; $lastTip = $tip }

        if (& $script:HolderProbe) {
            $goneOnce = $false
            $age = $null
            if (Test-Path -LiteralPath $StatusPath) { $age = (Get-Date) - (Get-Item -LiteralPath $StatusPath).LastWriteTime }
            if ($null -ne $age -and $age -gt $script:StaleAfter) {
                if ($null -eq $quietSaid -or ((Get-Date) - $quietSaid) -ge $script:StaleAfter) {
                    Out-Watch ("quiet: no status for {0:N0} minute(s), but the supervisor still holds the lane -- most likely one long tool call. Still following." -f $age.TotalMinutes)
                    $quietSaid = Get-Date
                }
            } else { $quietSaid = $null }
        } elseif ($goneOnce) {
            # Twice, a poll apart: the supervisor releases the lock a moment before it writes its last
            # line, so one empty reading can be a clean finish that has not landed in the file yet.
            # The loop above has read the file again since, so an end line would already have returned.
            Out-Watch 'STALE: nothing holds the lane and its ledger never said it finished, so the supervisor was killed or its window closed. Its console is the record.'
            return 2
        } else {
            $goneOnce = $true
        }
        Start-Sleep -Seconds $script:WatchPoll
    }
}

function Invoke-LaneCheck {
    $holder = Get-LaneHolder -LaneWorktree $laneConfig.Worktree
    if ($holder) {
        Out-Watch ("running: {0} (pid {1}) since {2}" -f (Get-Field $holder 'owner' '?'), (Get-Field $holder 'pid' '?'), (Get-Field $holder 'since' '?'))
    }
    if (Test-Path -LiteralPath $StatusFile) {
        $age = (Get-Date) - (Get-Item -LiteralPath $StatusFile).LastWriteTime
        Out-Watch ("status: written {0:N0} minute(s) ago -- {1}" -f $age.TotalMinutes, (Read-TextUtf8 $StatusFile).Trim())
    } else {
        Out-Watch 'status: none written since the logs were last cleared.'
    }
    if (Test-Path -LiteralPath $laneConfig.Worktree) {
        $dirt = Get-WorktreeDirt -Path $laneConfig.Worktree
        if ($dirt.Lines.Count -gt 0) {
            Out-Watch ("lane: {0} uncommitted change(s) -- a run in flight, a session started by hand, or one that died mid-work." -f $dirt.Lines.Count)
        } else {
            Out-Watch 'lane: clean'
        }
    } else {
        Out-Watch ("lane: not seeded -- Lane.ps1 seed {0}" -f $laneConfig.Name)
    }
    if ($holder) { Out-Watch 'verdict: RUNNING'; return 1 }
    Out-Watch 'verdict: NOT RUNNING'
    return 0
}

if ($Check) { exit (Invoke-LaneCheck) }
if ($Watch) { exit (Invoke-LaneWatch -Root $LogRoot -StatusPath $StatusFile -WaitForNew ([bool]$NewRun) -SkipWritten ([bool]$FromEnd)) }

# ------------------------------------------------------------------------------- reading a run

function Format-StreamEvent {
    <#
        One short line per interesting event. `claude -p` in its default text format prints nothing
        at all until it exits, so an unattended run would be silent for its whole length; stream-json
        is what makes it readable live. A line that cannot be parsed is shown raw rather than dropped.
    #>
    param([string]$Json)
    if (-not $Json -or -not $Json.TrimStart().StartsWith('{')) { return $null }

    $event = $null
    try { $event = $Json | ConvertFrom-Json } catch { return $null }
    $type = Get-Field $event 'type' ''

    if ($type -eq 'assistant' -or $type -eq 'user') {
        $message = Get-Field $event 'message' $null
        foreach ($block in (ConvertTo-Array (Get-Field $message 'content' @()))) {
            $kind = Get-Field $block 'type' ''
            if ($kind -eq 'tool_use') { return "tool  " + (Get-Field $block 'name' '?') }
            if ($kind -eq 'text') {
                $text = ([string](Get-Field $block 'text' '')).Trim()
                if ($text) {
                    $text = ($text -split "`n")[0]
                    if ($text.Length -gt 110) { $text = $text.Substring(0, 110) + '...' }
                    return "say   $text"
                }
            }
        }
        return $null
    }
    if ($type -eq 'result') {
        return "done  " + (Get-Field $event 'subtype' 'result')
    }
    return $null
}

# What every run gets: no background tasks, and a foreground Bash cap of two hours, which is room for
# a whole verification sweep without letting one stuck call hold the lane all night. The header says why.
$script:RunVariables = [ordered]@{
    'CLAUDE_CODE_DISABLE_BACKGROUND_TASKS' = '1'
    'BASH_MAX_TIMEOUT_MS'                  = '7200000'
}

function Set-RunEnvironment {
    foreach ($name in @($script:RunVariables.Keys)) { [Environment]::SetEnvironmentVariable($name, $script:RunVariables[$name]) }
}

function Get-TasksKilledAtExit {
    # The summary of each task stopped after the run's final result. Those were killed because the
    # process exited. A task the run stopped itself, before its result, does not count.
    param([string[]]$Lines)
    $killed = New-Object System.Collections.Generic.List[string]
    foreach ($raw in (ConvertTo-Array $Lines)) {
        $t = ([string]$raw).Trim()
        if (-not $t.StartsWith('{')) { continue }
        $evt = $null
        try { $evt = $t | ConvertFrom-Json } catch { continue }
        if ((Get-Field $evt 'type' '') -eq 'result') { $killed.Clear(); continue }
        if ((Get-Field $evt 'subtype' '') -ne 'task_notification') { continue }
        if (@('stopped', 'killed') -notcontains [string](Get-Field $evt 'status' '')) { continue }
        $killed.Add([string](Get-Field $evt 'summary' (Get-Field $evt 'task_id' '?'))) | Out-Null
    }
    return ,$killed.ToArray()
}

# --------------------------------------------------------------------------------- the self-test

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    function Assert { param([bool]$Condition, [string]$What)
        if ($Condition) { Write-Host "  ok    $What" -ForegroundColor Green }
        else { Write-Host "  FAIL  $What" -ForegroundColor Red; $failures.Add($What) | Out-Null } }

    Write-Host 'Run-Lane -SelfTest' -ForegroundColor Cyan

    Assert ($null -eq (Format-StreamEvent 'not json')) 'a non-JSON line renders nothing'
    Assert ($null -eq (Format-StreamEvent '')) 'an empty line renders nothing'
    Assert ((Format-StreamEvent '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}') -eq 'tool  Edit') 'a tool call renders its name'
    Assert ((Format-StreamEvent '{"type":"result","subtype":"success"}') -eq 'done  success') 'a result renders its subtype'
    $long = '{"type":"assistant","message":{"content":[{"type":"text","text":"' + ('x' * 300) + '"}]}}'
    Assert ((Format-StreamEvent $long).Length -le 120) 'a long message is truncated rather than filling the ledger'

    # A task killed at exit, in the shape a real run left: the result, then the kill. The controls are a
    # task the run stopped itself before its result, and one that completed after it.
    $exited = @('{"type":"system","subtype":"task_notification","task_id":"a","status":"stopped","summary":"stopped mid-run on purpose"}',
                '{"type":"result","subtype":"success","is_error":false,"result":"The sweep is running in the background."}',
                '{"type":"system","subtype":"task_updated","task_id":"b","patch":{"status":"killed"}}',
                '{"type":"system","subtype":"task_notification","task_id":"b","status":"stopped","summary":"Run every tier"}',
                '{"type":"system","subtype":"task_notification","task_id":"c","status":"completed","summary":"finished in time"}')
    $k = Get-TasksKilledAtExit -Lines $exited
    Assert ($k.Count -eq 1 -and $k[0] -eq 'Run every tier') 'a sweep killed at exit is named, and only it'
    Assert ((Get-TasksKilledAtExit -Lines $exited[0..1]).Count -eq 0) 'a task the run stopped itself is not read as killed at exit'
    $savedRun = @{}
    foreach ($n in @($script:RunVariables.Keys)) { $savedRun[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        Set-RunEnvironment
        Assert ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_DISABLE_BACKGROUND_TASKS') -eq '1') 'a run starts with background tasks disabled'
        Assert ([int][Environment]::GetEnvironmentVariable('BASH_MAX_TIMEOUT_MS') -ge 1800000) 'a run can hold a thirty-minute sweep in the foreground'
    } finally {
        foreach ($n in @($savedRun.Keys)) { [Environment]::SetEnvironmentVariable($n, $savedRun[$n]) }
    }

    # The decision, against a real repository, which is the part that has been wrong before.
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("reach-lane-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    try {
        Invoke-Git -Path $fixture -Arguments @('init', '-q', '-b', 'lane') | Out-Null
        Invoke-Git -Path $fixture -Arguments @('config', 'user.email', 'f@example.invalid') | Out-Null
        Invoke-Git -Path $fixture -Arguments @('config', 'user.name', 'Fixture') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fixture 'a.txt'), 'a')
        Invoke-Git -Path $fixture -Arguments @('add', '-A') | Out-Null
        Invoke-Git -Path $fixture -Arguments @('commit', '-qm', 'one') | Out-Null

        # Assertions are relative, never absolute. The floor is truncated to a whole second on
        # purpose, so a commit made in the same second as the mark counts -- which means a fixture
        # built in well under a second cannot assert an absolute zero, and asserting one anyway made
        # three of these fail against a function that was correct.
        $base = Get-Date
        $atBase = Get-LaneWorkCount -Path $fixture -Branch 'lane' -Since $base

        Assert ((Get-LaneWorkCount -Path $fixture -Branch 'lane' -Since $base.AddSeconds(5)) -eq 0) 'nothing after a mark in the future reads as no work'

        [System.IO.File]::WriteAllText((Join-Path $fixture 'b.txt'), 'b')
        Invoke-Git -Path $fixture -Arguments @('add', '-A') | Out-Null
        Invoke-Git -Path $fixture -Arguments @('commit', '-qm', 'two') | Out-Null
        $afterCommit = Get-LaneWorkCount -Path $fixture -Branch 'lane' -Since $base
        Assert ($afterCommit -eq $atBase + 1) 'a commit the lane makes is counted'

        # The regression this whole approach exists for: a merge arriving afterwards must not be
        # counted as the lane's work, and must not erase it either. The branch has to actually
        # diverge -- merging a branch at the same commit is a no-op that writes no reflog entry, and
        # would have passed this test while proving nothing.
        # Named for this fixture, not a constant beside it: '../other-wt' was the same directory for
        # every run, so two self-tests at once collided and the cleanup could remove one the other
        # was still using.
        $otherWt = "$fixture-other-wt"
        Invoke-Git -Path $fixture -Arguments @('branch', 'other', 'HEAD~1') | Out-Null
        Invoke-Git -Path $fixture -Arguments @('worktree', 'add', '-q', $otherWt, 'other') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $otherWt 'd.txt'), 'd')
        Invoke-Git -Path $otherWt -Arguments @('add', '-A') | Out-Null
        Invoke-Git -Path $otherWt -Arguments @('commit', '-qm', 'elsewhere') | Out-Null
        $merge = Invoke-Git -Path $fixture -Arguments @('merge', '--no-ff', '--no-edit', 'other')
        Assert ($merge.Code -eq 0) 'the fixture merge actually merged something'
        Assert ((Get-LaneWorkCount -Path $fixture -Branch 'lane' -Since $base) -eq $afterCommit) 'a merge afterwards is not counted as the lane writing work'

        # A commit in the same second as the mark must still count: reflog timestamps carry seconds
        # and Get-Date carries ticks, and truncating the wrong way turns a short successful run into
        # a false halt.
        $tight = Get-Date
        [System.IO.File]::WriteAllText((Join-Path $fixture 'c.txt'), 'c')
        Invoke-Git -Path $fixture -Arguments @('add', '-A') | Out-Null
        Invoke-Git -Path $fixture -Arguments @('commit', '-qm', 'three') | Out-Null
        Assert ((Get-LaneWorkCount -Path $fixture -Branch 'lane' -Since $tight) -ge 1) 'a commit in the same second as the mark is counted'
    } finally {
        Remove-Item -LiteralPath $otherWt -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    # The watch, over a synthetic ledger with who holds the lane stood in for.
    $watchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("reach-watch-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $savedPoll = $script:WatchPoll; $savedHolder = $script:HolderProbe; $savedTip = $script:TipProbe
    try {
        $script:WatchPoll = 0
        $script:WatchMaxPolls = 20
        $script:TipProbe = { $null }
        $script:WatchLedger = Join-Path $watchRoot '2026-01-01_000000/ledger.txt'
        $watchStatus = Join-Path $watchRoot 'status.txt'
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:WatchLedger) -Force | Out-Null

        function Set-WatchFixture { param([string[]]$Lines)
            [System.IO.File]::WriteAllText($script:WatchLedger, (($Lines -join "`r`n") + "`r`n"))
            [System.IO.File]::WriteAllText($watchStatus, 'lane=build run=1 :: tool  Bash')
            # Older than the stale threshold, as a status is through one long silent tool call.
            (Get-Item -LiteralPath $watchStatus).LastWriteTime = (Get-Date).Add(-$script:StaleAfter).AddMinutes(-5) }
        function Invoke-CapturedWatch { param([bool]$SkipWritten = $false)
            $script:Captured = New-Object System.Collections.Generic.List[string]
            $code = Invoke-LaneWatch -Root $watchRoot -StatusPath $watchStatus -WaitForNew $false -SkipWritten $SkipWritten
            $said = @($script:Captured); $script:Captured = $null
            return [pscustomobject]@{ Code = $code; Said = $said } }
        $started = @('[10:00:00] lane supervisor -- build -- started', '[10:00:01] === run 1 ===', '[10:00:02]   tool  Bash')
        $finished = '[10:30:00] lane supervisor -- build -- finished after 1 run(s)'

        # Held through a quiet, then finished: followed to the last line, announced once, no tool lines.
        Set-WatchFixture $started
        $script:Polls = 0
        $script:HolderProbe = {
            $script:Polls++
            if ($script:Polls -ge 2) { [System.IO.File]::AppendAllText($script:WatchLedger, $finished + "`r`n") }
            [pscustomobject]@{ pid = 1; owner = 'Run-Lane' } }
        $w = Invoke-CapturedWatch
        Assert ($w.Code -eq 0) 'a quiet supervisor still holding the lane is followed to its finish'
        Assert (@($w.Said | Where-Object { $_ -like 'quiet:*' }).Count -eq 1) 'a quiet is announced once within its interval'
        Assert (-not ($w.Said | Where-Object { $_ -like 'STALE:*' })) 'a quiet supervisor still holding the lane is not called stale'
        Assert (-not ($w.Said | Where-Object { $_ -match '\btool  Bash' })) 'the per-tool lines a terminal wants are left out'

        # Nothing holds the lane and the ledger never finished: stale.
        Set-WatchFixture $started
        $script:HolderProbe = { $null }
        $w = Invoke-CapturedWatch
        Assert ($w.Code -eq 2) 'a supervisor gone without its last line is stale'

        # The lock released a moment before the last line lands: a finish, not a death.
        Set-WatchFixture $started
        $script:HolderProbe = { [System.IO.File]::AppendAllText($script:WatchLedger, $finished + "`r`n"); $null }
        $w = Invoke-CapturedWatch
        Assert ($w.Code -eq 0) 'a finish written just after the lock is released is a finish, not a death'

        # A crash is its own code, and a re-armed watch still finds a last line written in the gap.
        Set-WatchFixture ($started + '[10:05:00] supervisor CRASHED after 1 run(s): boom')
        $script:HolderProbe = { $null }
        $w = Invoke-CapturedWatch
        Assert ($w.Code -eq 4) 'a crash is reported as a crash'
        Set-WatchFixture ($started + $finished)
        $w = Invoke-CapturedWatch -SkipWritten $true
        Assert ($w.Code -eq 0) 'a re-armed watch still finds a last line written in the gap'
    } finally {
        $script:WatchPoll = $savedPoll; $script:HolderProbe = $savedHolder; $script:TipProbe = $savedTip
        $script:WatchMaxPolls = 0
        $script:Captured = $null
        Remove-Item -LiteralPath $watchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # The stop request round-trips.
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $hadStop = Test-Path -LiteralPath $StopFile
    if (-not $hadStop) {
        [System.IO.File]::WriteAllText($StopFile, 'x')
        Assert (Test-Path -LiteralPath $StopFile) 'a stop request can be written'
        Remove-Item -LiteralPath $StopFile -Force
        Assert (-not (Test-Path -LiteralPath $StopFile)) 'a stop request can be cleared'
    }

    Write-Host ''
    if ($failures.Count -gt 0) {
        Write-Host ("SELF-TEST FAILED -- {0}" -f $failures.Count) -ForegroundColor Red
        exit 1
    }
    Write-Host 'SELF-TEST PASSED. It does not cover the loop; use -DryRun for that.' -ForegroundColor Green
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

# ------------------------------------------------------------------------------------ the guards

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "REFUSED: the 'claude' CLI is not on PATH, so there is nothing to supervise." -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $laneConfig.Worktree)) {
    Write-Host ("REFUSED: lane '{0}' is not seeded. Run: Lane.ps1 seed {0}" -f $laneConfig.Name) -ForegroundColor Red
    exit 2
}
if (Test-SamePath -A $RepoRoot -B $laneConfig.Worktree) {
    Write-Host 'REFUSED: will not drive a lane from inside itself. A sync rewrites the lane scripts underneath the loop running them. Start this from the primary checkout.' -ForegroundColor Red
    exit 2
}
$onBranch = Get-GitValue -Path $laneConfig.Worktree -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
if ($onBranch -ne $laneConfig.Branch) {
    Write-Host ("REFUSED: the lane is on '{0}', not '{1}'. One agent per lane, one branch per lane." -f $onBranch, $laneConfig.Branch) -ForegroundColor Red
    exit 2
}
if (-not $laneConfig.Command) {
    Write-Host ("REFUSED: lane '{0}' declares no command to run." -f $laneConfig.Name) -ForegroundColor Red
    exit 2
}

# The lane command goes to `claude -p` as a PROMPT. If the plugin that defines it is not installed,
# "/reach:build" is not a command -- it is a line of prose, and the agent improvises against a
# repository full of documents it has no instructions for. Unattended, and with permission prompts
# skipped when the lane declares it. This is the one failure here that is invisible from the outside:
# the loop starts, the ledger fills, runs commit, and nothing says the instructions never loaded.
if ($laneConfig.Command -match '^/([A-Za-z0-9_.-]+):') {
    $plugin = $Matches[1]
    $manifest = Join-Path $HOME '.claude/plugins/installed_plugins.json'
    $present = $false
    if (Test-Path -LiteralPath $manifest) {
        $listed = Read-TextUtf8 $manifest | ConvertFrom-Json
        if ($listed.PSObject.Properties.Match('plugins').Count) {
            foreach ($property in $listed.plugins.PSObject.Properties) {
                if ($property.Name -like ($plugin + '@*')) { $present = $true; break }
            }
        }
    }
    if (-not $present) {
        Write-Host ("REFUSED: lane '{0}' runs '{1}', and no plugin '{2}' is installed for this user. The agent would read that as prose rather than a command and improvise." -f $laneConfig.Name, $laneConfig.Command, $plugin) -ForegroundColor Red
        Write-Host ("  claude plugin install {0}@{0}" -f $plugin) -ForegroundColor DarkGray
        exit 2
    }
}

$lock = Enter-LaneLock -LaneWorktree $laneConfig.Worktree -Owner 'Run-Lane'
if (-not $lock.Ok) {
    Write-Host ("REFUSED: lane '{0}' is already held. Two agents in one lane share its index and its cache, which is the collision lanes exist to remove." -f $laneConfig.Name) -ForegroundColor Red
    if ($lock.Held) { Write-Host ("  held by pid {0} since {1}" -f (Get-Field $lock.Held 'pid' '?'), (Get-Field $lock.Held 'since' '?')) -ForegroundColor DarkGray }
    exit 2
}

# ------------------------------------------------------------------------------------- the loop

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$logDir = Join-Path $LogRoot $stamp
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ledgerPath = Join-Path $logDir 'ledger.txt'

function Write-Ledger {
    param([string]$Text)
    $line = if ($Text) { "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text } else { '' }
    Write-Host $line
    try { [System.IO.File]::AppendAllText($ledgerPath, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

$run = 0
$script:CommittedThisRun = 0

# An unattended tool that dies must say so where the record is, not only on a console nobody is
# watching, and must exit non-zero so a wrapper can tell a crash from a clean halt.
trap {
    Write-Ledger ''
    Write-Ledger ("supervisor CRASHED after {0} run(s): {1}" -f $run, $_.Exception.Message)
    Write-StatusLine -Run $run -Elapsed ([TimeSpan]::Zero) -Event "CRASHED: $($_.Exception.Message)" -StopPending $false
    Exit-LaneLock -LaneWorktree $laneConfig.Worktree
    exit 1
}

# The permission posture is stated every run, in the record, because it is the thing a reader most
# needs to know and the thing least visible from the outside.
$unattended = $laneConfig.Unattended
$permission = if ($unattended) { 'skipping permission prompts (lane declares unattended: true)' } else { 'prompting for permissions -- the loop will stall on the first one' }

Write-Ledger ("lane supervisor -- {0} -- started" -f $laneConfig.Name)
Write-Ledger ("  worktree: {0}" -f $laneConfig.Worktree)
Write-Ledger ("  command:  {0}" -f $laneConfig.Command)
Write-Ledger ("  agent:    {0}" -f $permission)
Write-Ledger ("  log:      {0}" -f $logDir)
Write-Ledger  '  ends when a run commits nothing, or you stop it.'
Write-Ledger ("  watch:    Run-Lane.ps1 {0} -Status -Follow" -f $laneConfig.Name)
Write-Ledger ("  stop:     Run-Lane.ps1 {0} -Stop" -f $laneConfig.Name)
if (-not $unattended -and -not $DryRun) {
    Write-Ledger '  WARNING: this lane is not marked unattended, so the agent will ask before acting and nothing is here to answer.'
}
if (Test-Path -LiteralPath $StopFile) {
    Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
    Write-Ledger '  (cleared a stop request left over from a previous loop)'
}
if ($DryRun) { Write-Ledger '  DRY RUN: one real but trivial agent call in place of the lane command; the zero-commit verdict halts it after one iteration.' }
Set-RunEnvironment
Write-Ledger ("  every run: no background tasks, foreground Bash up to {0} minutes" -f ([int]$script:RunVariables['BASH_MAX_TIMEOUT_MS'] / 60000))
Write-Ledger ''

try {
    while ($true) {
        if (Test-Path -LiteralPath $StopFile) {
            Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
            Write-Ledger ''
            Write-Ledger ("stopped on request after {0} run(s)" -f $run)
            break
        }

        $run++
        $script:CommittedThisRun = 0
        $started = Get-Date
        $transcript = Join-Path $logDir ("run-{0:d3}.jsonl" -f $run)
        Write-Ledger ("=== run {0} ===" -f $run)
        Write-StatusLine -Run $run -Elapsed ([TimeSpan]::Zero) -Event 'starting a fresh agent process' -StopPending $false

        $prompt = if ($DryRun) { 'Reply with exactly: dry run ok. Use no tools.' } else { $laneConfig.Command }
        $arguments = @('-p', $prompt, '--output-format', 'stream-json', '--verbose')
        if ($unattended) { $arguments += '--dangerously-skip-permissions' }

        Push-Location -LiteralPath $laneConfig.Worktree
        try {
            & claude @arguments 2>&1 | ForEach-Object {
                $line = [string]$_
                try { [System.IO.File]::AppendAllText($transcript, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch { }
                $rendered = Format-StreamEvent $line
                if ($rendered) {
                    Write-Ledger ("  {0}" -f $rendered)
                    Write-StatusLine -Run $run -Elapsed ((Get-Date) - $started) -Event $rendered -StopPending (Test-Path -LiteralPath $StopFile)
                }
            }
            $agentCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $script:CommittedThisRun = Get-LaneWorkCount -Path $laneConfig.Worktree -Branch $laneConfig.Branch -Since $started
        $elapsed = (Get-Date) - $started
        Write-Ledger ("--- run {0}: agent exit {1}, {2} commit(s), {3:hh\:mm\:ss}" -f $run, $agentCode, $script:CommittedThisRun, $elapsed)
        if (Test-Path -LiteralPath $transcript) {
            foreach ($k in (Get-TasksKilledAtExit -Lines (Read-LinesUtf8 $transcript))) {
                Write-Ledger ("KILLED AT EXIT: {0} -- a background task outlived the run's turn, so whatever it was verifying did not land. CLAUDE_CODE_DISABLE_BACKGROUND_TASKS is no longer preventing this; check it against this CLI version." -f $k)
            }
        }
        Write-StatusLine -Run $run -Elapsed $elapsed -Event 'run finished' -StopPending (Test-Path -LiteralPath $StopFile)

        if ($script:CommittedThisRun -eq 0) {
            Write-Ledger ''
            Write-Ledger ("halting: run {0} committed nothing. Every claim whose dependencies are built is blocked on an answer -- that is a question for the ideate command, not a reason to run again." -f $run)
            break
        }
    }
} finally {
    Exit-LaneLock -LaneWorktree $laneConfig.Worktree
}

Write-Ledger ''
Write-Ledger ("lane supervisor -- {0} -- finished after {1} run(s)" -f $laneConfig.Name, $run)
Write-StatusLine -Run $run -Elapsed ([TimeSpan]::Zero) -Event 'finished' -StopPending $false
exit 0
