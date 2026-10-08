---
description: Implement and prove everything that is not presentation, reading the unit documents as the backlog. Runs until nothing is left that can be built without an answer. Use to build unbuilt units, satisfy owed claims, or work through the roster.
argument-hint: "[builder]"
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

1. **Read each document's `**Contract:**` header before its claims.** It is the document saying whether
   it is one. **A unit declaring `none` is not started**, however much depends on it: the missing part is
   load-bearing, writing it is the ideate command's, and whatever waits on the unit waits on that writing
   rather than on this command. Say so and pick the next; do not build a fragment to show progress. A unit
   declaring `partial` is built as far as it is written, and the unwritten part is neither improvised nor
   filed as a question — there is no claim to file one under, and the declaration is already the record
   that it is owed.
2. Read the roster. Take the earliest unit with a claim you can build, or the next unbuilt claim inside
   a unit already in progress. If the project has a human-verified document, what its top entry needs
   comes first: a walkthrough waiting on its units leaves that command with no work. **A dependency
   being `unbuilt` does not block a claim** — what a claim reads from a unit that does not exist yet is
   stood in for at a named boundary, and the document says which under *Waiting on other units*. A
   dependency blocks a claim only when the thing it would stand in for is the thing the claim is about.
   Wait for `built` dependencies instead and a roster stalls whole: on the project this was written for
   it left fourteen of sixteen unbuilt units unreachable, three of them permanently, because they
   depended on each other in a cycle — while every one of the twenty-two already built had been built
   over stand-ins, two of them over units still unbuilt that day.
3. **A built unit's *(owed)* claim is work like any unbuilt one**, and it holds up a dependent only
   when that dependent's own work needs it. An owed claim never makes its unit anything but `built`.
4. If a claim cannot be built as written, file it as a question and build around it. **A unit document
   is a contract; where it cannot be built against, that is a question and not something to improvise
   past.**
5. **When a unit is finished, wholly blocked, or as far as this run takes it, commit it and pick again
   from step 1** — up to three units, then run every tier once over the tip and land the batch.
   Parking a claim blocks the claim, not the run.
