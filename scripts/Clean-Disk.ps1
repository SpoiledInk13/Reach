#Requires -Version 5.1
<#
.SYNOPSIS
    Deletes what the repository's checkouts rebuild for themselves, and warns before their disk fills.

.DESCRIPTION
    Every lane is a whole checkout with its own build cache and its own outputs, so lanes multiply
    whatever the toolchain writes, and nothing in git ever removes any of it. Measured on the project
    this was built in: one lane at 161 GB, 118 GB of it caches nobody would open again, found only when
    a write failed -- which reads as a broken build rather than a full disk.

    What may go is the repository's to say, in process.json, because only it knows which directory is
    a cache:

      "disk": {
        "warnPercent": 15,
        "regenerable": [
          { "path": "Library", "idleDays": 1 },     a cache: deleted once nothing has written to it for a day
          { "path": "Build/*", "keep": 2 }          outputs: all but the newest two in each checkout
        ]
      }

    `path` is relative to a checkout and may hold wildcards. It is swept in the primary and in every
    lane and builder reach knows; a worktree reach did not make is never swept, because it is somebody
    else's. A match is deleted only when all of these hold, and the first that fails is what is said:

      * git ignores it and tracks nothing inside it -- an entry that names source is a mistake in
        process.json, refused with exit 1, and never a deletion;
      * nothing holds its lane -- a supervisor or a session working there;
      * no running process names it, anything inside it, or exactly one of the directories between it
        and its checkout on its command line: an editor started on a project has every cache under it
        open, and one started on a sibling has none of them;
      * with `idleDays`, nothing has written to the directory itself for that long -- its own time,
        never a walk of its contents, which on a large cache costs longer than the deletion;
      * with `keep`, it is not one of the newest that many in its checkout.

    Then each volume the checkouts sit on is reported, and one under warnPercent is warned about --
    exit 1, and with -Notify in a dialog as well, which is how a scheduled run reaches someone who is
    not watching a terminal. What is left at that point is not safe to delete unattended, which is why
    it warns rather than deleting harder.

    Exit codes: 0 done and the disk is fine; 1 a volume is under the warning or an entry was refused;
    2 refused to run.

.PARAMETER Notify
    Also show the warning in a dialog (Windows). Meant for the scheduled run.

.PARAMETER Install
    Register a daily run at 09:00 with -Notify instead of sweeping: a Windows scheduled task, or on
    other platforms the crontab line to add. It runs Scripts/reach.ps1, so it follows the plugin as
    it updates. -WhatIf shows what it would register.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Root,
    [switch]$Notify,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }
$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }
$RepoRoot = Get-PrimaryRoot $RepoRoot
$windows = (-not (Test-Path variable:IsWindows)) -or $IsWindows
# Loaded before anything runs, so -WhatIf does not list the module setting its own aliases as though
# they were deletions.
if ($windows) { & { $WhatIfPreference = $false; Import-Module CimCmdlets } }

# ------------------------------------------------------------------------------------------ install

