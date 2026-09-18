<#
    Shared by every reach script. Dot-sourced, never run.

    These exist because each of them encodes a PowerShell 5.1 trap that has silently produced a wrong
    answer at least once. Reading config or text any other way in a reach script is a bug waiting for
    a quiet afternoon.
#>

function Read-TextUtf8 {
    # 5.1's Get-Content defaults to the ANSI codepage, which mojibakes em-dashes and can turn a
    # content match into a silent miss.
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-LineCount {
    param([string]$Path)
    return ([System.IO.File]::ReadAllLines($Path)).Count
}

function Get-Field {
    # ConvertFrom-Json returns a PSCustomObject and StrictMode throws on a property that is not
    # there, so every optional field is read through this.
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if (-not $Object.PSObject.Properties.Match($Name).Count) { return $Default }
    $value = $Object.$Name
    if ($null -eq $value) { return $Default }
    return $value
}

function ConvertTo-Array {
    # A single-element JSON array comes back from ConvertFrom-Json as one object, and @() around a
    # generic List throws on 5.1. Everything that iterates goes through here.
    param($Value)
    if ($null -eq $Value) { return ,@() }
    if ($Value -is [string]) { return ,@($Value) }
    if ($Value -is [System.Collections.IEnumerable]) {
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { $out.Add($item) | Out-Null }
        return ,$out.ToArray()
    }
    return ,@($Value)
}

$script:PowerShellExe = $null

function Get-PowerShellExe {
    <#
        The PowerShell this machine can actually launch a script with.

        `powershell` is Windows PowerShell and exists nowhere else, so a suite that hard-codes it
        runs on Windows and silently nowhere -- which is how both proof suites came to be Windows-only
        while the README promised "Windows PowerShell 5.1 or pwsh on any platform". For anyone not on
        Windows that made every guard in this plugin decoration, because its failure path could not
        be observed at all.

        pwsh first: where both exist it is the newer one, and the scripts are written to the 5.1
        subset so either runs them.
    #>
    if ($script:PowerShellExe) { return $script:PowerShellExe }
    foreach ($candidate in @('pwsh', 'powershell')) {
        $found = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue
        if ($found) { $script:PowerShellExe = $candidate; return $candidate }
    }
    throw 'Neither pwsh nor powershell is on PATH, so no script can be launched in a child process.'
}

function Get-PowerShellArgs {
    <#
        The launch arguments that mean the same thing on every platform.

        -ExecutionPolicy applies only on Windows, so it is passed only there rather than relying on
        the other platforms to ignore it.
    #>
    [string[]]$list = @('-NoProfile')
    if ((-not (Test-Path variable:IsWindows)) -or $IsWindows) { $list += @('-ExecutionPolicy', 'Bypass') }
    return ,$list
}

function Resolve-RepoRoot {
    param([string]$Root)
    if (-not $Root -or $Root.Trim().Length -eq 0) {
        $Root = (& git rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $Root) { return $null }
    }
    if (-not (Test-Path -LiteralPath $Root)) { return $null }
    return (Resolve-Path -LiteralPath $Root).Path
}

function Read-ProcessConfig {
    param([string]$RepoRoot)
    $path = Join-Path $RepoRoot 'process.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Read-TextUtf8 $path | ConvertFrom-Json)
}

# ------------------------------------------------------------------------------------------ git

function Invoke-Git {
    <#
        Runs git in a repository and returns its lines and exit code together.

        Never `| Select-Object -First`, and never piped through anything: a native command's exit
        code is the pipeline's last element's, so a filter turns a failure into a pass. The lines come
        back whole and the caller decides.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    # ErrorActionPreference is forced to Continue for the call itself. Under Stop, redirecting a
    # native command's stderr makes 5.1 wrap each line in an ErrorRecord and throw -- so a git command
    # that merely PRINTS to stderr, like `rev-parse --verify` on a branch that does not exist yet,
    # terminates the script instead of returning the non-zero code the caller is about to check.
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $Path @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prior
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $output) { $lines.Add([string]$line) | Out-Null }
    return [pscustomobject]@{ Code = $code; Lines = $lines.ToArray() }
}

function Get-GitValue {
    param([string]$Path, [string[]]$Arguments)
    $result = Invoke-Git -Path $Path -Arguments $Arguments
    if ($result.Code -ne 0 -or $result.Lines.Count -eq 0) { return $null }
    return $result.Lines[0].Trim()
}

function Test-SamePath {
    # Two paths to the same directory compare unequal on spelling alone -- a trailing slash, a
    # different case, a short name. Resolved and normalised, or a lane can be driven from inside
    # itself and rewrite the script running it.
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    $left  = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $A).Path).TrimEnd('\', '/')
    $right = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $B).Path).TrimEnd('\', '/')
    return [string]::Equals($left, $right, [StringComparison]::OrdinalIgnoreCase)
}

