<#
    A unit marked built has evidence for every claim it makes, and the one exception is marked.

    This is the check the whole roster rests on. Without it, "built" records that someone wrote a
    document, and the difference between a claim that was implemented and a claim that was typed is
    invisible for as long as nobody goes looking.

    The *(owed)* mark exists because of the alternative. A claim added to a unit that is already
    built has no evidence yet, and the obvious move -- flip the unit back to unbuilt until it does --
    stops every unit that depends on it, none of which use the new claim. Doing that flipped one
    foundation unit back eight times in five days. So the unit stays built and the row carries the
    mark, which is what keeps the claim from reading as done. The gap that mark closes cost a day
    once: a claim landed six hours after its unit was built and nothing anywhere surfaced it.

    The mark is refused in the three places it would become an excuse: on a unit that is not built,
    on a row that evidence already proves, and as a way of holding an open question on a unit that
    owes nothing.
#>
function Test-ClaimsAreProven {
    $unit = Get-Field $Process 'unit'
    $unitDir = Join-Path $RepoRoot (Get-Field $unit 'dir' 'Docs/systems')
    if (-not (Test-Path -LiteralPath $unitDir)) { return }

    $unitNoun = Get-Field $unit 'noun' 'system'
    $evidence = Get-Field $Process 'evidence'
    $noun     = Get-Field $evidence 'noun' 'scenario'
    $mark     = Get-Field $evidence 'mark' ('// {0}:' -f $noun)
    $heading  = Get-Field $evidence 'heading' (($noun.Substring(0, 1).ToUpper() + $noun.Substring(1)) + 's')

    # ------------------------------------------------------------------ what evidence exists

    $proven = New-Object System.Collections.Generic.HashSet[string]
    $marks  = New-Object System.Collections.Generic.List[object]

    # A mark in a test file. The comment leader is whatever the project's language uses, so the mark
    # is matched as a literal prefix rather than assumed to be //.
    $pattern = '(?m)^\s*' + [regex]::Escape($mark) + '\s*([a-z0-9][a-z0-9-]*)\s*$'
    foreach ($dir in (ConvertTo-Array (Get-Field $evidence 'search' @('Tests')))) {
        $searchDir = Join-Path $RepoRoot $dir
        if (-not (Test-Path -LiteralPath $searchDir)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $searchDir -Recurse -File)) {
            if ($file.Length -gt 2MB) { continue }
            foreach ($m in [regex]::Matches((Read-TextUtf8 $file.FullName), $pattern)) {
                $proven.Add($m.Groups[1].Value) | Out-Null
                $marks.Add([pscustomobject]@{
                    Name  = $m.Groups[1].Value
                    Where = $file.FullName.Substring($RepoRoot.Length + 1)
                }) | Out-Null
            }
        }
    }

    # Or a file named for the evidence, where the project keeps evidence as data rather than as code.
    $evidenceFiles = Get-Field $evidence 'files' $null
    if ($evidenceFiles) {
        $filesDir = Join-Path $RepoRoot $evidenceFiles
        if (Test-Path -LiteralPath $filesDir) {
            foreach ($file in (Get-ChildItem -LiteralPath $filesDir -File)) {
                $proven.Add($file.BaseName) | Out-Null
                $marks.Add([pscustomobject]@{
                    Name  = $file.BaseName
                    Where = $file.FullName.Substring($RepoRoot.Length + 1)
                }) | Out-Null
            }
        }
    }

    # ------------------------------------------------------------------ what the documents claim

    $documented = New-Object System.Collections.Generic.HashSet[string]
    $docs = New-Object System.Collections.Generic.List[object]

    foreach ($doc in (Get-ChildItem -LiteralPath $unitDir -Filter *.md -File)) {
        $text = Read-TextUtf8 $doc.FullName
        $block = [regex]::Match($text, ('(?ms)^##\s+' + [regex]::Escape($heading) + '\s*$(.*?)(^##\s|\z)'))
        $names = @()
        $owed  = @()
        if ($block.Success) {
            $names = @([regex]::Matches($block.Groups[1].Value, '(?m)^\|\s*`([a-z0-9][a-z0-9-]*)`') | ForEach-Object { $_.Groups[1].Value })
            $owed  = @([regex]::Matches($block.Groups[1].Value, '(?m)^\|\s*`([a-z0-9][a-z0-9-]*)`\s*\|\s*\*\(owed\)\*') | ForEach-Object { $_.Groups[1].Value })
        }
        foreach ($name in $names) { $documented.Add($name) | Out-Null }
        $docs.Add([pscustomobject]@{
            Name  = $doc.Name
            Text  = $text
            Names = $names
            Owed  = $owed
        }) | Out-Null
    }

    # The direction that is easy to forget: a mark naming nothing. Evidence renamed or deleted from
    # its document leaves the test pointing at a claim that no longer exists, and a finishing edit
    # that quietly drops a claim shows up here and nowhere else.
    foreach ($m in $marks) {
        if (-not $documented.Contains($m.Name)) {
            Add-Failure ("{0} marks {1} '{2}', which no {3} document names. Rename the mark to the {1} it proves, or restore the row it lost." -f $m.Where, $noun, $m.Name, $unitNoun)
        }
    }

    # ------------------------------------------------------------------ and the two held together

    foreach ($doc in $docs) {
        $relative = "{0}/{1}" -f (Get-Field $unit 'dir' 'Docs/systems'), $doc.Name

        if ($doc.Text -notmatch '(?m)^\*\*State:\*\*\s*built\s*$') {
            # Every claim of an unbuilt unit is still to build, so the mark means nothing here. Left
            # in place it would survive the flip to built as an excuse nobody ever wrote for it.
            if ($doc.Owed.Count -gt 0) {
                Add-Failure ("{0} is unbuilt but marks {1} row(s) *(owed)*: {2}. Only a built {3} owes {4}; remove the mark." -f $relative, $doc.Owed.Count, ($doc.Owed -join ', '), $unitNoun, $noun)
            }
            continue
        }

        if (@($doc.Names | Where-Object { $doc.Owed -notcontains $_ }).Count -lt 1) {
            Add-Failure ("{0} is marked built but names no {1} it does not owe. Built means proven, not written." -f $relative, $noun)
        }

        $unproven = @($doc.Names | Where-Object { -not $proven.Contains($_) -and $doc.Owed -notcontains $_ })
        if ($unproven.Count -gt 0) {
            Add-Failure ("{0} is marked built but nothing proves {1} of its claims: {2}. Mark the test that proves each with '{3} <name>', or add the evidence file. A claim added after the {4} was built marks its row *(owed)* instead." -f $relative, $unproven.Count, ($unproven -join ', '), $mark, $unitNoun)
        }

        # The other half of the mark. Once evidence proves an owed row the mark comes off in the same
        # commit, or the backlog reads longer than it is and nobody can tell which owed claims are
        # really still waiting -- which is the one thing the mark exists to say.
        $settled = @($doc.Owed | Where-Object { $proven.Contains($_) })
        if ($settled.Count -gt 0) {
            Add-Failure ("{0} marks {1} row(s) *(owed)* that evidence already proves: {2}. Remove the mark in the commit that proves it." -f $relative, $settled.Count, ($settled -join ', '))
        }

        # An Open line is a claim the builder could not implement as written. A unit flipped to built
        # over one was finished by guessing the answer. So a built unit may carry a question only
        # while it owes evidence, where the question sits under the claim that owes it.
        #
        # Leading whitespace is matched on purpose: a claim is usually a bullet and its Open is
        # indented under it. Anchored hard at the line start, this check and the inbox grep both read
        # an indented question as absent, which is how a real one stayed invisible to both.
        $open = ([regex]::Matches($doc.Text, '(?m)^[ \t]*\*\*Open:\*\*')).Count
        if ($open -gt 0 -and $doc.Owed.Count -eq 0) {
            Add-Failure ("{0} is marked built but carries {1} Open question(s) and owes no {2}. A question on a built {3} sits under a claim it owes; a claim nobody has answered cannot have been built." -f $relative, $open, $noun, $unitNoun)
        }
    }
}
