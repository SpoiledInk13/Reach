#Requires -Version 5.1
<#
.SYNOPSIS
    Reports what the inbox cannot: cap headroom, owed rows, and where a unit's state disagrees with
    what is actually proven.

.DESCRIPTION
    Ideate opens by greping for `**Open:**` and `**Not working:**` lines, which is everything another
    command knew it was asking. A gap nobody filed a question about is invisible to that, and the ones
    that cost most are exactly the ones nobody can file: a document at its cap cannot be written in, so
    the command needing the room stops rather than asks.

    Measured on one project in a single sitting, none of it in any inbox. The spine was at its cap and a
    unit document at its own, and the two deadlocked: the remedy for a unit at its cap is to split it,
    a split costs a roster row, and the roster was in the document that was also full. A third document
    -- the only inbox one lane had -- sat at exactly its cap for nine consecutive lands, so that lane
    could not file the question that would have said so. The gate passes a document sitting exactly on
    its cap and no check looks at headroom, so nothing reported any of it.

    The state column understates too. Five units reading `unbuilt` were 82% proven or better, two of
    them at 100%, held back by a `**Contract:**` still owing a read rather than by any code. Reading the
    roster as the backlog gets that exactly backwards.

    So it is measured rather than remembered. Nothing here fails: these are gaps to report to the owner,
    not rules to enforce, and which of them is worth acting on is a conversation.

    Exit 0 when it measured, 1 when there is no process.json, 2 when it could not look.

.PARAMETER Root
    The repository. Defaults to the git root of the current directory.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) {
    Write-Host 'NOT ADOPTED: there is no process.json here. Run /reach:adopt.' -ForegroundColor Yellow
    exit 1
}

$problems = New-Object System.Collections.Generic.List[string]
function Add-Problem { param([string]$Message) $problems.Add($Message) | Out-Null }

$unit     = Get-Field $Process 'unit'
$unitNoun = Get-Field $unit 'noun' 'unit'
$unitDir  = Get-Field $unit 'dir' 'Docs/systems'
$unitPath = Join-Path $RepoRoot $unitDir

Write-Host ""
Write-Host "Measure-Gaps -- what no inbox reports" -ForegroundColor Cyan

# ------------------------------------------------------------------------------------ cap headroom

# Every cap is declared in process.json, so they are read from there rather than restated: a second
# copy is the thing that goes stale while both look right.
$rows = New-Object System.Collections.Generic.List[object]
function Add-Doc {
    param([string]$Relative, [int]$Cap)
    if (-not $Relative) { return }
    $path = Join-Path $RepoRoot $Relative
    if (-not (Test-Path -LiteralPath $path)) { return }
    $lines = Get-LineCount $path
    $rows.Add([pscustomobject]@{ Doc = $Relative; Lines = $lines; Cap = $Cap; Free = $Cap - $lines }) | Out-Null
}

foreach ($key in @('spine', 'roster')) {
    $node = Get-Field $Process $key $null
    if ($node) { Add-Doc (Get-Field $node 'path' '') ([int](Get-Field $node 'cap' 0)) }
}
$human = Get-Field $Process 'human' $null
if ($human) { Add-Doc (Get-Field $human 'doc' '') 0 }

$caps = Get-Field $Process 'caps' $null
if ($caps) {
    foreach ($property in $caps.PSObject.Properties) { Add-Doc $property.Name ([int]$property.Value) }
}

$unitCap = [int](Get-Field $unit 'cap' 0)
if (Test-Path -LiteralPath $unitPath) {
    foreach ($doc in (Get-ChildItem -LiteralPath $unitPath -Filter *.md -File)) {
        Add-Doc ("{0}/{1}" -f $unitDir, $doc.Name) $unitCap
    }
}

