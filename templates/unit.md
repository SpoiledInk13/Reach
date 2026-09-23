# <unit name>

**State:** unbuilt

<!--
    The shape on this page is not decoration: the gate reads it.

    `**State:**` must be exactly `built` or `unbuilt`, alone on its line. Binary on purpose. A unit
    that is half implemented stays `unbuilt`, and the tests are the record of partial progress.

    The evidence table's heading is whatever process.json's `evidence.heading` says -- by default the
    capitalised plural of `evidence.noun`, so `scenario` gives `## Scenarios`. Each row's first cell is
    a backticked lowercase-kebab name, and that name is what a test marks.

    Delete these comments when you write the real document.
-->

## Contract

What this unit is responsible for, in a few sentences. What it guarantees to everything else, and
what it deliberately does not do.

## Claims

Each claim is something the unit does, stated as a fact, in the present tense. A claim is a contract:
it is written here first, and the code is built against it -- never the other way round.

- A claim, stated plainly.
- Another claim.
  **Open:** the question that blocks this claim, and the fact that forces it -- a file and line, a
  measured number, the spine section it collides with. No options, no recommendation. Only the ideate
  command answers one, and it answers by rewriting the claim and deleting this line.

## Dependencies

The units this one reads. Names only.

Being listed here does not mean waiting: what this unit reads from one that is not built yet is stood
in for at a named boundary, and the line below says which, so a reader can tell a stand-in from a gap.
A dependency blocks a claim only when the thing it would stand in for is the thing the claim is about.

**Waiting on other units, and named rather than quietly missing:** what is stood in for, whose it is,
and which claims are proven over it.

## Evidence

| Name | Proves |
|---|---|
| `the-thing-happens` | the claim it demonstrates |
| `the-other-thing` | *(owed)* — a claim added after this unit was built, with nothing proving it yet |

<!--
    *(owed)* goes in the SECOND cell and opens it. It is how a claim added to a built unit is recorded
    without flipping the unit back to unbuilt -- which would stop every unit that depends on this one,
    none of which use the claim that was just added.

    The gate refuses the mark in three places: on an unbuilt unit, on a row that evidence already
    proves, and as a way of holding an Open question on a unit that owes nothing. It removes in the
    same commit that proves the row.
-->
