#Requires -Version 5.1
<#
.SYNOPSIS
    Proves every reach check can fail. Builds a fixture, breaks one thing at a time, and requires
    the gate to go red for that check and green again afterwards.

.DESCRIPTION
    A check whose failure path has never been observed is decoration. That is easy to agree with and
    easy to skip, so it is a script rather than a habit: run this and the claim is measured instead
    of remembered.

    Two halves, and the second is the one that gets forgotten. Red when broken says the check can
    fire. Green when restored says it fires on the thing it names rather than on something ambient
    in the fixture -- without it, a check that failed on every run at all would pass this suite.

    A control also asserts WHICH check fired. A gate that goes red for the wrong reason is how a
    check gets believed for years while testing nothing: the suite was green, so nobody looked at
    which line produced the red.

.PARAMETER Keep
    Leave the fixture on disk afterwards, to poke at a control by hand.
#>
[CmdletBinding()]
param([switch]$Keep)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# For Get-PowerShellExe: this suite launches the gate in a child process, and hard-coding the
# launcher is what kept it from running anywhere but Windows.
. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$ScriptRoot = $PSScriptRoot
$Gate = Join-Path $ScriptRoot 'Verify-Gate.ps1'
$Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("reach-prove-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

function Write-File {
    param([string]$Relative, [string]$Content)
    $path = Join-Path $Fixture $Relative
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # Every fixture file ends in exactly one newline. A here-string does not, and the first control
    # that appended a line to one glued it onto the end of the last table row -- where the check read
    # it as part of the row rather than as a line of its own, reported nothing, and the suite blamed
    # the check. A malformed fixture and a decorative check look identical from the outside.
    if (-not $Content.EndsWith("`n")) { $Content += "`n" }
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function New-Fixture {
    if (Test-Path -LiteralPath $Fixture) { Remove-Item -LiteralPath $Fixture -Recurse -Force }
    New-Item -ItemType Directory -Path $Fixture -Force | Out-Null

    Write-File 'process.json' @'
{
  "project": "fixture",
  "spine":    { "path": "Docs/ARCHITECTURE.md", "cap": 20 },
  "unit":     { "noun": "system", "dir": "Docs/systems", "cap": 30 },
  "evidence": { "noun": "scenario", "mark": "// scenario:", "search": ["Tests"] },
  "human":    { "doc": "Docs/process/WALKTHROUGHS.md", "noun": "walkthrough" },
  "archive":  "Reference",
  "adoption": "Docs/process/ADOPTION.md",
  "checks":   "Scripts/gate-checks"
}
'@
    Write-File 'Docs/ARCHITECTURE.md' "# Spine`n`nThe frame.`n"
    Write-File 'Docs/systems/widget.md' @'
# widget

**State:** built

## Claims

- A widget spins.

## Scenarios

| Name | Proves |
|---|---|
| `widget-spins` | a widget spins |
'@
    Write-File 'Docs/systems/sprocket.md' @'
# sprocket

**State:** unbuilt

## Claims

- A sprocket meshes.

## Scenarios

| Name | Proves |
|---|---|
| `sprocket-meshes` | a sprocket meshes |
'@
    Write-File 'Tests/WidgetTests.cs' "// scenario: widget-spins`nvoid Test() { }`n"
    Write-File 'Docs/process/WALKTHROUGHS.md' (@'
# Walkthroughs

## 1. A widget turns

**Turn the thing on and watch a widget spin.**

**Needs:** widget.

**Not working:** The widget does not spin.
{0} The claim is `widget-spins`, built and proven. What the owner has not seen
yet is the spinning itself, so this waits on a build rather than on the builder.
'@ -f [char]0x2192)
    Write-File 'Reference/old.md' "# Old`n`nArchived.`n"
    Write-File 'Docs/process/ADOPTION.md' @'
# Adoption

| Source | Lines | Goes to |
|---|---|---|
| [old.md](../../Reference/old.md) | 3 | widget |
'@
    New-Item -ItemType Directory -Path (Join-Path $Fixture 'Scripts/gate-checks') -Force | Out-Null

    Push-Location -LiteralPath $Fixture
    try {
        & git init -q 2>&1 | Out-Null
        & git config user.email 'fixture@example.invalid' | Out-Null
        & git config user.name 'Fixture' | Out-Null
        & git add -A 2>&1 | Out-Null
        & git commit -qm 'fixture' 2>&1 | Out-Null
    } finally { Pop-Location }
}

function Invoke-Gate {
    $launch = Get-PowerShellArgs
    $output = & (Get-PowerShellExe) @launch -File $Gate -Root $Fixture 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

# ------------------------------------------------------------------------------------ controls

$controls = @(
    @{ Check = 'DocumentCaps'; What = 'the spine outgrows its cap'
       Break = { Add-Content -LiteralPath (Join-Path $Fixture 'Docs/ARCHITECTURE.md') -Value (1..40 | ForEach-Object { "line $_" }) } }

    @{ Check = 'DocumentCaps'; What = 'every document moves out from under its cap'
       Break = { Rename-Item -LiteralPath (Join-Path $Fixture 'Docs') -NewName 'Documents' } }

    @{ Check = 'DocumentCaps'; What = 'a cap was never set, and is not reported as a document to split'
       Says  = 'no cap is set'
       Break = { Write-File 'process.json' ((Get-Content -LiteralPath (Join-Path $Fixture 'process.json') -Raw) -replace '"cap": 20', '"cap": 0') } }

    @{ Check = 'ArchiveImmutable'; What = 'the archive is edited'
       Break = { Add-Content -LiteralPath (Join-Path $Fixture 'Reference/old.md') -Value 'tidied' } }

    @{ Check = 'ArchiveImmutable'; What = 'the archive is pruned'
       Break = { Remove-Item -LiteralPath (Join-Path $Fixture 'Reference/old.md') -Force } }

    @{ Check = 'ArchiveImmutable'; What = 'the archive is edited in a commit this branch carries'
       Break = { Push-Location -LiteralPath $Fixture
                 try {
                     # Committed, which is how it arrives for real: a lane edits, commits, and runs
                     # the gate before landing. `diff HEAD` is clean by then and saw nothing.
                     # The replacement keeps the line count so AdoptionCounts stays out of it.
                     & git branch develop 2>&1 | Out-Null
                     & git checkout -q -b working 2>&1 | Out-Null
                     Write-File 'Reference/old.md' "# Old`n`nTidied.`n"
                     & git add -A 2>&1 | Out-Null
                     & git commit -qm 'tidy the archive' 2>&1 | Out-Null
                 } finally { Pop-Location } } }

    @{ Check = 'ArchiveImmutable'; What = 'the archive is pruned in a commit, taking its directory with it'
       Break = { Push-Location -LiteralPath $Fixture
                 try {
                     # old.md is the only file in the archive, so committing its deletion removes the
                     # directory too -- and the check used to return early on exactly that.
                     & git branch develop 2>&1 | Out-Null
                     & git checkout -q -b working 2>&1 | Out-Null
                     & git rm -q 'Reference/old.md' 2>&1 | Out-Null
                     & git commit -qm 'prune the archive' 2>&1 | Out-Null
                 } finally { Pop-Location } } }

    @{ Check = 'ClaimsAreProven'; What = 'a built claim has no evidence'
       Break = { Write-File 'Tests/WidgetTests.cs' "void Test() { }`n" } }

    @{ Check = 'ClaimsAreProven'; What = 'evidence names a claim no document makes'
       Break = { Write-File 'Tests/WidgetTests.cs' "// scenario: widget-wobbles`nvoid Test() { }`n" } }

    @{ Check = 'ClaimsAreProven'; What = 'an owed mark sits on a claim evidence already proves'
       Break = { Write-File 'Docs/systems/widget.md' ((Get-Content -LiteralPath (Join-Path $Fixture 'Docs/systems/widget.md') -Raw) -replace '\| `widget-spins` \|', '| `widget-spins` | *(owed)*') } }

    @{ Check = 'ClaimsAreProven'; What = 'an unbuilt unit owes something'
       Break = { Write-File 'Docs/systems/sprocket.md' ((Get-Content -LiteralPath (Join-Path $Fixture 'Docs/systems/sprocket.md') -Raw) -replace '\| `sprocket-meshes` \|', '| `sprocket-meshes` | *(owed)*') } }

    @{ Check = 'ClaimsAreProven'; What = 'a built unit holds a question it does not owe'
       Break = { Add-Content -LiteralPath (Join-Path $Fixture 'Docs/systems/widget.md') -Value '  **Open:** how fast?' } }

    @{ Check = 'TriageLines'; What = 'a triage line still calls a built row owed'
       Break = { # Read-TextUtf8, not Get-Content: 5.1 decodes this un-BOMed UTF-8 file as CP1252, and
                 # round-tripping it through a control mangles the arrow the check keys on. The first
                 # version of this control did exactly that and reported the check as decoration.
                 Write-File 'Docs/process/WALKTHROUGHS.md' ((Read-TextUtf8 (Join-Path $Fixture 'Docs/process/WALKTHROUGHS.md')) -replace '`widget-spins`, built and proven', '`widget-spins`, *(owed)*') } }

    @{ Check = 'TriageLines'; What = 'a triage line calls an owed row built'
       Break = { # The mark goes onto the row and the line naming it still reads built, which is the
                 # direction that gets acted on: the lane is sent at work that is not there.
                 Write-File 'Docs/systems/widget.md' ((Get-Content -LiteralPath (Join-Path $Fixture 'Docs/systems/widget.md') -Raw) -replace '\| `widget-spins` \|', '| `widget-spins` | *(owed)*')
                 Write-File 'Tests/WidgetTests.cs' "void Test() { }`n" } }

    @{ Check = 'TriageLines'; What = 'a triage line names an owed row on a continuation line'
       Break = { # The same miss, with the name moved off the line the arrow opens. A check reading
                 # physical lines passes this one and fails the one above, which is how it would
                 # have shipped looking proven.
                 Write-File 'Docs/systems/widget.md' ((Get-Content -LiteralPath (Join-Path $Fixture 'Docs/systems/widget.md') -Raw) -replace '\| `widget-spins` \|', '| `widget-spins` | *(owed)*')
                 Write-File 'Tests/WidgetTests.cs' "void Test() { }`n"
                 Write-File 'Docs/process/WALKTHROUGHS.md' ((Read-TextUtf8 (Join-Path $Fixture 'Docs/process/WALKTHROUGHS.md')) -replace 'The claim is `widget-spins`, built and proven\.', ('The claim it waits on is written down,' + "`r`n" + 'and it is named here: `widget-spins`, built and proven.')) } }

    @{ Check = 'DocLinks'; What = 'a maintained document links to nothing'
       Break = { Add-Content -LiteralPath (Join-Path $Fixture 'Docs/ARCHITECTURE.md') -Value 'See [the plan](../Docs/plan.md).' } }

    @{ Check = 'PrimaryIsStale'; What = 'a lane lands while the primary checkout is not looking'
       Break = { Push-Location -LiteralPath $Fixture
                 try {
                     # Exactly how it happens for real: the integration ref is advanced from objects
                     # while the primary has its own branch checked out. No file here changes, and
                     # nothing in this tree says the documents moved -- which is the whole problem.
                     & git checkout -q -b working 2>&1 | Out-Null
                     $head = ([string](& git rev-parse HEAD)).Trim()
                     $tree = ([string](& git rev-parse 'HEAD^{tree}')).Trim()
                     $landed = ([string](& git commit-tree $tree -p $head -m 'a lane landed')).Trim()
                     & git branch -f develop $landed 2>&1 | Out-Null
                 } finally { Pop-Location } } }

    @{ Check = 'AdoptionCounts'; What = 'a recorded line count stops matching its file'
       Break = { Add-Content -LiteralPath (Join-Path $Fixture 'Reference/old.md') -Value 'a line'
                 Push-Location -LiteralPath $Fixture; try { & git add -A 2>&1 | Out-Null; & git commit -qm 'archive grows' 2>&1 | Out-Null } finally { Pop-Location } } }
)

# ---------------------------------------------------------------------------------------- run

Write-Host "Prove-Gate -- $($controls.Count) negative control(s)" -ForegroundColor Cyan
Write-Host "fixture: $Fixture" -ForegroundColor DarkGray

New-Fixture
$baseline = Invoke-Gate
if ($baseline.Code -ne 0) {
    Write-Host "REFUSED: the fixture is not green before anything is broken. Nothing below would mean anything." -ForegroundColor Red
    Write-Host $baseline.Output
    exit 2
}
Write-Host "  baseline green" -ForegroundColor DarkGray
Write-Host ""

$failures = New-Object System.Collections.Generic.List[string]

foreach ($control in $controls) {
    $name = "{0}: {1}" -f $control.Check, $control.What

    New-Fixture
    & $control.Break
    $broken = Invoke-Gate

    if ($broken.Code -eq 0) {
        $failures.Add("$name -- gate stayed GREEN. The check cannot see this, so it is not testing what it says.") | Out-Null
        Write-Host ("  DECORATION  {0}" -f $name) -ForegroundColor Red
        continue
    }
    if ($broken.Output -notmatch ("\[" + [regex]::Escape($control.Check) + "\]")) {
        $failures.Add("$name -- gate went red, but not from $($control.Check). A red for the wrong reason is how a check gets believed while testing nothing.") | Out-Null
        Write-Host ("  WRONG CHECK {0}" -f $name) -ForegroundColor Red
        continue
    }

    # Optional, and only where the diagnosis IS the thing being proven. A check that goes red for two
    # different causes with one message sends you to fix the wrong one, and the red alone cannot tell
    # those apart -- so a control about wording has to read the wording.
    if ($control.ContainsKey('Says') -and $broken.Output -notmatch $control.Says) {
        $failures.Add("$name -- $($control.Check) fired, but did not say it. Expected /$($control.Says)/ in the failure.") | Out-Null
        Write-Host ("  WRONG WHY   {0}" -f $name) -ForegroundColor Red
        continue
    }

    New-Fixture
    $restored = Invoke-Gate
    if ($restored.Code -ne 0) {
        $failures.Add("$name -- gate did not go green again after restoring. The red was ambient, not caused by the break.") | Out-Null
        Write-Host ("  AMBIENT     {0}" -f $name) -ForegroundColor Red
        continue
    }

    Write-Host ("  proven      {0}" -f $name) -ForegroundColor Green
}

if (-not $Keep -and (Test-Path -LiteralPath $Fixture)) {
    Remove-Item -LiteralPath $Fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host ("FAIL -- {0} of {1} control(s) did not behave" -f $failures.Count, $controls.Count) -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host ("  {0}" -f $failure) -ForegroundColor Red }
    exit 1
}
Write-Host ("PASS -- all {0} control(s) went red for the right check and green again" -f $controls.Count) -ForegroundColor Green
exit 0
