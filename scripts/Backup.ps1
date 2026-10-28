#Requires -Version 5.1
<#
.SYNOPSIS
    Mirrors a process root git never holds into documents.backup, and commits the mirror there.

.DESCRIPTION
    An overlay's documents are never committed to the repository they sit in -- they are one
    person's, and the tree is the team's -- so without this the disk they are on is their only copy,
    and nothing records how they changed. "Git history is the why-trail" has no git to be true of.

    So the backup is a mirror, and the mirror is a git repository of its own: each run copies the
    process root over it, deletes what the root no longer has, and commits the result. A document
    deleted on purpose is gone from the mirror and still in its history, which is what makes deleting
    safe here exactly as it is in a committed tree -- and `git -C <backup> log -S` is the trail.

    Point it at a folder a cloud client syncs and it leaves the machine too. It refuses a destination
    inside the repository, which would put the documents in the team's tree by another route.

    Links are not followed. An overlay may hold a junction into the team's tree, and mirroring one
    copies somebody else's files into your backup, or deletes them on a restore.

    Exit 0 backed up. 2 refused.

.PARAMETER Message
    A file holding the backup commit's message. The ideate command passes the decision it just
    settled, so the backup's log reads as the list of decisions a land's log would have been. Without
    it the message names the commit the repository is at, which is what the post-commit hook wants.

.PARAMETER Root
    The process root. Defaults to the one Resolve-RepoRoot finds.
#>
[CmdletBinding()]
param([string]$Message, [string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }

$documents = Get-Documents $Process
if (-not $documents.Backup) {
    Write-Host 'REFUSED: documents.backup names no folder.' -ForegroundColor Red
    exit 2
}

# Before anything is copied, so a refusal changes nothing.
if ($Message -and -not (Test-Path -LiteralPath $Message)) {
    Write-Host ("REFUSED: no message file at {0}." -f $Message) -ForegroundColor Red
    exit 2
}

$destination = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($documents.Backup)) { $documents.Backup } else { Join-Path $RepoRoot $documents.Backup }))

$top = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--show-toplevel')
if ($top) {
    $top = [System.IO.Path]::GetFullPath($top)
    $inside = $destination.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($inside.StartsWith($top.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("REFUSED: {0} is inside the repository, so the backup would be one more thing in the team's tree. Point documents.backup outside it." -f $destination) -ForegroundColor Red
        exit 2
    }
}

# ------------------------------------------------------------------------------------- the walk

function Get-Files {
    # Relative paths of every file under $Base, never descending through a link or into .git.
    param([string]$Base)
    $out = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Base)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($item.PSIsContainer) {
                if ($item.Name -eq '.git') { continue }
                $stack.Push($item.FullName)
            } else {
                $out.Add($item.FullName.Substring($Base.Length).TrimStart('\', '/')) | Out-Null
            }
        }
    }
    return ,$out.ToArray()
}

if (-not (Test-Path -LiteralPath $destination)) { New-Item -ItemType Directory -Path $destination -Force | Out-Null }

$source = Get-Files $RepoRoot
$kept = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($relative in $source) {
    $kept.Add($relative) | Out-Null
    $to = Join-Path $destination $relative
    $dir = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $to -Force
}

# A mirror, not an accumulation: a document the root deleted is deleted here, and the history below
# is where it is kept. Leaving it would restore a rule that was replaced.
$removed = 0
foreach ($relative in (Get-Files $destination)) {
    if ($kept.Contains($relative)) { continue }
    Remove-Item -LiteralPath (Join-Path $destination $relative) -Force
    $removed++
}

# ----------------------------------------------------------------------------------- the history

if (-not (Test-Path -LiteralPath (Join-Path $destination '.git'))) {
    Invoke-Git -Path $destination -Arguments @('init', '-q') | Out-Null
}

$name = Get-GitValue -Path $RepoRoot -Arguments @('config', 'user.name')
$email = Get-GitValue -Path $RepoRoot -Arguments @('config', 'user.email')
if (-not $name) { $name = 'reach' }
if (-not $email) { $email = 'reach@localhost' }

$branch = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
$subject = Get-GitValue -Path $RepoRoot -Arguments @('log', '-1', '--format=%h %s')
$text = ("backup at {0} {1}" -f $branch, $subject).Trim()
if ($Message) {
    $text = (Read-TextUtf8 $Message).Trim()
}

Invoke-Git -Path $destination -Arguments @('add', '-A') | Out-Null
$staged = Invoke-Git -Path $destination -Arguments @('diff', '--cached', '--quiet')
if ($staged.Code -eq 0) {
    Write-Host ("BACKED UP: {0} file(s) -> {1}, unchanged since the last backup." -f $source.Count, $destination) -ForegroundColor Green
    exit 0
}

$commit = Invoke-Git -Path $destination -Arguments @('-c', "user.name=$name", '-c', "user.email=$email", 'commit', '-q', '-m', $text)
if ($commit.Code -ne 0) {
    foreach ($line in $commit.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
    Write-Host ("WARNING: the files are mirrored to {0}, but its history did not record them." -f $destination) -ForegroundColor Yellow
    exit 0
}
Write-Host ("BACKED UP: {0} file(s), {1} removed -> {2}, committed there." -f $source.Count, $removed, $destination) -ForegroundColor Green
exit 0
