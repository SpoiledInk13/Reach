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
        # An integrator merging a builder's ready tip is its work too: a run that only integrates
        # writes no `commit` entry, and reading it as idle halts the lane that lands the builders.
        # A sync of the integration branch is a merge as well, and is never counted.
        if ($parts[2] -notmatch '^commit' -and $parts[2] -notmatch '^merge refs/ready/') { continue }
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
        One lane by name, with its paths resolved against the primary checkout. A lane's worktree is
        written relative to the primary in process.json so the file stays portable between machines
        and checkouts.

        A lane that declares `builders` also answers for `<name>-1`, `<name>-2`, ...: its BUILDER
        lanes, derived rather than listed, because how many there are is how many the owner seeded.
        A builder runs the lane's command with `builder` after it, on a branch and worktree of its
        own, and it is not warmed with the lane's harness unless `builders.warm` says otherwise --
        the scarce verifier is the reason one lane integrates and the rest only build.
    #>
    param($Process, [string]$RepoRoot, [string]$Name)
    # Every lane path is the primary's, whichever worktree asks: resolved against the checkout running
    # the verb, `../<repo>-lanes/<name>` from inside a lane lands one level too deep and every lane
    # reads not seeded -- which is where a builder runs its own sync.
    $RepoRoot = Get-PrimaryRoot $RepoRoot
    $lanes = ConvertTo-Array (Get-Field $Process 'lanes' @())
    foreach ($lane in $lanes) {
        if ((Get-Field $lane 'name' '') -ne $Name) { continue }
        return (New-LaneConfig -Lane $lane -RepoRoot $RepoRoot -Name $Name)
    }
    if ($Name -notmatch '^(?<base>.+)-(?<n>[1-9][0-9]*)$') { return $null }
    $base = $Matches['base']
    $n = [int]$Matches['n']
    foreach ($lane in $lanes) {
        if ((Get-Field $lane 'name' '') -ne $base) { continue }
        $builders = Get-Field $lane 'builders' $null
        if (-not $builders) { return $null }
        $integrator = New-LaneConfig -Lane $lane -RepoRoot $RepoRoot -Name $base
        $pattern = Get-Field $builders 'worktree' $null
        $worktree = if ($pattern) {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ($pattern -replace '\{n\}', [string]$n)))
        } else {
            "$($integrator.Worktree)-$n"
        }
        $command = ''
        if ($integrator.Command) { $command = "$($integrator.Command) builder" }
        return [pscustomobject]@{
            Name        = $Name
            Branch      = "$($integrator.Branch)-$n"
            Worktree    = $worktree
            Command     = $command
            Warm        = Get-Field $builders 'warm' $null
            Unattended  = $integrator.Unattended
            Builder     = $n
            Integrator  = $base
            HasBuilders = $false
        }
    }
    return $null
}

$script:PrimaryRoots = @{}

function Get-PrimaryRoot {
    <#
        The main worktree, from any worktree of the repository: the first entry `git worktree list`
        prints, which is the main one by git's own contract. The parent of `--git-common-dir` is not,
        under `--separate-git-dir` or in a submodule. Asked once per checkout, because a status reads
        every lane and each lookup would otherwise pay a git call for the same answer.
    #>
    param([string]$RepoRoot)
    if ($script:PrimaryRoots.ContainsKey($RepoRoot)) { return $script:PrimaryRoots[$RepoRoot] }
    $primary = $RepoRoot
    $result = Invoke-Git -Path $RepoRoot -Arguments @('worktree', 'list', '--porcelain')
    if ($result.Code -eq 0) {
        foreach ($line in $result.Lines) {
            if ($line -like 'worktree *') { $primary = [System.IO.Path]::GetFullPath($line.Substring(9).Trim()); break }
        }
    }
    $script:PrimaryRoots[$RepoRoot] = $primary
    return $primary
}

