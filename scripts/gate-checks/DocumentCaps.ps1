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

    $spine = Get-Field $Process 'spine'
    if ($spine) {
        $path = Join-Path $RepoRoot (Get-Field $spine 'path' 'Docs/ARCHITECTURE.md')
        $cap = [int](Get-Field $spine 'cap' 600)
        if (Test-Path -LiteralPath $path) {
            $checked++
            $lines = Get-LineCount $path
            if ($lines -gt $cap) {
                Add-Failure ("{0} is {1} lines, cap {2}. Split it or cut it; raising a cap is a conversation, not an edit." -f (Get-Field $spine 'path' 'Docs/ARCHITECTURE.md'), $lines, $cap)
            }
        }
    }

    $unit = Get-Field $Process 'unit'
    $unitRel = Get-Field $unit 'dir' 'Docs/systems'
    $unitDir = Join-Path $RepoRoot $unitRel
    if (Test-Path -LiteralPath $unitDir) {
        $unitCap = [int](Get-Field $unit 'cap' 500)
        $noun = Get-Field $unit 'noun' 'system'
        foreach ($doc in (Get-ChildItem -LiteralPath $unitDir -Filter *.md -File)) {
            $checked++
            $lines = Get-LineCount $doc.FullName
            if ($lines -gt $unitCap) {
                Add-Failure ("{0}/{1} is {2} lines, cap {3}. A {4} that outgrows its cap is two {4}s." -f $unitRel, $doc.Name, $lines, $unitCap, $noun)
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
            if ($lines -gt [int]$property.Value) {
                Add-Failure ("{0} is {1} lines, cap {2}. Split it or cut it; raising a cap is a conversation, not an edit." -f $property.Name, $lines, [int]$property.Value)
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
