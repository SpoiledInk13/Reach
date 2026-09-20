<#
    A triage line says what its claim is actually waiting on.

    The owner's verdict on a walkthrough step is their own words, and under it goes an arrow line
    naming where that symptom went. The milestone command reads those lines to learn what a step
    waits on, and acts on nothing it cannot see a line for -- so the line is not a note, it is the
    instruction.

    Nothing kept it true. The line lives in the human document and the row it names lives in a unit
    document, and no reader held the two together, so every drain by the builder left the line one
    step further behind. Measured once: sixteen of the seventeen rows a walkthrough's lines called
    *(owed)* had been built, some of them days earlier.

    Both directions, because each misleads differently. A line still calling a row *(owed)* parks a
    step that is ready for the owner's eyes. A line naming a row that is owed, without the mark,
    sends the lane at work that does not exist yet -- the worse of the two, because it is acted on.

    Only arrow lines. A walkthrough's **Needs** names rows too, as an ordering rather than a verdict,
    and holding that to a mark would force a blocker to be restated as one.
#>
function Test-TriageLines {
    $human = Get-Field $Process 'human' $null
    if (-not $human) { return }

    $docRelative = Get-Field $human 'doc' ''
    if (-not $docRelative) { return }
    $doc = Join-Path $RepoRoot $docRelative
    if (-not (Test-Path -LiteralPath $doc)) { return }

    $unit = Get-Field $Process 'unit'
    $unitDir = Join-Path $RepoRoot (Get-Field $unit 'dir' 'Docs/systems')
    if (-not (Test-Path -LiteralPath $unitDir)) { return }

    $evidence = Get-Field $Process 'evidence'
    $noun = Get-Field $evidence 'noun' 'scenario'
    $heading = Get-Field $evidence 'heading' (($noun.Substring(0, 1).ToUpper() + $noun.Substring(1)) + 's')

    # ------------------------------------------------------------------ what each row says of itself

    $owedByName = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $unitDir -Filter *.md -File)) {
        $text = Read-TextUtf8 $file.FullName
        $block = [regex]::Match($text, ('(?ms)^##\s+' + [regex]::Escape($heading) + '\s*$(.*?)(^##\s|\z)'))
        if (-not $block.Success) { continue }
        foreach ($m in [regex]::Matches($block.Groups[1].Value, '(?m)^\|\s*`([a-z0-9][a-z0-9-]*)`\s*\|(.*)$')) {
            $owedByName[$m.Groups[1].Value] = $m.Groups[2].Value.Contains('*(owed)*')
        }
    }
    if ($owedByName.Count -eq 0) { return }

    # ------------------------------------------------------------------ and what the lines say of them

    # A triage line is a block: it opens with the arrow and runs to the next blank line, so a row
    # named on its fourth physical line belongs to it. Reading physical lines finds only the names
    # that happen to sit beside the arrow, which is most of them and never the ones that matter --
    # a control that moved a name onto a continuation line passed over exactly that mistake.
    $blocks = @()
    $current = $null
    foreach ($line in (Read-TextUtf8 $doc) -split "`r?`n") {
        if ($line -match "^\s*$([char]0x2192)") { $current = $line; continue }
        if ($null -eq $current) { continue }
        if ($line.Trim().Length -eq 0) { $blocks += $current; $current = $null; continue }
        $current = $current + ' ' + $line
    }
    if ($null -ne $current) { $blocks += $current }

    foreach ($block in $blocks) {
        # Called pending: the mark follows the name, which is the form every triage line uses.
        foreach ($m in [regex]::Matches($block, '`([a-z0-9][a-z0-9-]*)`,\s*\*\(owed\)\*')) {
            $name = $m.Groups[1].Value
            if ($owedByName.ContainsKey($name) -and -not $owedByName[$name]) {
                Add-Failure ("{0} calls {1} '{2}' *(owed)*, and its row is built. Refresh the line in the commit that drains it -- the milestone command parks on a step this says is waiting." -f $docRelative, $noun, $name)
            }
        }

        # Named at all while its row is owed. A name already carrying the mark above satisfies this.
        foreach ($m in [regex]::Matches($block, '`([a-z0-9][a-z0-9-]*)`')) {
            $name = $m.Groups[1].Value
            if ($owedByName.ContainsKey($name) -and $owedByName[$name] -and
                $block -notmatch ('`' + [regex]::Escape($name) + '`,\s*\*\(owed\)\*')) {
                Add-Failure ("{0} names {1} '{2}' without *(owed)*, and its row is owed. Say so on the line -- the milestone command acts on what a line calls built." -f $docRelative, $noun, $name)
            }
        }
    }
}
