<#
    Every maintained document has a line cap, and the cap is what makes deletion happen.

    A document with no ceiling grows, because adding is always cheaper than reconciling. One corpus
    reached 662,000 lines that way, and the mechanisms written to consolidate it added too: its
    domain model ran to 9,067 lines, and a single entry in it was seventy lines long, carried
    twenty-five citations, described four retired mechanisms, and contained a dated correction to
    itself. Nothing in it was wrong when written. It was never allowed to shrink.

    A cap is not a budget to spend up to. It is the thing that forces the question "what in here is
    no longer true?" on the day you want to add. You may split a document, and you may cut it. You
    may not raise the cap without saying why and what you would cut instead -- a raise is a
    conversation, never an edit, and a splitting cost is what bounds the document count too.

    Caps are set at adoption from each document's own size plus a small margin, never inherited from
    another project. The number means "about this big", and it only does its work while it pinches.
#>
function Test-DocumentCaps {
    $checked = 0

    <#
        A cap of zero is the template's placeholder, and it used to be read as a ceiling of zero
        lines -- so a fresh adoption that had not set its caps yet failed EVERY document with "split
        it or cut it". Nothing was too long and nothing wanted splitting; a number had never been
        chosen. It stays blocking, because an unset cap is a real gap, and an unenforced cap is how a
        document starts growing. Only the diagnosis changes.

        A scriptblock in a local variable rather than a second function, because the gate dot-sources
        a check file inside a function of its own and keeps only Test-<name>. A helper function beside
        it loads without complaint and is gone by the time the check runs.
    #>
    $unsetCap = {
        param([string]$Relative, [int]$Lines)
        "no cap is set for {0} -- process.json has 0, which is the placeholder rather than a ceiling. It is {1} lines now; caps are set at adoption from the document's own size plus a small margin." -f $Relative, $Lines
    }

    $spine = Get-Field $Process 'spine'
    if ($spine) {
        $relative = Get-Field $spine 'path' 'Docs/ARCHITECTURE.md'
        $path = Join-Path $RepoRoot $relative
        $cap = [int](Get-Field $spine 'cap' 600)
        if (Test-Path -LiteralPath $path) {
            $checked++
            $lines = Get-LineCount $path
            if ($cap -le 0) {
                Add-Failure (& $unsetCap $relative $lines)
            }
            elseif ($lines -gt $cap) {
                Add-Failure ("{0} is {1} lines, cap {2}. Split it or cut it; raising a cap is a conversation, not an edit." -f $relative, $lines, $cap)
            }
        }
    }

    # Only when it is its own document. The roster grows by a row per unit and by nothing else, so
    # its cap is what bounds how many units there are -- the job the spine's cap did by accident while
    # the table lived there, and did badly, because a rule added to the spine spent the same lines.
    $roster = Get-Field $Process 'roster'
    if ($roster) {
        $relative = Get-Field $roster 'path' ''
        $path = Join-Path $RepoRoot $relative
        $cap = [int](Get-Field $roster 'cap' 0)
        if ($relative -and (Test-Path -LiteralPath $path)) {
            $checked++
            $lines = Get-LineCount $path
            if ($cap -le 0) {
                Add-Failure (& $unsetCap $relative $lines)
            }
            elseif ($lines -gt $cap) {
                Add-Failure ("{0} is {1} lines, cap {2}. Split it or cut it; raising a cap is a conversation, not an edit." -f $relative, $lines, $cap)
            }
        }
    }

    $unit = Get-Field $Process 'unit'
    $unitRel = Get-Field $unit 'dir' 'Docs/systems'
    $unitDir = Join-Path $RepoRoot $unitRel
    if (Test-Path -LiteralPath $unitDir) {
        $unitCap = [int](Get-Field $unit 'cap' 500)
        $noun = Get-Field $unit 'noun' 'system'
        $documents = @(Get-ChildItem -LiteralPath $unitDir -Filter *.md -File)

        # One failure for the unit cap, not one per document: the number is missing once, and saying
        # so eleven times buries every other line in the report.
        if ($unitCap -le 0 -and $documents.Count -gt 0) {
            $checked += $documents.Count
            Add-Failure ("no cap is set for the {0} documents in {1} -- process.json has unit.cap {2}. Caps are set at adoption from each document's own size plus a small margin, and a cap of zero is the placeholder, not a ceiling. Nothing here is too long; the number was never chosen." -f $noun, $unitRel, $unitCap)
        }
        else {
            foreach ($doc in $documents) {
                $checked++
                $lines = Get-LineCount $doc.FullName
                if ($lines -gt $unitCap) {
                    Add-Failure ("{0}/{1} is {2} lines, cap {3}. A {4} that outgrows its cap is two {4}s." -f $unitRel, $doc.Name, $lines, $unitCap, $noun)
                }
            }
        }
    }

    $caps = Get-Field $Process 'caps'
    if ($caps) {
        foreach ($property in $caps.PSObject.Properties) {
            $path = Join-Path $RepoRoot $property.Name
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $checked++
            $lines = Get-LineCount $path
            $cap = [int]$property.Value
            if ($cap -le 0) {
                Add-Failure (& $unsetCap $property.Name $lines)
            }
            elseif ($lines -gt $cap) {
                Add-Failure ("{0} is {1} lines, cap {2}. Split it or cut it; raising a cap is a conversation, not an edit." -f $property.Name, $lines, $cap)
            }
        }
    }

    # A check that silently measures nothing passes forever. This one has been pointed at a moved
    # documents folder and reported clean, which is indistinguishable from every document being
    # within its cap right up until someone looks.
    if ($checked -eq 0) {
        Add-Failure "No document was measured. Either process.json points at paths that do not exist, or the documents moved and the caps did not follow."
    }
}
