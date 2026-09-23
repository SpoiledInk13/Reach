---
description: Implement and prove everything that is not presentation, reading the unit documents as the backlog. Runs until nothing is left that can be built without an answer. Use to build unbuilt units, satisfy owed claims, or work through the roster.
---

# Build

Implements unbuilt work from the unit documents, proving each thing at every tier the project
declares. **A run is not one unit.** It carries on until the roster has nothing left it can build
without an answer.

It owns every layer but one. **The boundary is the layer**: `process.json`'s `human.layer` belongs to
the human-verified command — the look, and the code that draws it — and everything else is yours. A
project naming no `human.layer` gives you all of its code.

> **If an outcome can only be verified by looking at it or listening to it, it is presentation by
> definition.**

That rule says what a **claim** is, and so what belongs in a unit document and owes proof. It does not
say who writes the code. A claim whose code sits in that layer is a claim like any other — written in a
unit document, proven by a tier — but the command that owns the layer is the one that satisfies it and
writes that proof. A defect in that layer is its to repair however assertable it is, and never returns
here.

Read `process.json` first: it names the unit documents, the evidence mark, the tiers and their
commands.

## What it reads

The unit documents, and the spine. Nothing else. **The `unbuilt` entries are the backlog** — there is
no ledger, no queue, no gap folder, and re-reading the roster is what grooms it.

The spine binds everything you write. Where a unit document and the spine disagree, the spine wins and
the unit document wants correcting — say so rather than coding around it.

## Picking work

1. Read the roster. Take the earliest unit with a claim you can build, or the next unbuilt claim inside
   a unit already in progress. If the project has a human-verified document, what its top entry needs
   comes first: a walkthrough waiting on its units leaves that command with no work. **A dependency
   being `unbuilt` does not block a claim** — what a claim reads from a unit that does not exist yet is
   stood in for at a named boundary, and the document says which under *Waiting on other units*. A
   dependency blocks a claim only when the thing it would stand in for is the thing the claim is about.
   Wait for `built` dependencies instead and a roster stalls whole: on the project this was written for
   it left fourteen of sixteen unbuilt units unreachable, three of them permanently, because they
   depended on each other in a cycle — while every one of the twenty-two already built had been built
   over stand-ins, two of them over units still unbuilt that day.
2. **A built unit's *(owed)* claim is work like any unbuilt one**, and it holds up a dependent only
   when that dependent's own work needs it. An owed claim never makes its unit anything but `built`.
3. If a claim cannot be built as written, file it as a question and build around it. **A unit document
   is a contract; where it cannot be built against, that is a question and not something to improvise
   past.**
4. **When a unit is finished, wholly blocked, or as far as this run takes it, commit it, land it**, and
   pick again from step 1. Parking a claim blocks the claim, not the run — that is the difference
   between a run that lands one unit and a run that lands three.
5. **A land is a green slice, never a finished unit.** What lands is whatever claims are proven and the
   checks are green over; the unit keeps its state, so a slice of an unbuilt one lands `unbuilt` and the
   tests are the record of how far it got. Most units are bigger than one run and land several times:
   one of sixty claims took eight lands over two days and was `unbuilt` for seven of them. Read "finish"
   anywhere here as the state flip and the rule inverts into a deadlock — no unit larger than a run may
   be started, because none can be flipped in one, so four were once reported as buildable work that
   could not be landed when three were smaller than units already built and the fourth was nine claims
   proven of fifteen.

## Where it works

If the project declares lanes, work in this command's lane — its own worktree on its own branch, with
its own build cache — and never in the primary checkout. Two agents sharing one checkout share one
index they both stage into and one working tree each edits under the other; that is the collision
lanes exist to remove, and it is also why a lane tests exactly the tree that lands rather than a copy
of it.

```shell
pwsh Scripts/reach.ps1 lane sync build       # bring the integration branch in first
pwsh Scripts/reach.ps1 all                   # from inside the lane
pwsh Scripts/reach.ps1 land -Lane build -Message <file> -Verified <sha>
```

`-Verified` is the commit whose tree you actually ran the tiers against. If the merge would produce a
different tree, the land is refused — because something arrived while you were working and what you
proved is not what would land. Sync, re-run, land again.

A land also publishes. If it fails on the push rather than on the merge, the merge already happened:
run `publish` to retry the push. Landing again would report nothing to land and read like a fault.

## Questions

A claim you cannot build as written — thin, contradicted by the spine, contradicted by what the code
actually does — is a question, and **this command never answers one**: not by guessing, not by asking
the owner mid-run, and not by writing down an answer the owner gives during the run. A build run that
holds a design conversation starts improvising, and the answer it reaches never gets checked against
the spine.

File it as one `**Open:**` line directly under the claim it blocks, stating the question and the fact
that forces it — a file and line, a measured number, the claim or spine section it collides with.
**No options and no recommendation.** A question from a run that parked rather than dug is a
hypothesis, and its proposed fix goes stale faster than its problem.

A `built` unit may hold one only under a claim it owes; a question raised by a proven claim goes under
the unbuilt claim it blocks.

Then park that claim and carry on with anything that does not depend on the answer. **The document is
the only place a question goes** — never memory, never the report alone. A question anywhere else is a
decision nobody reviews.

