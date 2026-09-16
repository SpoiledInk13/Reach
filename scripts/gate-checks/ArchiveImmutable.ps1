<#
    The archive is read-only. Nothing in it is built, run, tested or fixed.

    Adoption replaces a workflow, and replacing is only safe because the thing replaced is still
    there. The archive is where the previous documents, commands and notes go, whole, so that a
    lesson removed by mistake is recoverable rather than gone. That guarantee is worth exactly as
    much as the rule that nobody edits it.

    Additions are fine, and are how things get deprecated: you move a document in, you never reach
    back in to tidy it. A file that gets edited in the archive is a file someone is still treating as
    live, which means it was not really replaced.

    Modifications and deletions both fail. Deletion especially -- a pruned archive is the one failure
    mode that cannot be noticed later, because what is missing leaves no trace.
#>
function Test-ArchiveImmutable {
    $archive = Get-Field $Process 'archive' $null
    if (-not $archive) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $archive))) { return }

    Push-Location -LiteralPath $RepoRoot
    try {
        # Staged and unstaged together, and against HEAD rather than the index, so a change that was
        # staged and then partly reverted still reads as a change.
        $changed = & git diff HEAD --name-status --find-renames -- $archive 2>$null
        if ($LASTEXITCODE -ne 0) { return }
    } finally {
        Pop-Location
    }

    foreach ($line in (ConvertTo-Array $changed)) {
        if (-not $line) { continue }
        $parts = $line -split "`t"
        $status = $parts[0].Substring(0, 1)
        if ($status -eq 'A') { continue }

        $what = switch ($status) {
            'D' { 'deletes' }
            'R' { 'renames' }
            default { 'modifies' }
        }
        Add-Failure ("This commit {0} {1}, which is the archive. Nothing in it is built, run, tested or fixed, and what it holds is only recoverable while nobody edits it. Add to it freely; never reach back in." -f $what, $parts[1])
    }
}
