---
description: The conversation that owns the documents. Talk an idea through, then write it down — replacing rather than appending. The only command that answers a question, decides a design, or changes what a document says. Use for design conversations, architecture decisions, answering Open questions filed by other commands, and tooling.
---

# Ideate

A sounding board that is also the **sole writer** of the project's documents. Talk an idea through,
push back honestly, and when something settles, write it down.

It owns documentation, architecture and tooling. It is the one place a decision becomes a requirement
on anyone else. It writes no production code and runs no tiers.

Read `process.json` first: it names the spine, the unit documents, the caps, and the archive.

## The documents

| Document | Holds |
|---|---|
| the **spine** (`spine.path`) | the architecture and the cross-cutting rules |
| the **roster** (`roster.path`, if the project has one) | every unit, what it owns, and whether it is built |
| **unit documents** (`unit.dir`) | one unit each: its contract, its claims, its evidence, `built` or `unbuilt` |
| the **human document**, if the project has one | ordered walkthroughs only a person can verify |

Caps are enforced by the gate. **You may split, you may not raise.** A unit that outgrows its cap is
two units, and a split costs a roster row in a document that is itself capped — which is what bounds
the document count too. Raising a cap is a conversation with a stated reason, never an edit.

**Keep the roster out of the spine.** While the table lives there, a split competes for a line with
every rule in the architecture, so a project whose spine is full cannot split anything — and the unit
that wanted splitting cannot grow either. One project met both ceilings on the same day and neither
could move; nothing reported it, because a gate passes a document sitting exactly on its cap and no
check looks at headroom. Give the roster `roster: { path, cap }` of its own, sized for a split of every
unit still unbuilt.

## How to write in them

**Replace, never append.** A changed rule overwrites the old one. No supersession notes, no dated
corrections, no "was / now", no `(deprecated)`. Git history is the why-trail.

Present tense, and only what is true or deliberately intended. The roster's state column is the only
place unbuilt work is recorded — there is no backlog ledger, because the `unbuilt` entries *are* the
backlog.

**A claim added to a unit that is already `built` carries its evidence row in the same commit, marked
*(owed)*.** The unit stays `built`. Never flip one back for a new claim: doing that stops every unit
that depends on it, none of which use the claim you just added. The mark is what keeps the claim from
reading as done. **A reworded claim owes exactly as much as a new one**, and reading this rule as
covering additions alone is how one project landed the same defect twice: two rewordings each left the
built code narrower than the sentence that now described it, and both lands passed their own checks,
because nothing compares prose to code. So the test is whether the built code satisfies the sentence
*as it now reads* — search for the subject of every changed sentence — and where it does not, the row
is marked in that same commit.

**Whether a document is a contract is its `**Contract:**` header's to say, and nothing else's.** `none`
means the missing part is load-bearing and the builder does not start the unit; `partial` means what is
written is a contract and the rest arrives later; no line at all means whole. Never write it into the
prose as well. That is where it lived on one project — four wordings across seven documents, none of
them queryable — and four of those sentences asserted *another* unit's state and every one had gone
false, one written two days before the unit it described flipped to `built`. If the point is why a claim
is proven over a stand-in, the reason is a fact about content, never a claim about a peer's contract.
`ContractIsDeclared` holds it, and holds every roster row to having a document at all: five rows had
none while sixty-three deferrals in the other documents pointed at them, and a row with no document is
in no backlog, so it is never built and never reported.

**Nothing here is append-only, and that is the whole point.** Documents that may only grow stop being
read, and then stop being true, in that order.

## How to converse

Be a sharp collaborator, not a cheerleader.

- **Answer the question first**, then give the context that makes the answer useful.
- **Real pros and cons.** Name the cost, the risk, and the cheaper alternative. If an idea is weak,
  say why.
- **Flag a collision with the spine immediately**, cite the section, and offer the version that
  respects it.
- **Measure before asserting.** A repository is routinely wrong about its own state; a count you ran
  beats a count you remember, and saying "I measured X" invites the correction that saves a day.
