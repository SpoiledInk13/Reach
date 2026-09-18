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

    Two ranges, because either alone is blind to half of it. `diff HEAD` is the working tree and the
    index, which catches an edit before it is committed. It also STOPS catching it the moment it is
    committed -- and this check ran that way for long enough to matter: a lane edited the archive,
    committed, and the gate it runs before landing saw a clean tree and passed. On a fresh CI checkout
    there is nothing uncommitted at all, so the check was a guaranteed no-op there while the badge
    stayed green. The second range is the branch's own commits -- everything it carries that the
    integration branch does not -- which is what a land is about to move.

    In push mode there is no local integration branch a land advances: what this branch carries is the
    reviewers' to read, and a stale local ref would only manufacture a diff nobody made.
#>
function Test-ArchiveImmutable {
    $archive = Get-Field $Process 'archive' $null
    if (-not $archive) { return }

    # No Test-Path guard on the archive directory. Git does not track directories, so pruning the
    # LAST file in the archive removes it -- and a guard that returned early when the directory was
    # missing went quiet for the largest possible version of the failure it exists to catch. A
    # configured archive that was never created matches nothing in either range and reports nothing,
    # which is the same answer by a route that cannot be fooled.

    $integration = Get-Integration $Process

    # Staged and unstaged together, and against HEAD rather than the index, so a change that was
    # staged and then partly reverted still reads as a change.
    $ranges = New-Object System.Collections.Generic.List[object]
    $ranges.Add([pscustomobject]@{ Spec = 'HEAD'; Where = 'This working tree' }) | Out-Null

    if ($integration.Mode -eq 'objects') {
        $exists = Invoke-Git -Path $RepoRoot -Arguments @('show-ref', '--verify', '--quiet', ("refs/heads/{0}" -f $integration.Branch))
        $head = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        # Three dots: from where this branch left the integration branch, not from wherever that
        # branch has since reached. Two dots would report every archive addition made elsewhere as
        # this branch deleting it.
        if ($exists.Code -eq 0 -and $head -and $head -ne $integration.Branch) {
            $ranges.Add([pscustomobject]@{
                Spec  = ("{0}...HEAD" -f $integration.Branch)
                Where = ("A commit here that '{0}' does not have" -f $integration.Branch)
            }) | Out-Null
        }
    }

    # One failure per path: a file both committed and then edited again reads from both ranges, and
    # saying so twice implies two separate offences.
    $reported = New-Object System.Collections.Generic.HashSet[string]
    foreach ($range in $ranges) {
        $result = Invoke-Git -Path $RepoRoot -Arguments @('diff', $range.Spec, '--name-status', '--find-renames', '--', $archive)
        if ($result.Code -ne 0) { continue }

        foreach ($line in $result.Lines) {
            if (-not $line) { continue }
            $parts = $line -split "`t"
            if ($parts.Count -lt 2) { continue }
            $status = $parts[0].Substring(0, 1)
            if ($status -eq 'A') { continue }
            if (-not $reported.Add($parts[1])) { continue }

            $what = switch ($status) {
                'D' { 'deletes' }
                'R' { 'renames' }
                default { 'modifies' }
            }
            Add-Failure ("{0} {1} {2}, which is the archive. Nothing in it is built, run, tested or fixed, and what it holds is only recoverable while nobody edits it. Add to it freely; never reach back in." -f $range.Where, $what, $parts[1])
        }
    }
}
