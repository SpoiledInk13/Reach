<#
    Every roster row has a unit document, and the document says whether it is a contract.

    Whether the builder may build against a document is the one fact about a document that is not in
    it. On the project this was earned on it was a sentence in the middle of the prose, phrased four
    ways across seven documents, and nothing could query it. Three things followed, all measured in
    one sitting.

    Five roster rows had no document at all, while sixty-three deferrals in the other documents
    pointed at them -- "flora and fauna are that unit's", "who holds a system is that unit's". Nothing
    required one. Every reference to them was a name in prose rather than a link, so the link check
    resolved none of it, and a row with no document is in no backlog the builder reads: it is never
    built, never skipped, and never reported. It simply does not come up.

    Five more read as finished contracts while material they had not yet absorbed was still queued
    against them, and nothing said which they were. One was next in build order. A document that is
    complete and a document that only looks complete are indistinguishable from outside, and that is
    how an incomplete unit gets built with every check green.

    And four documents asserted *another* unit's contract state in prose, and every one of them had
    gone false. One was written two days before the unit it described flipped to built. A premise about
    a peer rots silently, because the two facts live in different files and nothing compares them.

    So the fact is declared in the header and recorded nowhere else. `none` means the missing part is
    load-bearing and the unit is not to be started; `partial` means what is written is a contract and
    the rest arrives later; absent means whole.

    The prose ban names the wordings that actually rotted rather than every wording that could, and
    that is deliberate: the header is the only record, so any of these appearing is a second one.
#>
function Test-ContractIsDeclared {
    $unit = Get-Field $Process 'unit'
    $unitDir = Join-Path $RepoRoot (Get-Field $unit 'dir' 'Docs/systems')
    if (-not (Test-Path -LiteralPath $unitDir)) { return }
    $unitNoun = Get-Field $unit 'noun' 'system'

    $spine = Get-Field $Process 'spine'
    $spinePath = Join-Path $RepoRoot (Get-Field $spine 'path' 'Docs/ARCHITECTURE.md')

    # ------------------------------------------------------------------ every roster row has a document

    # The roster is part of the spine unless `roster` names a document of its own. Reading that field
    # is what keeps this half of the check when a project moves the table out: it used to fall back to
    # the declaration half alone, and a spine with no roster in it parses as a roster with no missing
    # documents -- green, and measuring nothing.
    #
    # Moving it out is worth doing for a reason the caps create. A unit that outgrows its cap is two
    # units, and a split costs a roster row; while the row lives in the spine it competes with every
    # rule there for a line, so a project whose spine is full cannot split anything, and the document
    # that wanted splitting cannot grow either. One project met both ceilings on the same day.
    $roster = Get-Field $Process 'roster'
    $rosterPath = if ($roster) { Join-Path $RepoRoot (Get-Field $roster 'path' '') } else { $spinePath }

    if (Test-Path -LiteralPath $rosterPath) {
        $names = @([regex]::Matches((Get-Content -LiteralPath $rosterPath -Raw), '(?m)^\|\s*`([a-z][a-z0-9-]*)`\s*\|') |
                   ForEach-Object { $_.Groups[1].Value })
        foreach ($name in $names) {
            if (-not (Test-Path -LiteralPath (Join-Path $unitDir "$name.md"))) {
                Add-Failure ("The roster names '{0}' and {1}/{0}.md does not exist. A roster row with no document is in no backlog and is never built -- write it as a stub declaring **Contract:** none, saying what the roster says it owns and what other documents already defer to it, rather than leaving the row to read as tracked." -f $name, (Get-Field $unit 'dir' 'Docs/systems'))
            }
        }
    }

    # ------------------------------------------------------------------ the declaration says which kind

    # Each is now the header's to state, so an occurrence in prose is a second record of it -- and the
    # second record about another unit is the one that goes false unnoticed.
    $banned = @('not yet a contract', 'is not a contract', 'not yet whole')

    foreach ($doc in Get-ChildItem -LiteralPath $unitDir -Filter *.md -File) {
        $text = Get-Content -LiteralPath $doc.FullName -Raw
        if (-not $text) { continue }

        # The declaration wraps like any other header line, so it is read to the next field or the
        # blank line that ends the block. Matching one line would miss half of what it says.
        $decl = [regex]::Match($text, '(?ms)^\*\*Contract:\*\*[ ]*(.*?)(?=^\*\*|^\r?$)')
        if ($decl.Success) {
            $flat = ($decl.Groups[1].Value -replace '\s+', ' ').Trim()
            if ($flat -notmatch '^(none|partial)\b') {
                Add-Failure ("{0}/{1}'s **Contract:** line reads '{2}'. It is 'none' -- the missing part is load-bearing, so the {3} is not started -- or 'partial' -- what is written is a contract and the rest arrives later. A document that is whole carries no line at all." -f (Get-Field $unit 'dir' 'Docs/systems'), $doc.Name, $flat, $unitNoun)
            }
        }

        # Collapsed, because these documents hard-wrap and a phrase probe spanning the break sees
        # nothing at all -- which reads as an absence and is how one of the four went unnoticed.
        $collapsed = $text -replace '\s+', ' '
        foreach ($phrase in $banned) {
            if ($collapsed -match [regex]::Escape($phrase)) {
                Add-Failure ("{0}/{1} says '{2}' in prose. Whether a document is a contract is its **Contract:** header's to state and nothing else's. Four sentences of this shape asserted another {3}'s state and every one had gone false -- if the point is why a claim is proven over a stand-in, the reason is a fact about content, never a claim about a peer's contract." -f (Get-Field $unit 'dir' 'Docs/systems'), $doc.Name, $phrase, $unitNoun)
            }
        }
    }
}