function Get-WorktreeFor {
    <#
        The working tree that has $Branch checked out, or $null.

        This is what stands between the object-merge land and a corrupted checkout: advancing a ref
        by update-ref while some worktree has it checked out leaves that worktree's index describing
        a commit that is no longer its HEAD, and the next status there reports the whole tree as
        deleted.
    #>
    param([string]$Path, [string]$Branch)
    $result = Invoke-Git -Path $Path -Arguments @('worktree', 'list', '--porcelain')
    if ($result.Code -ne 0) { return $null }

    $current = $null
    foreach ($line in $result.Lines) {
        if ($line -like 'worktree *') { $current = $line.Substring(9).Trim() }
        elseif ($line -like 'branch *') {
            $ref = $line.Substring(7).Trim()
            if ($ref -eq "refs/heads/$Branch") { return $current }
        }
    }
    return $null
}

function Get-WorktreeDirt {
    <#
        `git status --porcelain`, minus the files reach itself writes into a working tree.

        The lane lock sits at a lane's root and the supervisor's logs sit under the primary, and
        neither is tracked. Counting them as uncommitted work made `lane sync` refuse a lane while a
        supervisor was running in it, and made `lane sync -Primary` refuse in any checkout that had
        ever run one -- which is the command PrimaryIsStale prints when it blocks the gate. A guard
        whose only remedy is unreachable does not protect anything; it just stops work.

        Filtered here rather than left to the project's .gitignore, because a repository that adopted
        reach before those lines existed still has to work.

        -uall because git collapses a wholly untracked directory to one entry -- `Logs/` rather than
        the files under it -- and a filter on the reach path would never see it. Listing every file
        is what makes the filter exact, and it is what leaves anything else in Logs/ still reported.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = Invoke-Git -Path $Path -Arguments @('status', '--porcelain', '-uall')
    $kept = New-Object System.Collections.Generic.List[string]
    if ($result.Code -eq 0) {
        foreach ($line in $result.Lines) {
            if (-not $line -or $line.Length -lt 4) { continue }

            # Two status columns, a space, then the path. A rename prints "old -> new", and the new
            # name is the one that says where the file is now.
            $file = $line.Substring(3).Trim()
            $arrow = $file.IndexOf(' -> ')
            if ($arrow -ge 0) { $file = $file.Substring($arrow + 4) }
            $file = $file.Trim('"').Replace('\', '/').TrimEnd('/')

            if ($file -eq '.reach-lane-lock') { continue }
            if ($file -eq 'Logs/reach-lane' -or $file.StartsWith('Logs/reach-lane/')) { continue }
            $kept.Add($line) | Out-Null
        }
    }
    return [pscustomobject]@{ Code = $result.Code; Lines = $kept.ToArray() }
}

function Get-LaneWorkCount {
    <#
        How many commits the lane itself wrote since $Since, from the reflog. Only the lane writes
        that ref, so `commit` entries are its work and nothing else's -- a fast-forward or a merge
        arriving from elsewhere has a different subject and is not counted.

        $Since is truncated to a whole second: reflog timestamps carry seconds and Get-Date carries
        ticks, so a commit written in the same second the run started would otherwise read as older
        than the run and go uncounted -- turning a short successful run into a false halt.

        Lives here rather than beside its one caller because the supervisor only reaches it after a
        real agent run, and a guard that cannot be exercised is the decoration this plugin condemns.
    #>
    param([string]$Path, [string]$Branch, [datetime]$Since)

    $result = Invoke-Git -Path $Path -Arguments @('reflog', "refs/heads/$Branch", '--format=%H|%cI|%gs')
    if ($result.Code -ne 0 -or $result.Lines.Count -eq 0) {
        # An empty reflog used to be read as "reflogs are off here", on the grounds that `git branch`
        # writes an entry of its own. That inference expires. gc.reflogExpire drops entries after 90
        # days, and a clone writes no reflog for a branch it never checked out -- so a lane resumed
        # after a long pause, on a healthy branch with logging on, was told to turn on a setting that
        # was already on. Ask about each cause instead of inferring one.
        $exists = Invoke-Git -Path $Path -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$Branch")
        if ($exists.Code -ne 0) {
            throw "refs/heads/$Branch does not exist, so there is no lane branch to count work on."
        }

        $logging = Get-GitValue -Path $Path -Arguments @('config', '--get', 'core.logAllRefUpdates')
        if ($logging -and $logging.Trim().ToLowerInvariant() -eq 'false') {
            throw "refs/heads/$Branch has no reflog, and core.logAllRefUpdates is false here. It must be on for a lane's work to be counted."
        }

        # The branch is there and logging is on, so the reflog is empty because its entries were
        # expired or never cloned -- not because work cannot be counted. Anything this run commits
        # writes an entry seconds old, which no expiry reaches, so counting from zero is honest.
        return 0
    }

    $floor = [datetimeoffset]$Since.AddTicks( - ($Since.Ticks % [timespan]::TicksPerSecond))
    $count = 0
    foreach ($line in $result.Lines) {
        $parts = $line -split '\|', 3
        if ($parts.Count -lt 3) { continue }
        if ($parts[2] -notmatch '^commit') { continue }
        $when = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse($parts[1], [ref]$when)) { continue }
        if ($when -lt $floor) { continue }
        $count++
    }
    return $count
}