function New-LaneConfig {
    param($Lane, [string]$RepoRoot, [string]$Name)
    $relative = Get-Field $Lane 'worktree' ("../" + (Split-Path -Leaf $RepoRoot) + "-lanes/$Name")
    return [pscustomobject]@{
        Name        = $Name
        Branch      = Get-Field $Lane 'branch' $Name
        Worktree    = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $relative))
        Command     = Get-Field $Lane 'command' ''
        Warm        = Get-Field $Lane 'warm' $null
        Unattended  = [bool](Get-Field $Lane 'unattended' $false)
        Builder     = 0
        Integrator  = $Name
        HasBuilders = [bool](Get-Field $Lane 'builders' $null)
    }
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

# -------------------------------------------------------------------------------------- builders
#
# A lane declaring `builders` runs as one INTEGRATOR -- the only lane holding the scarce verifier,
# and the only one that lands -- and any number of BUILDERS, which prove every tier that needs no
# such harness and mark the tip they proved ready. Three facts pass between them, kept under the
# shared git directory so every worktree reads the same ones and none is ever committed:
#
#   a claim      one builder or integrator per unit, taken atomically before writing in it
#   ready        refs/ready/<builder>, the tip a builder proved and wants landed
#   a rejection  the integrator sending a ready tip back, keyed by the tip, so the next ready tip
#                supersedes it

function Get-BuilderLanes {
    # The builder lanes of one integrator that are seeded: a branch `<branch>-<n>` with its worktree.
    param($Process, [string]$RepoRoot, [string]$Name)
    $integrator = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $Name
    if (-not $integrator -or -not $integrator.HasBuilders) { return }
    $refs = Invoke-Git -Path $RepoRoot -Arguments @('for-each-ref', '--format=%(refname:strip=2)', "refs/heads/$($integrator.Branch)-*")
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($ref in $refs.Lines) {
        if ($ref -notmatch ('^' + [regex]::Escape($integrator.Branch) + '-([1-9][0-9]*)$')) { continue }
        $builder = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name "$Name-$($Matches[1])"
        if ($builder -and (Test-Path -LiteralPath $builder.Worktree)) { $found.Add($builder) | Out-Null }
    }
    # Each item on its own: callers wrap this in @(), which a comma-wrapped array would nest.
    $sorted = @($found.ToArray() | Sort-Object Builder)
    return $sorted
}

function Get-LaneOfBranch {
    # Which lane a branch is -- a declared lane, or a builder of one -- or nothing.
    param($Process, [string]$RepoRoot, [string]$Branch)
    if (-not $Branch) { return $null }
    foreach ($lane in (ConvertTo-Array (Get-Field $Process 'lanes' @()))) {
        $name = Get-Field $lane 'name' ''
        $config = Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name $name
        if (-not $config) { continue }
        if ($config.Branch -eq $Branch) { return $config }
        if ($config.HasBuilders -and $Branch -match ('^' + [regex]::Escape($config.Branch) + '-([1-9][0-9]*)$')) {
            return (Get-LaneConfig -Process $Process -RepoRoot $RepoRoot -Name "$name-$($Matches[1])")
        }
    }
    return $null
}

function Get-BuilderStateDir {
    param([string]$RepoRoot)
    $common = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--path-format=absolute', '--git-common-dir')
    if (-not $common) { throw "'$RepoRoot' is not a git checkout" }
    $dir = Join-Path $common 'reach-builders'
    foreach ($d in @($dir, (Join-Path $dir 'claims'), (Join-Path $dir 'rejected'))) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
    return $dir
}

function Read-BuilderRecord {
    # Two lines: who (or which tip), then when (or why).
    param([string]$Path)
    $lines = @((Read-TextUtf8 $Path) -split "`r?`n" | Where-Object { $_ -ne '' })
    $first = ''; $rest = ''
    if ($lines.Count -gt 0) { $first = $lines[0].Trim() }
    if ($lines.Count -gt 1) { $rest = ($lines[1..($lines.Count - 1)] -join ' ').Trim() }
    return [pscustomobject]@{ First = $first; Rest = $rest }
}