if ($rows.Count -eq 0) {
    Add-Problem "No capped document was measured. Either process.json points at paths that do not exist, or the documents moved -- this reporting nothing is not the same as nothing being tight."
} else {
    Write-Host ""
    Write-Host "Cap headroom, tightest first" -ForegroundColor White
    # A cap of 0 is the template's placeholder rather than a ceiling, so it is named as unset instead
    # of reported as the tightest document in the repository.
    foreach ($r in @($rows.ToArray() | Sort-Object Free | Select-Object -First 8)) {
        if ($r.Cap -le 0) {
            Write-Host ("  {0,-42} {1,4}/ --   no cap set" -f $r.Doc, $r.Lines) -ForegroundColor Yellow
            continue
        }
        $colour = if ($r.Free -le 0) { 'Red' } elseif ($r.Free -le 15) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-42} {1,4}/{2,-4} free {3,4}" -f $r.Doc, $r.Lines, $r.Cap, $r.Free) -ForegroundColor $colour
    }
    $full = @($rows.ToArray() | Where-Object { $_.Cap -gt 0 -and $_.Free -le 0 })
    if ($full.Count -gt 0) {
        Write-Host ("  -> {0} document(s) at or over cap: nothing can be written in one, including an Open: line." -f $full.Count) -ForegroundColor Red
    }
}

# ------------------------------------------------------------------------------------ proof vs state

$evidence = Get-Field $Process 'evidence'
$evNoun   = Get-Field $evidence 'noun' 'scenario'
$mark     = Get-Field $evidence 'mark' ('// {0}:' -f $evNoun)

$proven = New-Object System.Collections.Generic.HashSet[string]
$pattern = '(?m)^\s*' + [regex]::Escape($mark) + '\s*([a-z0-9][a-z0-9-]*)\s*$'
foreach ($dir in (ConvertTo-Array (Get-Field $evidence 'search' @('Tests')))) {
    $searchDir = Join-Path $RepoRoot $dir
    if (-not (Test-Path -LiteralPath $searchDir)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $searchDir -Recurse -File)) {
        if ($file.Length -gt 2MB) { continue }
        foreach ($m in [regex]::Matches((Read-TextUtf8 $file.FullName), $pattern)) {
            $proven.Add($m.Groups[1].Value) | Out-Null
        }
    }
}
$evidenceFiles = Get-Field $evidence 'files' $null
if ($evidenceFiles) {
    $filesDir = Join-Path $RepoRoot $evidenceFiles
    if (Test-Path -LiteralPath $filesDir) {
        foreach ($file in (Get-ChildItem -LiteralPath $filesDir -File)) { $proven.Add($file.BaseName) | Out-Null }
    }
}

if ($proven.Count -eq 0) {
    Add-Problem "No evidence mark was found anywhere under the searched directories. Every $unitNoun below would read as 0% proven, which is a broken scan rather than a repository with nothing proven."
}

$units = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $unitPath) {
    foreach ($doc in (Get-ChildItem -LiteralPath $unitPath -Filter *.md -File)) {
        $text = Read-TextUtf8 $doc.FullName

        $state = 'unknown'
        $m = [regex]::Match($text, '(?m)^\*\*State:\*\*\s*([a-z]+)')
        if ($m.Success) { $state = $m.Groups[1].Value }

        # The declaration wraps like any other header line, so it is read to the next field or the
        # blank line that ends the block.
        $contract = 'whole'
        $m = [regex]::Match($text, '(?ms)^\*\*Contract:\*\*[ ]*(.*?)(?=^\*\*|^\r?$)')
        if ($m.Success) {
            $flat = ($m.Groups[1].Value -replace '\s+', ' ').Trim()
            if ($flat -match '^(none|partial)') { $contract = $Matches[1] }
        }

        # An evidence row's first cell is its name. At least one hyphen, because other tables in these
        # documents put a single backticked word -- a field, a table -- in that same position.
        $names = New-Object System.Collections.Generic.HashSet[string]
        foreach ($r in [regex]::Matches($text, '(?m)^\|\s*`([a-z][a-z0-9]*(?:-[a-z0-9]+)+)`\s*\|')) {
            $names.Add($r.Groups[1].Value) | Out-Null
        }

        $ok = 0
        foreach ($n in $names) { if ($proven.Contains($n)) { $ok++ } }

        $units.Add([pscustomobject]@{
            Name = $doc.BaseName; State = $state; Contract = $contract
            Proven = $ok; Total = $names.Count
            Owed = ([regex]::Matches($text, '\*\(owed\)\*')).Count
        }) | Out-Null
    }
}