if ($Install) {
    # The shim, never this file: this file's path carries the plugin's version and moves on the next
    # update, so a schedule naming it would stop running without a word.
    $shim = Join-Path $RepoRoot 'Scripts/reach.ps1'
    if (-not (Test-Path -LiteralPath $shim)) {
        Write-Host 'REFUSED: no Scripts/reach.ps1. A schedule naming the plugin''s own path breaks on its next update -- copy templates/reach.ps1 in first.' -ForegroundColor Red
        exit 2
    }
    $project = Get-Field $Process 'project' (Split-Path -Leaf $RepoRoot)
    $name = "reach clean -- $project"
    $exe = (Get-Command (Get-PowerShellExe) -CommandType Application | Select-Object -First 1).Source
    if ($windows) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$shim`" clean -Notify"
        if ($PSCmdlet.ShouldProcess($name, "register a daily 09:00 task running $exe $arguments")) {
            $action = New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $RepoRoot
            $trigger = New-ScheduledTaskTrigger -Daily -At '09:00'
            $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
            Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
            Write-Host ("INSTALLED: '{0}' runs daily at 09:00, and on the next start after a missed one. Remove it with: Unregister-ScheduledTask -TaskName '{0}'" -f $name) -ForegroundColor Green
        }
    } else {
        Write-Host 'Add this line with `crontab -e` -- this script does not edit a crontab for you:' -ForegroundColor Cyan
        Write-Host ("0 9 * * * cd '{0}' && '{1}' -NoProfile -File '{2}' clean" -f $RepoRoot, $exe, $shim)
    }
    exit 0
}

# ------------------------------------------------------------------------------------------- sweep

$lines = New-Object System.Collections.Generic.List[string]
function Say { param([string]$Text, [string]$Colour = 'Gray') Write-Host $Text -ForegroundColor $Colour; $lines.Add($Text) | Out-Null }

$entries = ConvertTo-Array (Get-Field (Get-Field $Process 'disk' $null) 'regenerable' @())
$trees = Get-ProcessTrees -Process $Process -RepoRoot $RepoRoot
$processes = Get-ProcessCommandLines
$before = Get-TreeSpaces -Process $Process -RepoRoot $RepoRoot
$refused = 0

Say ("Clean-Disk {0:yyyy-MM-dd HH:mm} -- {1}" -f (Get-Date), $RepoRoot) 'Cyan'
if ($entries.Count -eq 0) {
    Say '  process.json declares nothing regenerable (disk.regenerable), so nothing is deleted; the disk is only reported.' 'DarkGray'
}

foreach ($tree in $trees) {
    if ($entries.Count -eq 0) { break }
    if ($tree.Lane) {
        $holder = Get-LaneHolder -LaneWorktree $tree.Path
        if ($holder) {
            Say ("  {0}: kept whole -- held by {1} (pid {2}), so something is working in it" -f $tree.Name, (Get-Field $holder 'owner' '?'), (Get-Field $holder 'pid' '?')) 'Yellow'
            continue
        }
    }
    $base = [System.IO.Path]::GetFullPath($tree.Path).TrimEnd('\', '/')

    foreach ($entry in $entries) {
        $pattern = [string](Get-Field $entry 'path' '')
        $idle = Get-Field $entry 'idleDays' $null
        $keep = Get-Field $entry 'keep' $null
        if (-not $pattern -or [System.IO.Path]::IsPathRooted($pattern) -or $pattern -match '(^|[\\/])\.\.([\\/]|$)') {
            Say ("  REFUSED entry '{0}': a regenerable path is relative to a checkout and stays inside it" -f $pattern) 'Red'
            $refused++; continue
        }
        if ($null -eq $idle -and $null -eq $keep) {
            Say ("  REFUSED entry '{0}': it says neither idleDays nor keep, so nothing says when it may go" -f $pattern) 'Red'
            $refused++; continue
        }

        $found = @(Get-Item -Path (Join-Path $base $pattern) -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $rank = 0
        foreach ($item in $found) {
            $rank++
            $full = $item.FullName.TrimEnd('\', '/')
            if (-not $full.StartsWith($base + [System.IO.Path]::DirectorySeparatorChar)) { continue }
            $relative = $full.Substring($base.Length + 1).Replace('\', '/')
            $label = "{0}: {1}" -f $tree.Name, $relative

            if ($null -ne $keep -and $rank -le [int]$keep) { Say ("  kept {0} -- one of the newest {1}" -f $label, $keep) 'DarkGray'; continue }

            # Source is never regenerable. check-ignore is the whole guard: it calls a directory not
            # ignored once anything inside it is tracked, even a file force-added under an ignore
            # pattern, and a tracked file not ignored at all. ls-files only words the refusal.
            $probe = if ($item.PSIsContainer) { "$relative/" } else { $relative }
            if ((Invoke-Git -Path $base -Arguments @('check-ignore', '-q', '--', $probe)).Code -ne 0) {
                $tracked = @((Invoke-Git -Path $base -Arguments @('ls-files', '--', $relative)).Lines | Where-Object { $_ })
                $why = if ($tracked.Count -gt 0) { "git tracks $($tracked.Count) file(s) in it" } else { 'git does not ignore it' }
                Say ("  REFUSED {0} -- {1}, so it may be source. A regenerable path must be ignored and hold nothing tracked." -f $label, $why) 'Red'
                $refused++; continue
            }

            $open = @(Find-ProcessesNaming -Path $full -Within $base -Processes $processes)
            if ($open.Count -gt 0) {
                Say ("  kept {0} -- open in {1} (pid {2})" -f $label, $open[0].Name, $open[0].Id) 'Yellow'
                continue
            }
            if ($null -ne $idle -and $item.LastWriteTime -gt (Get-Date).AddDays(-[double]$idle)) {
                Say ("  kept {0} -- written to within {1} day(s)" -f $label, $idle) 'DarkGray'
                continue
            }

            $reason = if ($null -ne $keep) { "older than the newest $keep" } else { "idle $idle day(s)" }
            if (-not $PSCmdlet.ShouldProcess($full, "delete ($reason)")) { continue }
            $gone = if ($item.PSIsContainer) { Remove-Tree -Path $full } else {
                Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
                -not (Test-Path -LiteralPath $full)
            }
            if ($gone) { Say ("  deleted {0} ({1})" -f $label, $reason) }
            else { Say ("  could not delete all of {0} -- something has a file in it open" -f $label) 'Yellow' }
        }
    }
}

# ------------------------------------------------------------------------------------------ report

$after = Get-TreeSpaces -Process $Process -RepoRoot $RepoRoot
$low = @()
foreach ($space in $after) {
    $was = @($before | Where-Object { $_.Name -eq $space.Name })
    $freed = if ($was.Count -gt 0) { ($space.Free - $was[0].Free) / 1GB } else { 0 }
    Say ("  {0}; freed {1:N1} GB" -f (Format-Space $space), [math]::Max(0, $freed)) 'Cyan'
    if ($space.Low) { $low += $space }
}
foreach ($space in $low) {
    $message = ("{0} is {1}% free ({2:N0} GB), under the {3}% warning. What is left is not safe to delete unattended: remove the lanes this machine no longer runs (lane remove), and look for what nothing declares regenerable." -f $space.Name, $space.Percent, ($space.Free / 1GB), $space.Warn)
    Say "WARNING: $message" 'Red'
    if ($Notify -and $windows -and -not $WhatIfPreference) {
        try { (New-Object -ComObject WScript.Shell).Popup($message, 0, ("{0}: disk space" -f (Get-Field $Process 'project' 'reach')), 0x30) | Out-Null } catch { }
    }
}

# A scheduled run has no terminal, so what it did is kept beside the repository's own git state, where
# no checkout commits it and every worktree finds the same file.
if (-not $WhatIfPreference) {
    $common = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($common) {
        $log = Join-Path $common 'reach-clean.log'
        $kept = if (Test-Path -LiteralPath $log) { @([System.IO.File]::ReadAllLines($log) | Select-Object -Last 2000) } else { @() }
        [System.IO.File]::WriteAllLines($log, [string[]]($kept + $lines + ''))
    }
}

if ($low.Count -gt 0 -or $refused -gt 0) { exit 1 }
exit 0
