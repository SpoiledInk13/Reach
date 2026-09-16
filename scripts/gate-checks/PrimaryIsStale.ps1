<#
    The primary checkout is the one working tree nothing syncs.

    Lanes land onto the integration branch by ref, which is what lets a land happen while every lane
    is busy -- and it means the branch the owner has open falls behind by everything every lane has
    landed since it last synced. Silently, because nothing in a working tree changes when a ref it
    does not hold moves. The documents read there are then a snapshot from before those lands: a
    question a lane filed is invisible, a unit's state is whatever it used to be, and a decision made
    from that text is made from a document that is no longer true.

    That has happened here. A run read an empty inbox and five unbuilt units from a tree twelve
    commits behind, and reported both; the integration branch held an unanswered question and all ten
    units built. Nothing was wrong with the grep.

    It blocks rather than warns because what it is protecting is not the tree but the decision, and
    the fix is one command. It fires only when it can prove staleness -- no integration branch, or a
    branch that is not the primary, and it says nothing -- so the negative control below is the only
    thing standing between this and decoration.
#>
function Test-PrimaryIsStale {
    $integration = Get-Integration $Process

    # In push mode there is no local integration branch to fall behind: landing is the reviewers'.
    if ($integration.Mode -ne 'objects') { return }

    $head = Get-GitValue -Path $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    if (-not $head) { return }

    # Only the primary. A lane sitting behind the integration branch is ordinary -- it syncs
    # deliberately before it lands, and `lane status` is where that is read.
    if ($head -ne $integration.Primary) { return }

    $exists = Invoke-Git -Path $RepoRoot -Arguments @('show-ref', '--verify', '--quiet', ("refs/heads/{0}" -f $integration.Branch))
    if ($exists.Code -ne 0) { return }

    $contains = Invoke-Git -Path $RepoRoot -Arguments @('merge-base', '--is-ancestor', $integration.Branch, 'HEAD')
    if ($contains.Code -eq 0) { return }

    $behind = Get-GitValue -Path $RepoRoot -Arguments @('rev-list', '--count', ("HEAD..{0}" -f $integration.Branch))
    if (-not $behind) { $behind = 'some' }

    Add-Failure ("'{0}' is {1} commit(s) behind '{2}', so the documents here are not the ones the next reader sees. Sync before reading or writing them: Scripts/reach.ps1 lane sync -Primary" -f $integration.Primary, $behind, $integration.Branch)
}