if ($units.Count -eq 0) {
    Add-Problem "No $unitNoun document was read from $unitDir. Nothing below is measured."
}
# Every document parsing to zero rows is the quiet one: the documents are read, the marks are found,
# and every unit reads 0/0, so both sections below print "none" and the report looks clean.
elseif ((($units.ToArray() | Measure-Object Total -Sum).Sum) -eq 0) {
    Add-Problem "Not one $evNoun row parsed across $($units.Count) $unitNoun documents. The row's shape changed -- every one reads 0/0 below, which is a broken scan and not a repository with nothing proven."
}

Write-Host ""
Write-Host ("Owed rows on {0}s reading built" -f $unitNoun) -ForegroundColor White
$owed = @($units.ToArray() | Where-Object { $_.State -eq 'built' -and $_.Owed -gt 0 } | Sort-Object Name)
if ($owed.Count -eq 0) {
    Write-Host "  none" -ForegroundColor Gray
} else {
    foreach ($u in $owed) {
        Write-Host ("  {0,-16} {1} owed   ({2}/{3} proven)" -f $u.Name, $u.Owed, $u.Proven, $u.Total) -ForegroundColor Yellow
    }
    Write-Host ("  -> a backlog no Open: line ever mentions." ) -ForegroundColor Gray
}

Write-Host ""
Write-Host "Reading unbuilt, mostly proven" -ForegroundColor White
$near = @($units.ToArray() |
          Where-Object { $_.State -eq 'unbuilt' -and $_.Total -gt 0 -and ($_.Proven * 100 / $_.Total) -ge 75 } |
          Sort-Object { - ($_.Proven * 100 / $_.Total) })
if ($near.Count -eq 0) {
    Write-Host "  none" -ForegroundColor Gray
} else {
    foreach ($u in $near) {
        $why = if ($u.Contract -eq 'whole') { 'contract whole -- buildable backlog' } else { "contract $($u.Contract) -- waiting on writing, not code" }
        Write-Host ("  {0,-16} {1,3}% ({2}/{3})  {4}" -f $u.Name, [int]($u.Proven * 100 / $u.Total), $u.Proven, $u.Total, $why) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Contract none -- the builder does not start these" -ForegroundColor White
$none = @($units.ToArray() | Where-Object { $_.Contract -eq 'none' } | Sort-Object Name)
if ($none.Count -eq 0) {
    Write-Host "  none" -ForegroundColor Gray
} else {
    Write-Host ("  {0}: {1}" -f $none.Count, (($none | ForEach-Object { $_.Name }) -join ' ')) -ForegroundColor Yellow
    $empty = @($none | Where-Object { $_.Total -eq 0 })
    if ($empty.Count -gt 0) {
        Write-Host ("  -> {0} state no {1} at all: {2}" -f $empty.Count, $evNoun, (($empty | ForEach-Object { $_.Name }) -join ' ')) -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------ what it could not see

# A survey that silently measures nothing reads exactly like a repository with no gaps, which is the
# one way a report like this does harm rather than nothing.
Write-Host ""
if ($problems.Count -gt 0) {
    Write-Host "COULD NOT MEASURE" -ForegroundColor Red
    foreach ($p in $problems) { Write-Host "  $p" -ForegroundColor Red }
    exit 2
}

Write-Host ("Measured {0} {1}(s) and {2} capped document(s). Nothing here fails; report it." -f $units.Count, $unitNoun, $rows.Count) -ForegroundColor Green
exit 0