function Get-ReadyTip {
    param([string]$RepoRoot, [string]$Name)
    return (Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--verify', '--quiet', "refs/ready/$Name"))
}

function Get-RejectionOf {
    # A rejection stands only while the ready tip is the one it names.
    param([string]$RepoRoot, [string]$StateDir, [string]$Name)
    $path = Join-Path $StateDir "rejected/$Name"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $record = Read-BuilderRecord $path
    if ($record.First -ne (Get-ReadyTip -RepoRoot $RepoRoot -Name $Name)) { return $null }
    return $record
}

function Get-PendingTips {
    # What the integrator has to merge: a ready tip not already on integration and not sent back.
    param([string]$RepoRoot, [string]$StateDir, [string]$IntegrationBranch)
    $refs = Invoke-Git -Path $RepoRoot -Arguments @('for-each-ref', '--format=%(refname:strip=2) %(objectname) %(subject)', 'refs/ready/')
    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($line in $refs.Lines) {
        if (-not $line) { continue }
        $name, $sha, $subject = $line -split ' ', 3
        $landed = (Invoke-Git -Path $RepoRoot -Arguments @('merge-base', '--is-ancestor', $sha, $IntegrationBranch)).Code -eq 0
        if ($landed) { continue }
        if ($null -ne (Get-RejectionOf -RepoRoot $RepoRoot -StateDir $StateDir -Name $name)) { continue }
        $pending.Add([pscustomobject]@{ Lane = $name; Sha = $sha; Subject = $subject }) | Out-Null
    }
    return $pending.ToArray()
}

function Get-TipState {
    # One word for the supervisor's waits: none, pending or rejected.
    param([string]$RepoRoot, [string]$StateDir, [string]$IntegrationBranch, [string]$Name)
    if ($null -ne (Get-RejectionOf -RepoRoot $RepoRoot -StateDir $StateDir -Name $Name)) { return 'rejected' }
    foreach ($tip in (Get-PendingTips -RepoRoot $RepoRoot -StateDir $StateDir -IntegrationBranch $IntegrationBranch)) {
        if ($tip.Lane -eq $Name) { return 'pending' }
    }
    return 'none'
}

function Get-CueVerdict {
    <#
        What a run that committed nothing means once an integrator and its builders run side by side,
        which is not always a blocked backlog:

          idle     the integrator has nothing of its own, but a builder is still running or a ready
                   tip is waiting: it waits for one rather than halting
          waiting  a builder whose ready tip is with the integrator: nothing to do until that tip
                   lands or comes back
          halt     nothing to wait for -- the answer that was the only answer before builders

        A builder whose tip was ALREADY sent back when its run ended had its chance to fix it and did
        not, so it halts rather than looping on the same refusal.
    #>
    param([int]$Builder, [int]$LiveBuilders, [int]$Pending, [string]$TipState)
    if ($Builder -le 0) {
        if ($LiveBuilders -gt 0 -or $Pending -gt 0) { return 'idle' }
        return 'halt'
    }
    if ($TipState -eq 'pending') { return 'waiting' }
    return 'halt'
}

function Get-LiveBuilders {
    # The builders of an integrator whose lane something holds: a supervisor or a session.
    param($Process, [string]$RepoRoot, [string]$Name)
    $live = New-Object System.Collections.Generic.List[string]
    foreach ($builder in (Get-BuilderLanes -Process $Process -RepoRoot $RepoRoot -Name $Name)) {
        if (Get-LaneHolder -LaneWorktree $builder.Worktree) { $live.Add($builder.Name) | Out-Null }
    }
    return $live.ToArray()
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

function Get-ProcessInfo {
    # A process's parent, name and command line, or nothing when it is gone. Windows answers from
    # Win32_Process, because Get-Process carries no parent or command line on 5.1; elsewhere `ps`
    # answers on Linux and macOS alike, where /proc exists on only one of them.
    param([int]$Id)
    if ($Id -le 0) { return $null }
    if ((-not (Test-Path variable:IsWindows)) -or $IsWindows) {
        try { $w = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$Id" -ErrorAction Stop } catch { return $null }
        if (-not $w) { return $null }
        return [pscustomobject]@{ Id = [int]$w.ProcessId; Parent = [int]$w.ParentProcessId; Name = [string]$w.Name; Command = [string]$w.CommandLine }
    }
    $parent = (@(& ps -o 'ppid=' -p $Id 2>$null) -join '').Trim()
    if (-not $parent) { return $null }
    $name = Split-Path -Leaf ((@(& ps -o 'comm=' -p $Id 2>$null) -join '').Trim())
    $command = (@(& ps -o 'args=' -p $Id 2>$null) -join ' ').Trim()
    return [pscustomobject]@{ Id = $Id; Parent = [int]$parent; Name = $name; Command = $command }
}

function Test-AgentProcess {
    # Claude Code's own process: the native binary, or node running the npm package.
    param($Info)
    if (-not $Info) { return $false }
    if ($Info.Name -match '^claude(\.exe)?$') { return $true }
    return ($Info.Name -match '^node(\.exe)?$' -and $Info.Command -match 'claude')
}

function Get-AgentProcessId {
    <#
        The agent session this script was run from: the nearest ancestor that is the agent itself.

        A lane claimed by a session has to be held by a process that lives as long as the session,
        and the shell that runs this script exits a moment after it -- a lock naming it would be stale
        before the agent read the reply. The agent's tool calls are its descendants, so the walk up
        finds it, through however many shells sit between. The nearest one, because a run the
        supervisor started is an agent under a supervisor, and the run is the session.

        REACH_AGENT_PID names it instead, for an agent this walk does not recognise and for a test
        standing one in. It must name a live process; anything else is no agent at all, and 0 comes
        back rather than a guess.
    #>
    $override = [Environment]::GetEnvironmentVariable('REACH_AGENT_PID')
    if ($override) {
        $named = 0
        if ([int]::TryParse($override, [ref]$named) -and $named -gt 0 -and (Get-Process -Id $named -ErrorAction SilentlyContinue)) { return $named }
        return 0
    }
    $info = Get-ProcessInfo $PID
    for ($depth = 0; $info -and $depth -lt 32; $depth++) {
        $info = Get-ProcessInfo $info.Parent
        if (Test-AgentProcess $info) { return $info.Id }
    }
    return 0
}

function Test-ProcessAncestor {
    # Whether that process is above this one: the supervisor is above the run it started.
    param([int]$Id)
    $info = Get-ProcessInfo $PID
    for ($depth = 0; $info -and $depth -lt 32; $depth++) {
        if ($info.Parent -eq $Id) { return $true }
        $info = Get-ProcessInfo $info.Parent
    }
    return $false
}

function Test-SessionClaim {
    <#
        Whether a lock is this session's own claim: taken by `lane claim`, for the agent this runs
        under. The owner is read as well as the pid because the lock already says who took it, and a
        supervisor's lock is never released by the run beneath it however the pids fall.
    #>
    param($Holder)
    if (-not $Holder -or (Get-Field $Holder 'owner' '') -ne 'session') { return $false }
    $agent = Get-AgentProcessId
    return ($agent -gt 0 -and [int](Get-Field $Holder 'pid' 0) -eq $agent)
}

function Get-LaneHolder {
    <#
        Who holds the lane, read from its lock: the lock's record when its process is alive, and
        nothing when there is no lock or its process is gone. That is the whole answer to "is
        something running in this lane?" -- a status file's age answers a different question, how
        long since the agent last said anything, and one long tool call makes the two disagree.
    #>
    param([string]$LaneWorktree)
    $path = Get-LockPath $LaneWorktree
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $held = $null
    try { $held = Read-TextUtf8 $path | ConvertFrom-Json } catch { return $null }
    $pidHeld = [int](Get-Field $held 'pid' 0)
    if ($pidHeld -le 0) { return $null }
    if ($null -eq (Get-Process -Id $pidHeld -ErrorAction SilentlyContinue)) { return $null }
    return $held
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
    param([string]$LaneWorktree, [string]$Owner, [int]$HolderPid = $PID)
    $path = Get-LockPath $LaneWorktree

    if (Test-Path -LiteralPath $path) {
        $held = Get-LaneHolder -LaneWorktree $LaneWorktree
        if ($held) {
            return [pscustomobject]@{ Ok = $false; Held = $held; Path = $path }
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    try {
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        $payload = (@{ pid = $HolderPid; owner = $Owner; since = (Get-Date).ToString('o') } | ConvertTo-Json -Compress)
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
