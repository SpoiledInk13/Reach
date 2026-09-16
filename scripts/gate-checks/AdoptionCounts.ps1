<#
    The adoption map holds its line counts to the files, so a stalled adoption is visible.

    Adoption replaces a workflow one document at a time, and the map is the work list: every source
    that still has to be read, its size, and where its content is going. The size is the point. It is
    the only signal that says whether the work is moving, because a map of thirty rows looks the same
    on day one and day thirty.

    Hand-typed counts rot, reliably. In the one corpus this was measured on, five recorded counts
    were off by one from a real drain, and one document had shrunk forty lines with its figure
    untouched -- a signal nobody can see a change in is decoration. So the counts are re-measured
    here, every run, and a drain that did not update its row fails.

    The other half -- a source archived without its row being deleted -- is DocLinks' to report: the
    row's link dies the moment the file moves into the archive. Reported twice, the cause gets buried,
    so a dead link is skipped here rather than counted again.

    The map is self-liquidating. A row goes when its source is archived, the file deletes itself when
    the table empties, and its absence is the record that adoption finished.
#>
function Test-AdoptionCounts {
    $map = Get-Field $Process 'adoption' $null
    if (-not $map) { return }

    $path = Join-Path $RepoRoot $map
    if (-not (Test-Path -LiteralPath $path)) { return }

    $text = Read-TextUtf8 $path
    $dir = Split-Path -Parent $path

    # Both shapes a count is written in: a table row's Lines column, and a parenthesised figure in
    # prose for a source with no row of its own.
    foreach ($match in [regex]::Matches($text, '\]\(([^)#][^)]*?)\)\s*(?:\|\s*|\()([\d,]+)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^(https?:|mailto:)') { continue }

        $resolved = Join-Path $dir ([uri]::UnescapeDataString(($target -split '#')[0]))
        if (-not (Test-Path -LiteralPath $resolved)) { continue }

        $recorded = [int]$match.Groups[2].Value.Replace(',', '')
        $actual = Get-LineCount $resolved
        if ($recorded -ne $actual) {
            Add-Failure ("{0} records {1} at {2} lines; it is {3}. Update the map in the commit that drained it -- the count is the only signal that adoption is moving." -f $map, $target, $recorded, $actual)
        }
    }
}
