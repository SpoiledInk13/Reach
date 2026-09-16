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
        branch, and every lane's -- to the remote, atomically.

        A land in `objects` mode merges from objects and touches nothing else, so without this the
        integration branch advances on one disk and nowhere else. From that disk the result is
        indistinguishable from published work, which is why this is not left to whoever remembers.

        The refs go together because a partial publish leaves exactly that state for whichever ref
        did not make it. Returns 0 published, or deliberately not published; 1 the remote refused.
    #>
    param([Parameter(Mandatory = $true)][string]$RepoRoot, $Process)

    $integration = Get-Integration $Process

    $wanted = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($integration.Branch, $integration.Primary)) {
        if ($name -and -not $wanted.Contains($name)) { $wanted.Add($name) | Out-Null }
    }
    foreach ($lane in (ConvertTo-Array (Get-Field $Process 'lanes' @()))) {
        $name = [string](Get-Field $lane 'branch' (Get-Field $lane 'name' ''))
        if ($name -and -not $wanted.Contains($name)) { $wanted.Add($name) | Out-Null }
    }

    # A lane declared in process.json but never seeded has no branch yet, and naming a ref that does
    # not exist makes git refuse the whole atomic push -- so the unseeded lane would block publication
    # for every other ref rather than for itself.
    $refs = New-Object System.Collections.Generic.List[string]
    foreach ($name in $wanted) {
        $exists = Invoke-Git -Path $RepoRoot -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$name")
        if ($exists.Code -eq 0) { $refs.Add($name) | Out-Null }
    }
    if ($refs.Count -eq 0) {
        Write-Host 'NOT PUBLISHED: process.json names no branch that exists here.' -ForegroundColor Yellow
        return 0
    }
    $named = ($refs.ToArray()) -join ', '

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

    $push = Invoke-Git -Path $RepoRoot -Arguments (@('push', '--atomic', $integration.Remote) + $refs.ToArray())
    if ($push.Code -ne 0) {
        foreach ($line in $push.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
        Write-Host ("FAILED: publishing {0} to '{1}' was refused, so the work is on this machine only. Fetch, reconcile, re-verify, and publish again. Never force." -f $named, $integration.Remote) -ForegroundColor Red
        return 1
    }
    Write-Host ("PUBLISHED: {0} -> {1}." -f $named, $integration.Remote) -ForegroundColor Green

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
