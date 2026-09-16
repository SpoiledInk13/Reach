<#
    Every relative link in a maintained document resolves.

    This one earns its place twice. The obvious job is that a document nobody can follow is a
    document nobody reads, and links rot silently when files move -- a rename is one commit and the
    six documents pointing at the old name are six commits nobody made.

    The job that matters more is that it is the backstop for adoption. A source archived without its
    row being deleted from the adoption map leaves the map claiming work that is already done, and
    the only trace is that the row's link now points into the archive rather than at a live file.
    This catches that, which is why the adoption map is allowed to be a plain table rather than
    something with its own machinery.

    Only maintained documents are read. The archive is full of links to things that no longer exist,
    by design: those citations are exactly what adoption removed, and a rule that made the archive
    tidy would make it a rewrite rather than a record.
#>
function Test-DocLinks {
    $archive = Get-Field $Process 'archive' $null
    $skip = New-Object System.Collections.Generic.List[string]
    foreach ($dir in (ConvertTo-Array (Get-Field $Process 'unmaintained' @('node_modules', '.git', 'Library', 'obj', 'bin', 'target', '.venv')))) {
        $skip.Add($dir) | Out-Null
    }
    if ($archive) { $skip.Add($archive) | Out-Null }

    $checked = 0
    foreach ($doc in (Get-ChildItem -LiteralPath $RepoRoot -Filter *.md -Recurse -File)) {
        $relative = $doc.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')

        $skipped = $false
        foreach ($dir in $skip) {
            $normalised = $dir.Replace('\', '/').TrimEnd('/')
            if ($relative -eq $normalised -or $relative.StartsWith($normalised + '/')) { $skipped = $true; break }
        }
        if ($skipped) { continue }

        $checked++
        $text = Read-TextUtf8 $doc.FullName
        $dir = Split-Path -Parent $doc.FullName

        foreach ($match in [regex]::Matches($text, '\]\(([^)\s]+?)(?:\s+"[^"]*")?\)')) {
            $target = $match.Groups[1].Value
            if ($target -match '^(https?:|mailto:|#|/)') { continue }

            # A link may carry an anchor, and the anchor is not part of the path. Nothing here
            # verifies the anchor itself: headings get reworded constantly and a check that failed on
            # every rewording would be turned off within a week.
            $path = ($target -split '#')[0]
            if (-not $path) { continue }

            if (-not (Test-Path -LiteralPath (Join-Path $dir ([uri]::UnescapeDataString($path))))) {
                Add-Failure ("{0} links to {1}, which does not exist. Point it at what replaced it, or delete the sentence that needed it." -f $relative, $target)
            }
        }
    }

    if ($checked -eq 0) {
        Add-Failure "No maintained document was read. Either the documents moved, or something in 'unmaintained' is excluding all of them."
    }
}