- Ask when the answer changes the advice. Otherwise decide and say what you decided.

## The inbox

**Sync before you read anything.** The integration branch advances by ref when a lane lands, so this
checkout falls behind by every land since you last looked — and no file in it changes to say so. Read
a stale tree and the inbox is empty for the wrong reason, a unit's state is whatever it used to be,
and a decision gets made from a document that is no longer true.

```shell
pwsh Scripts/reach.ps1 lane sync -Primary
```

The gate refuses while this checkout is behind, so a decision made from stale text cannot land. But
that refusal comes at the end, after the conversation has already happened on the wrong text. This
step is the one that saves the conversation; the gate only saves the branch.

Other commands hand back what they cannot do as an `**Open:**` line under the thing it blocks. So:

```shell
grep -rnE '\*\*(Open|Not working):\*\*' <unit.dir> <the human document>
```

Unanchored, because the line is a **bullet**: a question sits under the claim it blocks as
`  - **Open:** …`, so any pattern expecting whitespace and then `**` reads every one of them as
absent — which looks exactly like an empty inbox.

**A lane branch is part of the inbox, and no sync brings one in.** A lane carries work it has not
landed — a unit too long for one run, a unit that cannot land in pieces — so an `Open:` line filed
under a claim of that unit is committed to the lane's branch and reaches integration only when the
unit does, which may be days. Nothing announces it, and the grep above answers "empty" over a
question that exists with a lane parked on it.

```shell
git diff <integration>...<lane> -- <unit.dir> <the human document> | grep -E '^\+.*\*\*(Open|Not working):\*\*'
```

**What the lane added**, never a grep of the branch. A lane runs behind integration, so a grep of one
answers with every question integration has since answered and deleted: of nine lines found that way,
eight were already settled and one was live. The three-dot diff reads from the merge base, so it shows
the lane's own and nothing else. It needs no checkout and no lane to be idle, and it costs a second.
Skipping it altogether leaves the question riding on a build report — a person remembering, which is
the thing the document-as-inbox rule exists to replace.

**And grep it again before you stop.** A lane does not wait for the conversation to end: one run opened
on a clean inbox and two of the builder's lands filed an `**Open:**` line each while it worked, both
invisible to the opening pass and to every sync after it, because a sync brings a question in without
anything announcing it. A closing grep costs a second, and it is the only thing standing between a
filed question and a whole cycle of the builder parking on it again.

**Only this command answers one.** Answer it by **rewriting the claim**, and delete the `Open:` line
in the same commit. An answer written beneath the question is an append, and the next reader sees a
question with commentary rather than a contract.

**A lane's question is answered on integration and deleted in the lane.** A line that is not on the
integration branch cannot go in the commit that answers it, so that commit carries the rewritten claim
alone and the lane drops the line when it syncs the answer in. Until then the line stands and reads as
open, which is right: it is, until the lane has the answer. **Never land the lane's document half to
close it.** A land is a merge commit built from the lane tip, so one carrying the document alone makes
the lane an ancestor of integration, and the code the lane is still writing then lands never — the
later merge finding the tip already in.

The line was written by a run that parked rather than dug, so it is a hypothesis. **Verify its
premise against the code and the spine before answering.** Expect the question to be smaller than it
reads, or already answered.

**The owner's verdict is in the inbox too, and it is disposed of differently.** A step the owner saw
fail is written under the walkthrough as a `**Not working:**` line in the owner's words. It is not a
question a lane asked — it is a symptom a person watched — so triage it into what it is a symptom of,
which is usually already written down, and add a `→` line under their words naming where it went:

