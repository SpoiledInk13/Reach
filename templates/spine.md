# <project> — architecture

<!--
    The spine. One document, capped, and it outranks every other document in the repository.

    It holds what binds ACROSS units. A rule that lives here is one that would be shattered by being
    folded into any single unit's document -- and that is the test for whether something belongs here
    rather than there.

    The cap is set from this document's own size plus a small margin, never inherited. Raising it is a
    conversation with a stated reason, never an edit. You may split; you may not raise.

    Delete these comments when you write the real document.
-->

## 1. The loop

The one sentence this project is measured against. What the software does, stated so that a decision
can be checked against it.

## 2. Layers

What may depend on what, and what may never. Name the direction of every dependency, because that is
the rule a gate check can be written against.

## 3. The contracts that cross everything

Rules that bind every unit. A pattern that binds every unit cannot survive being folded into one
unit's document, so it is lifted here instead — and when a new one is found, it goes here *before*
whatever prompted it is written down anywhere else.

## 4. Verification

Which tier catches what, and what each is blind to. The tier commands themselves live in
`process.json`; this says what each one is *for*, and names the class of defect that would survive
every tier — because that is the class you will ship.

## 5. Hard constraints

Things that are not negotiable, each with the reason. A constraint with no reason gets removed by
someone who cannot see why it was there.

## Roster

Every unit, its state and what it depends on, is in the roster `process.json` names.

<!--
    The roster is a table that grows by a row per unit, so it is its own capped document rather than
    a section here: a unit that outgrows its cap is split in two, a split costs a roster row, and
    while the row competes with the architecture for a line a full spine blocks every split.
-->