# ----------------------------------------------------------------------------------------- lanes

function Get-LaneConfig {
    <#
        One lane by name, with its paths resolved against the repository. A lane's worktree is
        written relative to the repository root in process.json so the file stays portable between
        machines and checkouts.
    #>
    param($Process, [string]$RepoRoot, [string]$Name)
    foreach ($lane in (ConvertTo-Array (Get-Field $Process 'lanes' @()))) {
        if ((Get-Field $lane 'name' '') -ne $Name) { continue }

        $relative = Get-Field $lane 'worktree' ("../" + (Split-Path -Leaf $RepoRoot) + "-lanes/$Name")
        $full = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $relative))
        return [pscustomobject]@{
            Name      = $Name
            Branch    = Get-Field $lane 'branch' $Name
            Worktree  = $full
            Command   = Get-Field $lane 'command' ''
            Warm      = Get-Field $lane 'warm' $null
            Unattended = [bool](Get-Field $lane 'unattended' $false)
        }
    }
    return $null
}

function Get-LaneNames {
    param($Process)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($lane in (ConvertTo-Array (Get-Field $Process 'lanes' @()))) {
        $name = Get-Field $lane 'name' ''
        if ($name) { $names.Add($name) | Out-Null }
    }
    # Comma-wrapped: a one-element array returned from a function is unwrapped to the element, and
    # .Count on a scalar string throws under StrictMode. A project with exactly one lane is the
    # common case, so this is the path that breaks first.
    return ,$names.ToArray()
}

function Get-Integration {
    param($Process)
    $integration = Get-Field $Process 'integration'
    return [pscustomobject]@{
        Branch  = Get-Field $integration 'branch'  'develop'
        Primary = Get-Field $integration 'primary' 'working'
        Mode    = Get-Field $integration 'mode'    'objects'
        Remote  = Get-Field $integration 'remote'  'origin'

        # Publishing is on unless a project turns it off, because the alternative default is a
        # repository that looks landed from the one disk that holds it. `publishAll` is off because a
        # branch carrying no part of the process may be somebody's half-finished experiment.
        Publish    = [bool](Get-Field $integration 'publish'    $true)
        PublishAll = [bool](Get-Field $integration 'publishAll' $false)
    }
}

