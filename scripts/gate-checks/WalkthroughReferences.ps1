<#
    A walkthrough is named by what it is, never by its number or its place in the list.

    The list is ordered and a confirmed entry is deleted, so the entries below it move up. That is
    the whole point of the document -- and it means every reference by number or by position quietly
    comes to mean a different entry, with nothing anywhere that would say so. A unit document reading
    "walkthrough 3 needs claims 1 and 2" is not wrong in any way a reader can see. It is wrong in a
    way only the list can see, and the list is not looking.

    Measured, in the repository this came from: confirming one entry left six references across three
    documents pointing at things that no longer existed. The commit that deleted it said in its own
    message that they were going stale and left them for later. Later was six days, and by then two
    more had been written against a number that had already moved.

    Three handles survive a deletion, and the check allows exactly those. The sentence, italicised
    before the noun -- *the fireplace from a cold start* walkthrough -- which this resolves against
    the live entries, so it fails loudly the day that entry is confirmed rather than silently. A
    predicate, "the first walkthrough that runs a game", which identifies itself however the list
    moves. And "the top walkthrough", which is defined as whichever is first and so cannot go stale.

    A confirmed walkthrough is named at no handle at all. What it brought is shipped, so the sentence
    to write is about the thing rather than about the entry that delivered it.

    The human document itself is skipped. It is the one place the banned forms legitimately appear --
    as the examples in the rule banning them -- and it holds the entries rather than pointing at them.
#>
function Test-WalkthroughReferences {
    $human = Get-Field $Process 'human' $null
    if (-not $human) { return }

    $docRelative = Get-Field $human 'doc' ''
    if (-not $docRelative) { return }
    $doc = Join-Path $RepoRoot $docRelative
    if (-not (Test-Path -LiteralPath $doc)) { return }

    # The project names its own walkthroughs, so the pattern is built from that word rather than
    # from this file's vocabulary. A project calling them "runs" gets "run 3" caught and nothing else.
    $noun = Get-Field $human 'noun' 'walkthrough'
    $nounPattern = [regex]::Escape($noun) + 's?'

    $live = @()
    foreach ($m in [regex]::Matches((Read-TextUtf8 $doc), '(?m)^##[ ]+\d+\.[ ]+(.+?)\s*$')) {
        $live += $m.Groups[1].Value.Trim()
    }

    $skip = New-Object System.Collections.Generic.List[string]
    foreach ($dir in (ConvertTo-Array (Get-Field $Process 'unmaintained' @('node_modules', '.git', 'Library', 'obj', 'bin', 'target', '.venv')))) {
        $skip.Add($dir) | Out-Null
    }
    $archive = Get-Field $Process 'archive' $null
    if ($archive) { $skip.Add($archive) | Out-Null }

    $docNormalised = $docRelative.Replace('\', '/')
    $checked = 0

    foreach ($file in (Get-ChildItem -LiteralPath $RepoRoot -Filter *.md -Recurse -File)) {
        $relative = $file.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
        if ($relative -eq $docNormalised) { continue }

        $skipped = $false
        foreach ($dir in $skip) {
            $normalised = $dir.Replace('\', '/').TrimEnd('/')
            if ($relative -eq $normalised -or $relative.StartsWith($normalised + '/')) { $skipped = $true; break }
        }
        if ($skipped) { continue }

        $checked++

        # The reference hard-wraps, and a pattern matched line by line reads "the first\n walkthrough"
        # as absent -- which is how two of these survived a grep written to find them. Each newline
        # becomes one space, so an index into the flattened text still indexes the original.
        $text = Read-TextUtf8 $file.FullName
        $flat = $text -replace '[\r\n]', ' '

        $report = {
            param($index, $quoted, $why)
            $line = 1 + @([regex]::Matches($text.Substring(0, [Math]::Min($index, $text.Length)), "`n")).Count
            Add-Failure ("{0}:{1} names a {2} as `{3}`. {4}" -f $relative, $line, $noun, $quoted, $why)
        }

        foreach ($m in [regex]::Matches($flat, "(?i)$nounPattern[ ]+\d+")) {
            & $report $m.Index $m.Value ("Confirming one deletes it and the rest move up, so a number comes to mean a different entry with nothing to say it has. Name it by its sentence, or -- if it is already confirmed -- name the thing it brought instead ({0})." -f $docRelative)
        }

        foreach ($m in [regex]::Matches($flat, "(?i)\bthe[ ]+(?:first|second|third|fourth|last)[ ]+$nounPattern\b(?![ ]+that\b)")) {
            & $report $m.Index $m.Value ("A position moves when an entry above it is confirmed. `the top {0}` is defined as whichever is first, and `the first {0} that <does something>` identifies itself; a bare ordinal does neither ({1})." -f $noun, $docRelative)
        }

        foreach ($m in [regex]::Matches($flat, "\*([^*]+)\*[ ]+$nounPattern")) {
            $title = $m.Groups[1].Value.Trim()
            if ($live | Where-Object { $_ -ieq $title }) { continue }
            $named = if ($live) { $live -join '; ' } else { '(none)' }
            & $report $m.Index $title ("{0} states no entry by that sentence, so the reference points at nothing. A confirmed {1} is not named at all -- name the thing it brought. Live: {2}." -f $docRelative, $noun, $named)
        }
    }

    # A reference check that read nothing passes every repository, including the one that moved its
    # documents somewhere 'unmaintained' covers.
    if ($checked -eq 0) {
        Add-Failure "No maintained document was read, so no reference was resolved. Either the documents moved, or something in 'unmaintained' is excluding all of them."
    }
}