**It reaches the inbox from the lane branch, not from the land.** Commit the line with the rest of the
unit: a unit that cannot land in pieces holds one for as long as it takes, and the inbox reads what the
lane added for exactly that reason. A question left uncommitted in the lane's working tree is a question
nobody has, and one carried in the final report alone is a person remembering. The line is the design
command's to answer and **this lane's to delete** — the answer lands as a rewritten claim alone, the
next sync brings it in against the line, and the line goes in that merge. Do not land the document half
on its own to close it: that makes the lane an ancestor of integration and the unit's code lands never.

What you may decide yourself is what the contract is indifferent to: names, internal structure, which
of two mechanisms satisfy it identically. A choice that would change what the contract *says* is a
question, however confident you are.

## Building

**Write the code against the document, then consult the archive — in that order, always.** A port that
begins by reading the old implementation reproduces the old architecture with better formatting, which
is the failure the adoption was for. What `adopt` moved to `Reference/` is a parts bin and not a
specification: mine it for edge cases, for values somebody measured once and would have to measure
again, and for the mechanics of something fiddly — never for structure. A project that adopted nothing
has no archive, and this is then simply the rule that the document is what you build against.

**Respect the spine's hard constraints without being asked.** They are the project's rather than any
one claim's, so a unit document does not restate them and a claim that never mentions one is still
held to it. A constraint you find you cannot build against is a question like any other (above), not a
thing to route around quietly.

## Proving

A thing is not built until every tier has run and passed, and **you ran them**:

```shell
pwsh Scripts/reach.ps1 all
```

A tier that could not run is not a tier that passed. Say so plainly; a green summary covering less
than yesterday is worse than a red one.

**Write the evidence before or with the code, never after.** Evidence written afterwards certifies
what you built rather than what was wanted, and the tell is that it reads like a description of the
implementation.

**Prove the negative control.** Break the thing on purpose once and watch the test go red, then
restore it. A guard whose failure path has never been observed is decoration.

Mark what proves each claim with the project's evidence mark, so the gate can hold the document to the
tests.

## Finishing

When a unit's contract is fully implemented and proven:

1. Flip its `**State:**` to `built` and update the roster row in the spine.
2. **Delete the mechanism the code now expresses** — *how* a thing is done, which a reader can now
   read in the code. This is not optional tidying; it is the only thing keeping the documents from
   growing back. **Never delete a rule, a reason, or a constraint on a unit not yet built:** code
   shows what it does, not why, nor what the next unit must respect. If you cannot tell which a
   sentence is, leave it.
3. **Finishing only deletes.** Beyond the state flip, the roster row, a named gap, and removing an
   *(owed)* mark your test now proves, you add nothing and reword nothing. A sentence added to a
   claim, or a claim compressed into new words, changes what the contract says — that is a question,
   however small.

A unit that is only partly built stays `unbuilt`. The rule is binary and the tests are the record of
partial progress. **Once built, a unit stays built:** a claim added later arrives *(owed)*, and
proving it removes the mark rather than flipping anything.

The gate refuses a `built` unit that names no claim it does not owe, names one nothing proves that it
does not owe, keeps *(owed)* on one already proven, or carries an `Open:` line while it owes nothing.

## Committing

One commit per unit. Check `git diff --cached` before committing — a pathspec on `git add` does not
scope the commit — and put the message in a file rather than inline.

**One land per unit, too: land each before starting the next, rather than banking a run's worth.** A
land carrying three units cannot give back one of them, and that is the ceiling on a long run, not its
line count. Landing as you go also keeps each merge small, so the shared branch moving under you costs
one unit's reconciliation instead of the whole run's.

**Work that outlives the run is committed too, on the branch the run works on — never on a branch of
its own.** Some units cannot land in pieces and take longer than one run, and the branch the run works
on is what carries one across: the next run brings the integration branch in and continues on top of
it, the unattended runner reads the commit as the progress it was rather than halting on a run that
looks empty, and the branch says from outside the lane what is in flight. Say the state in the
message — what is proven, what is left. A branch of its own does none of that and is read by nothing:
eighty-four green scenarios once sat in a lane's index with the side branch three commits behind them,
invisible to the sync, to the runner and to every read anyone made, and a single checkout in that
worktree would have discarded them.

## Stop conditions

Stop and report rather than pushing through when:

- **no unit on the roster** has a claim left you can build without an answer — not merely the one you
  were working on. Land what was built, and the questions with it;
- two value-only attempts have failed. The mechanism is the wrong shape, and a third sweep is the
  failure mode rather than the fix;
- **you have started remembering the documents instead of re-reading them.** At every unit boundary,
  re-read the next document and the spine sections it names off disk, and re-run the gate rather than
  carrying the green from the unit before. Answering *what does the contract say?* from memory is the
  tell that a run is past its useful length, well before anything says the context is full. **A
  measurement never crosses a unit boundary;**
- **you are at a boundary and could not reach a green landable slice of the unit you would start.** The
  test is one claim proven and the checks green, not the unit finished — a unit you cannot finish is a
  unit you land twice, and stopping over one is how a whole roster reads as blocked. Stop only where the
  next unit's first claim is out of reach: its dependency is unbuilt and cannot be stood in for, or the
  run has no room for one claim and its test. **Work already in flight is not at a boundary**, and
  forfeits nothing only because it is committed first — stopping over a unit that cannot land in pieces
  means committing it, not parking it;
- a tier cannot be run, for any reason.