function Invoke-ReachPublish {
    <#
        Pushes the refs that carry the process -- the integration branch, the primary checkout's
        branch, and every lane's -- to the remote.

        A land in `objects` mode merges from objects and touches nothing else, so without this the
        integration branch advances on one disk and nowhere else. From that disk the result is
        indistinguishable from published work, which is why this is not left to whoever remembers.

        In TWO pushes, and that is the whole point. They used to go as one --atomic push, which meant
        any one diverged ref refused all of them: an abandoned lane branch blocked publication of the
        integration branch, and Publish.ps1 then recomputed the same doomed list forever. The
        argument above is about the integration branch and only the integration branch; a lane's
        branch and the primary's are working state nobody else reads, and their failing is not a
        reason to call a good land unfinished. The same lesson is already written into the unseeded
        lane filter below, and into publishAll's best-effort note.

        So: the integration branch alone decides the exit code -- 0 published, or deliberately not
        published; 1 the remote refused it. The rest are pushed together and warn.
    #>
    param([Parameter(Mandatory = $true)][string]$RepoRoot, $Process)

    $integration = Get-Integration $Process

    # A lane declared in process.json but never seeded has no branch yet, and naming a ref that does
    # not exist makes git refuse the whole push -- so the unseeded lane would block publication for
    # every other ref rather than for itself.
    $onDisk = {
        param([string]$Name)
        if (-not $Name) { return $false }
        return (Invoke-Git -Path $RepoRoot -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$Name")).Code -eq 0
    }

    $shared = ''
    if (& $onDisk $integration.Branch) { $shared = $integration.Branch }

    $mine = New-Object System.Collections.Generic.List[string]
    $wanted = New-Object System.Collections.Generic.List[string]
    if ($integration.Primary) { $wanted.Add([string]$integration.Primary) | Out-Null }
    foreach ($lane in (ConvertTo-Array (Get-Field $Process 'lanes' @()))) {
        $name = [string](Get-Field $lane 'branch' (Get-Field $lane 'name' ''))
        if ($name) { $wanted.Add($name) | Out-Null }
    }
    foreach ($name in $wanted) {
        if ($name -eq $integration.Branch) { continue }
        if ($mine.Contains($name)) { continue }
        if (& $onDisk $name) { $mine.Add($name) | Out-Null }
    }

    if (-not $shared -and $mine.Count -eq 0) {
        Write-Host 'NOT PUBLISHED: process.json names no branch that exists here.' -ForegroundColor Yellow
        return 0
    }

    # A repository with no remote is a legitimate local-only one rather than a misconfiguration, so
    # the land stands -- but it says so out loud, because "nothing was published" and "everything was
    # published" must never read the same from here.
    $remotes = Invoke-Git -Path $RepoRoot -Arguments @('remote')
    $known = @()
    if ($remotes.Code -eq 0) { $known = @($remotes.Lines | ForEach-Object { $_.Trim() }) }
    if ($known -notcontains $integration.Remote) {
        Write-Host ("NOT PUBLISHED: no remote '{0}' here, so this stays local." -f $integration.Remote) -ForegroundColor Yellow
        return 0
    }

    $code = 0

    if ($shared) {
        $push = Invoke-Git -Path $RepoRoot -Arguments @('push', $integration.Remote, $shared)
        if ($push.Code -ne 0) {
            foreach ($line in $push.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
            Write-Host ("FAILED: publishing {0} to '{1}' was refused, so the work is on this machine only. Fetch, reconcile, re-verify, and publish again. Never force." -f $shared, $integration.Remote) -ForegroundColor Red
            $code = 1
        }
        else {
            Write-Host ("PUBLISHED: {0} -> {1}." -f $shared, $integration.Remote) -ForegroundColor Green
        }
    }

    if ($mine.Count -gt 0) {
        $named = ($mine.ToArray()) -join ', '
        $push = Invoke-Git -Path $RepoRoot -Arguments (@('push', '--atomic', $integration.Remote) + $mine.ToArray())
        if ($push.Code -ne 0) {
            foreach ($line in $push.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
            Write-Host ("WARNING: {0} did not publish to '{1}'. That is your own working state, not the process, so the land stands -- but this machine is the only copy of it." -f $named, $integration.Remote) -ForegroundColor Yellow
        }
        else {
            Write-Host ("PUBLISHED: {0} -> {1}." -f $named, $integration.Remote) -ForegroundColor Green
        }
    }

    if ($code -ne 0) { return $code }

    if ($integration.PublishAll) {
        # Best effort by design: a pre-adoption dead end that has diverged is not a reason to call a
        # good land failed.
        $all = Invoke-Git -Path $RepoRoot -Arguments @('push', $integration.Remote, '--all')
        if ($all.Code -ne 0) {
            Write-Host 'WARNING: some other local branch did not publish. The refs that carry the process did.' -ForegroundColor Yellow
        }
    }
    return 0
}

# ------------------------------------------------------------------------------------- the lock

function Get-LockPath {
    param([string]$LaneWorktree)
    return (Join-Path $LaneWorktree '.reach-lane-lock')
}

function Enter-LaneLock {
    <#
        One agent per lane. Two sharing one share its index and its build cache, which is the
        collision lanes exist to remove.

        Created with CreateNew so the test and the claim are one operation -- checking for the file
        and then writing it lets two starts a millisecond apart both pass. A lock whose process is
        gone is stale and is taken over, because the alternative is a crashed run blocking the lane
        until somebody notices.
    #>
    param([string]$LaneWorktree, [string]$Owner)
    $path = Get-LockPath $LaneWorktree

    if (Test-Path -LiteralPath $path) {
        $held = $null
        try { $held = Read-TextUtf8 $path | ConvertFrom-Json } catch { $held = $null }
        $pidHeld = if ($held) { [int](Get-Field $held 'pid' 0) } else { 0 }
        $alive = $false
        if ($pidHeld -gt 0) {
            $alive = $null -ne (Get-Process -Id $pidHeld -ErrorAction SilentlyContinue)
        }
        if ($alive) {
            return [pscustomobject]@{ Ok = $false; Held = $held; Path = $path }
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    try {
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        $payload = (@{ pid = $PID; owner = $Owner; since = (Get-Date).ToString('o') } | ConvertTo-Json -Compress)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    } catch {
        return [pscustomobject]@{ Ok = $false; Held = $null; Path = $path }
    }
    return [pscustomobject]@{ Ok = $true; Held = $null; Path = $path }
}

function Exit-LaneLock {
    param([string]$LaneWorktree)
    $path = Get-LockPath $LaneWorktree
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}