6. **A land is a green slice, never a finished unit.** What lands is whatever claims are proven and the
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
pwsh Scripts/reach.ps1 lane claim build      # before anything else touches the lane
pwsh Scripts/reach.ps1 lane sync build       # bring the integration branch in first
pwsh Scripts/reach.ps1 all                   # from inside the lane
pwsh Scripts/reach.ps1 land -Lane build -Message <file> -Verified <sha>
pwsh Scripts/reach.ps1 lane release build    # when the run stops, for whatever reason
```

**Claim the lane before you touch it, and release it when you stop.** One agent per lane is a lock,
not a convention: the unattended supervisor takes it, and a run started by hand takes the same one, so
neither can start beside the other and a check on the lane sees either. The claim names this
session's own process, so a session that ends without releasing frees the lane when it ends. **A
refused claim means another agent is in the lane — stop, and say who holds it; never work around it.**
A run the supervisor started finds its supervisor already holding the lane, which is its claim made,
and its release leaves the supervisor's lock alone.

`-Verified` is the commit whose tree you actually ran the tiers against. If the merge would produce a
different tree, the land is refused — because something arrived while you were working and what you
proved is not what would land. Sync, re-run, land again.

A land also publishes. If it fails on the push rather than on the merge, the merge already happened:
run `publish` to retry the push. Landing again would report nothing to land and read like a fault.

## The integrator and the builders

A lane that declares `builders` in `process.json` runs as one **integrator** — the lane itself, the only
one holding the scarce harness (an editor, an emulator, a device, a warm database) and the only one that
lands — and any number of **builders**, `<lane>-1`, `<lane>-2`, …, seeded as lanes of their own, which
have no harness. This command with no argument is the integrator and `builder` makes it a builder;
everything else here binds both, except where this section says otherwise. The split pays wherever most
proofs need no harness: one project measured nine in ten that way, while its one lane spent half its wall
clock waiting on serial sweeps — and with two builders, most of what it proved came through them.

**Every lane takes a unit before writing in it**, `reach.ps1 builders take <unit>`, and one lane holds a
unit at a time, so two lanes never edit one document or one unit's code at once. A refused take is not a
question: take the next unit. A run starts by continuing the units its lane already holds
(`builders held`), and **drops one** (`builders drop <unit>`) only when nothing in it is left that the
lane can build *and* its work in it is on integration — dropped earlier, the next holder writes over a
document whose last edit has not landed. A take is the lane's, not the run's, and crosses runs.

**A builder takes what needs no harness**: a claim whose evidence runs in a tier `process.json` does not
mark `"builders": false`, and the code under it. **Whatever the harness must see is the integrator's.**
That is not a question either: the builder leaves it, and drops the unit once only such claims remain in
it, so the integrator can take it. `reach.ps1 all` in a builder reports those tiers as the integrator's
and never runs them.

**A builder proves with `reach.ps1 all` green over its committed tree, then marks that tip ready**,
`reach.ps1 builders ready`, **run inside the builder** — it marks the checkout's HEAD, and from anywhere
else it marks the wrong one. **It never lands and never touches integration**: where the integrator
would verify and land a batch, a builder proves and marks ready, and a half-done unit is committed to its
branch and simply not marked. `land` refuses a builder outright.

**A builder starts by asking whether its last tip came back**, `reach.ps1 builders rejection`, and fixes
that before anything else. A rejection names why — a tier the sweep reddened, a conflict — and marking
the fixed tip ready supersedes it. A conflict is fixed by syncing integration and proving again, the
other side having landed by then.

**The integrator integrates first** — at the start of every run and at every batch boundary — because a
builder waits on nothing else. `reach.ps1 builders pending` lists the ready tips; merge each into the lane
as `git merge --no-ff --no-edit refs/ready/<builder>`, that exact form, which is what the supervisor
counts as the run's work. A merge that conflicts is aborted and sent back,
`reach.ps1 builders reject <builder> -Reason <why>`. Then one sweep runs over everything merged and the
integrator's own commits, and green lands it all as one land, a builder's tip counting as one of the
batch's three (**Committing**). **A red sweep is localised before anything lands**: reset the lane to
before the merges — they are unlanded, so nothing is lost — sweep each tip alone over that, land the
green and reject the red with the row it failed. Then the integrator builds what only it can.

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

**Name what the archive holds on it.** Where the repository has one, much of what a builder parks on
the owner already ruled there, so grep the subject over the archive `process.json` names and name any
record that decides it in the line. That is a pointer, never an answer: you build nothing from a
record, because whether it still holds is the ideate command's call, and naming it turns that call from
a search into a read.

**A finding with no obvious home is still an `Open:` line, never a heading of your own.** The inbox
matches a closed set of markers, so a new bold lead-in files into nothing however apt it reads. Where a
measurement is what blocks a claim, **carry the numbers into the line** rather than a path to them: the
file they were read from is usually untracked and per lane, and does not survive the lane. A reading that
only says something got slower or larger is never one — it is dismissed or traced by the lane whose
instrument took it, and filed nowhere.

A `built` unit may hold one only under a claim it owes; a question raised by a proven claim goes under
the unbuilt claim it blocks.

Then park that claim and carry on with anything that does not depend on the answer. **The document is
the only place a question goes** — never memory, never the report alone. A question anywhere else is a
decision nobody reviews.

**It reaches the inbox from the lane branch, not from the land.** Commit the line with the rest of the
unit: a unit that cannot land in pieces holds one for as long as it takes, and the inbox reads what the
lane added for exactly that reason. A question left uncommitted in the lane's working tree is a question
nobody has, and one carried in the final report alone is a person remembering. The line is the design
command's to answer and **this lane's to delete** — the answer lands as a rewritten claim alone, and the
next sync brings it in. Do not land the document half on its own to close it: that makes the lane an
ancestor of integration and the unit's code lands never.

**The sync does not delete the line for you.** The answer rewrites the claim beside the line rather than
the line, so the merge is usually clean and the line survives it: one lane synced three answers in and
kept all three. So after every sync read what arrived, `git log ORIG_HEAD..HEAD --grep "Answers <lane>'s Open"`,
and delete each line it answers in the commit after the merge. **Land no tip still carrying one**: a line
kept goes back to integration with the land, reading as open over an answer already written, and the next
run parks on it again.

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

**Run the subset while you work and the whole set at the land**, where the runner can name one. The slow
tier is usually the one that boots the project, so running only the evidence you are writing costs minutes
against tens of minutes. It never stands in for the land's run: checks in one run share state a subset
never reaches, so the defect that is green alone and red together is invisible to it. And **a partial run
records nothing a whole run would** — a per-check baseline taken over a subset is taken against a
different set, so recording it disarms the guard by the way the tier is most often run.

**Record what the slow tier costs and how long the harness had been up**, appended rather than replaced,
wherever a run reuses a warm process. How often that tier runs is what decides whether its cost is worth
paying, and a set getting slower reads the same whether the set grew or the process did — a warm harness
grows with the work it has done, not with the clock, so a restart on a schedule restarts an idle one and
misses a busy one. Two runs at different ages tell those apart; one number never can.

**Write the evidence before or with the code, never after.** Evidence written afterwards certifies
what you built rather than what was wanted, and the tell is that it reads like a description of the
implementation.

**Prove the negative control.** Break the thing on purpose once and watch the test go red, then
restore it. A guard whose failure path has never been observed is decoration.

Mark what proves each claim with the project's evidence mark, so the gate can hold the document to the
tests.

## Finishing

When a unit's contract is fully implemented and proven:

1. Flip its `**State:**` to `built` and update the roster row, wherever `process.json` puts it.
   **When a check reads the state, the flip is a change to what that check asserts, so it goes in
   before verification, never after.** A test that holds built units to more than unbuilt ones passes
   over a tree without the flip and has verified nothing about the unit, and a gate reading documents
   cannot see the difference. Anything committed after verification, the flip included, is verified
   again. One flip made two minutes after a green run left the integration branch red on ten fields.
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

**A land carries up to three units, verified once.** The whole check set runs before every land, and
where that costs tens of minutes, landing one unit at a time spends most of a day re-proving a set that
had not changed. Build up to three — **independent ones wherever the backlog allows it**, which is what
makes a red locatable — each its own commit, then run every tier once over the tip and land the three
as **one merge**. The subset run gives per-unit feedback in the meantime, so the whole run confirms
rather than measures for the first time.

**Three, not more.** The saving is `1 − 1/k`: three captures two thirds of everything batching could
ever give, five captures four fifths, and what grows with the batch is the cost of a red — more
candidates to localize, and a longer gap in which the shared branch moves under you, which brings the
re-run over the combined delta.

**The batch is one land because it is one verification.** Reverting the merge gives back all three, and
that is paid on purpose: they were only ever proven together, so reverting one would leave the shared
branch on a tree nothing measured and would need re-proving anyway — and three merges off one run
would make two of them claim a verification that never ran. The history stays a list of lands; a land
is now up to three units.

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