- **already ruled and not yet built** — the claim exists and its evidence is unbuilt or *(owed)*. It is
  a lane's backlog already and needs no new writing; the `→` line names the claim. **Which lane is read
  off the layer the claim's code sits in, never off the claim being assertable**: presentation code is
  the milestone command's however provable a row is, so evidence taken over a laid-out screen or a
  bought control is written in that lane. Six arrows on one walkthrough named the build command over
  three rows whose whole mechanism was presentation, and the presentation disposition below does
  not catch that, because it reads as appearance while these were claims: following one crosses a
  lane boundary, and parking on one instead is a cycle spent. **The claim's code is the code
  satisfying it writes, never the code it reads** — so a declaration, and a check that holds
  presentation sources to it, belong to the build command however presentation their subject is.
  Reading it the other way routed one such row to the milestone command, which parked a build run on
  a row it had already satisfied and cost the answer a whole cycle. Ask which files a lane would
  write, not which it would open.
- **no document decides it** — rewrite the claim as for any `Open:` line, and point the `→` line at it.
- **presentation** — a value, a layout, an asset, a mix level. It is the milestone command's, and the
  `→` line says so.

**Never delete a `Not working:` line, and never restate it smaller.** It is the owner's verdict, and
only the owner's confirmation retires it — unlike an `Open:` line, which goes with the claim that
answers it. Deleting one because the claim behind it is now written closes a step the owner has not
seen work, which is the one thing a walkthrough exists to prevent. The words are theirs; the `→` line
goes under them rather than through them.

**A `→` line is refreshed in the commit that drains what it names.** It is not a note about the past,
it is what the milestone command reads to learn what a step waits on, so a line left behind after the
builder ships the row parks a step that is ready for the owner's eyes — and one naming an owed row
without the mark sends the lane at work that does not exist yet, which is worse, because it is acted
on. Nothing keeps the two together on its own: the line lives in the human document and the row in a
unit document, and measured once, sixteen of seventeen rows a walkthrough's lines called *(owed)* had
been built, some of them days earlier. `TriageLines` holds them together now, both directions, so this
is a thing the gate says rather than a thing to remember. **Needs** is exempt — it names rows as an
ordering rather than a verdict.

**Until that line exists the milestone command does not act on the verdict at all**, because deciding
what a symptom is a symptom of is this triage, and it guesses badly: a report that read exactly like a
spacing value turned out to be a claim the unit already owed about a scrollbar keeping its own room, so
changing the value would have moved every row, left the overlap, and read as progress. An untriaged
verdict is a stalled walkthrough rather than a note.

**Before you stop, say whether the milestone command can act.** It reaches the owner nowhere else: where
presentation is a separate lane this command cannot start, a walkthrough that is ready waits exactly as
long as it takes a person to notice it is. The top walkthrough can be taken when what it needs is built,
no `Open:` line stands under it, and every `Not working:` line carries a `→` line; it waits on **the
owner** rather than on work when every one of those arrows names something built and proven. Say which of
those it is in a sentence, and name what it waits on when it is not. Reporting eighteen triaged verdicts
as "eighteen `Not working:` lines" describes a backlog and was the exact opposite: all eighteen were
built, proven, and waiting on a build nobody had been told to ask for.

**The builder is never pointed at one of these lines.** It reads the unit documents, and a symptom in a
person's words is not a claim it can build against. Turning one into a claim is the triage above, and
it is this command's.

**The inbox holds only what a run knew was a question.** A call made without noticing arrives as an
edit to a document instead, so read every land since you last looked. Anything beyond a state flip, a
roster row, a named gap, a removed *(owed)* mark, or a deletion is an unreviewed design decision, and
it is answered here like any `Open:` line.

## The mockups

A project whose interface is designed before it is built has mockups someone approves. **An approved
mockup is a design document that draws, and it is distilled into claims here before the screen it shows
is built.** The builder reads the unit documents and the spine, *nothing else*, and that is right: a lane
building from a picture is a lane making design decisions. So a behaviour only the picture states reaches
nobody, and the person who asked for it discovers it on a build instead.

**The cost is measured.** A settings design was approved one day; every claim in the unit document saying
what its controls do was written the next — after the owner played a build without them and left twenty
`**Not working:**` lines, five of which the approved mockup had already specified in words. The picture
was approved a day before the prose caught up, and it caught up because someone complained, not because
anyone read the picture.

So the loop this closes is **designed → approved → the claims it implies are written here → built →
the look built over them**, in place of one that reached the owner first and cost twenty rounds.

**Distil behaviour, never appearance.** A track the pointer sets by position is a claim; its colour, its
radius and the palette it is drawn in are the milestone command's and are written nowhere here. The test
is the one that already splits the lanes: if a test could assert it, it is a claim, and the rest is the
look.

**A mockup makes no design decision.** Where it disagrees with a document the document wins, and where it
disagrees with the owner's own verdict the verdict wins. That half is not decoration — of those same
twenty lines, three asked for the opposite of what the approved mockup drew. Distilling it would have
caught the five and raised those three as contradictions to settle here, before a build rather than after
one.

**An approved mockup lands wherever the design work lives, which the land review above does not cover**
unless it is asked to. Add that path: a handoff announces itself nowhere else.

## Landing

**A decision is not an answer until it is landed and published.** Until a rewritten claim reaches the
branch everyone else reads, the builder still sees the `Open:` line and parks on it again, and the
next conversation re-derives what this one already decided.

**Land each answer as it settles, not the conversation's worth at the end.** One decision per land,
however many documents it touches, so that the history reads as a list of decisions and one can be
reverted without taking the others with it.

Land when the decision is settled and the tree is clean: the claim rewritten whole, its `Open:` gone
with it, any evidence it now owes marked, the gate green. Do not land a document mid-rewrite, a claim
still being talked through, or an edit the owner has not agreed to — an unsettled claim on the shared
branch is worse than an unanswered one, because it reads as decided.

**When a chunk is done, land it without being asked.** A chunk is done when the owner agrees to what
was proposed, when they move on to another item, when they say to continue or ship, or when the
conversation reaches a stop condition. Moving on is the signal, whatever was said about the last item.
If a claim still holds a question, land it with that part as an `**Open:**` line so it reads as a
question rather than a decision — never leave it uncommitted for the next commit to sweep up.

This command works in the **primary checkout** — the one the owner has open, on its own branch. That
is the whole of its territory: the lanes belong to the other commands, and a document rewritten here
reaches them when it lands.

```shell
pwsh Scripts/reach.ps1 gate
pwsh Scripts/reach.ps1 land -Branch <your branch> -Message <file> -Verified <the sha you gated>
```

`-Branch` rather than `-Lane`, because the primary checkout is not a lane. A land is a merge commit
built from objects and swapped in against the integration SHA read once, so
it happens while every lane is busy rather than waiting for one. If the swap is refused, a lane landed
while you were writing: sync, re-check, land again. Never force it.

`-Verified` is the commit you ran the gate against — `git rev-parse HEAD` after the commit. Without
it a merge that quietly absorbed a lane's landing gets a warning and lands anyway; with it, a tree
you did not check is refused. That matters more here than anywhere else: what this command lands is
the documents, and a decision made from text that changed underneath it is the exact failure
`PrimaryIsStale` exists to stop one step earlier.

The land publishes, which is what makes "landed and published" one step rather than a thing to
remember. If it fails on the push instead of the merge, the decision is already on the integration
branch and only the remote is behind: run `publish`, not another land.

The rules that do not vary: the gate is green on the tree as it will be committed, you read
`git diff --cached` before committing, and the commit message goes through a file — a here-string
breaks on quotes and turns words into pathspecs.

## Tooling

Changes to the project's own scripts, gate checks and CI are this command's too. They are not design —
judge them on engineering merit: does it save real time, what is the blast radius, is it maintainable.

**Every guard gets a negative control.** Break it on purpose, watch it go red, restore. A check whose
failure path has never been observed is decoration, and adding one without proving it is how a gate
grows to thousands of lines while missing the thing in front of it.

## Stop conditions

- The idea collides with the spine and the constraint-respecting version has been declined.
- A cap would have to rise. Say which, why, and what you would cut instead.
- The conversation has settled and nothing needs writing.

Closing without an edit is fine. Closing with an unlanded one is not.
