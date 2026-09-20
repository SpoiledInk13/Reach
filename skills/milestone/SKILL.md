---
description: Build the layer only a person can verify — how the software looks, sounds and feels — one walkthrough at a time, hand the owner a real build, and delete the walkthrough when they confirm it. Use for UI, visual and audio work whose verdict is the owner's eyes and ears.
---

# Milestone

Takes the top walkthrough from the project's human-verified document, builds the presentation it
needs, hands the owner a real build, and deletes the walkthrough when they confirm it.

It owns what cannot be asserted:

> **If an outcome can only be verified by looking at it or listening to it, it is presentation by
> definition.**

That is real work, not a thin shell: layout, type, colour, motion, light, effects, and how every cue
sounds in the mix. What *can* be asserted belongs to the build command — including presentation code
whose behaviour a test can drive, like a control's focus order or a backend's substitution.

**A project with no `human: true` tier does not need this command.** If everything it produces can be
asserted, the build command owns all of it, and adding walkthroughs would be ceremony.

## What a walkthrough is

**One sentence describing a cold start, whose definition of done is that sentence happening on a real
build with no developer shortcuts.** If a piece of work cannot be stated that way, it is not a
walkthrough — it is a unit, and it belongs in the unit documents.

That shape exists because per-bullet proof cannot see an assembly failure. A milestone can close with
a dozen green bullets over a feature wired at one of its two start-up sites, or over thousands of
green cases with the mechanism broken four ways. One sentence, end to end, on the real artifact, is
what catches that.

## What it reads

The human-verified document — an ordered list, capped. The top entry is the active one. There is no
roadmap and no archive: a verified walkthrough is **deleted**, not moved.

Also the documents of the units the entry needs, and the spine. They say what exists and what it does;
this command decides only how it presents, directed by whatever mockups or direction the owner has
given.

## Where it works

In its own lane if the project declares one — its own worktree, on its own branch, with its own build
cache — never in the primary checkout, and never in the build command's lane. The artifact you hand
over is produced there, from exactly the tree that lands.

```shell
pwsh Scripts/reach.ps1 lane sync milestone
pwsh Scripts/reach.ps1 all
pwsh Scripts/reach.ps1 land -Lane milestone -Message <file> -Verified <sha>
```

One agent per lane. Two in one share its index and its cache, which is the collision lanes exist to
remove — and it is why this command does not work in the same units the build command is working in,
even when the walkthrough needs them.

A land also publishes. If it fails on the push rather than on the merge, the merge already happened:
run `publish` to retry the push, not another land.

## What it decides, and what it never does

**It builds presentation, and sets the values that tune it.** Styles, layout, effects, lighting, token
values, a cue's loudness and the mix, which existing asset a row names, and the value of an existing
setting's default. A new row, key or mechanism is never a value. Presentation draws state and holds
nothing the rest of the system does not, so the look is built over what the units already publish.

**It takes direction from the owner's mockups.** What works in a mockup is taken. Where one
contradicts a document — an option a screen offers that no row provides, a control the kit lacks —
the document wins and the conflict is a blocker, never built from the picture. A mockup makes no
design call, however clearly it draws one. **Which framework or component system the software is
built on is among what it never decides** — that is a unit's claim — so a mockup drawn before a unit
moved is how a lane reaches for the framework it left, and a set of drawings that states a contract
of its own is worth catching before it is read. A surface the mockups have not drawn is not a
blocker: how a surface looks is this command's to decide, and one no drawing covers is that same
decision taken without one. A drawing is the owner's cheaper review, never a surface's permission
to be built — blocking on an absent one turns an accelerator into a gate, and where the same lane
draws and builds it is a gate on itself. An older set of drawings is still never read for it.

**Everything else goes back as a question.** It never builds what it finds missing and never makes a
design call. Each of these is a blocker:

- a unit the entry needs that is `unbuilt`;
- a `built` unit missing a behaviour or a quantity the look needs;
- a choice no document makes — what a screen offers, what a press does, what a conflict resolves to;
- a job no approved dependency covers, or one that cannot work for a stated, evidenced reason.

A blocker is not worked around, stubbed, restated smaller, or decided because the answer seems
obvious — not even with an answer the owner gives mid-run, which gets no pass against the spine.

## Blockers

File each as one `**Open:**` line directly under the walkthrough it blocks, stating what is missing
and the fact that shows it — the unit, the claim, a file and line. **No options and no
recommendation.** It goes under the walkthrough rather than under a unit's claim because a `built`
unit cannot carry an `Open:` line, and because answering one means writing the missing claim, which
returns the work to the build command's backlog.

Then carry on with any part of the walkthrough that does not depend on it. When nothing left can be
built without an answer, land what was built, with the blockers, and stop.

## Running one

1. **Read the walkthrough as written**, and the documents of what it needs, off disk. Never restate it
   smaller because part of it is hard; a sentence that cannot happen as written is a blocker.
2. Check what it needs. Anything `unbuilt`, or carrying an `Open:` line the entry depends on, is a
   blocker — file it and stop, rather than working in the same units as the build command.
3. Build the presentation. Compose existing components rather than hand-rolling primitives, name
   tokens rather than literals, and use an approved dependency before making what it already provides.
4. **What its own code does that can be asserted, it asserts**, in the same commit. Anything
   assertable it finds missing beneath it is a blocker, not a test to write here.
5. Produce the real artifact — the project's most expensive tier, the one that builds what ships.
6. **Drive it first.** Take the build through the walkthrough's sentence the way a user would, with no
   developer shortcuts, and capture what it looks like at each step. Read every capture against the
   sentence and the mockups, and fix and rebuild what is wrong. Name anything you could not drive, and
   name what no capture shows — how it sounds is the owner's to hear.
7. **Hand it over and stop.** The owner runs the build. Verification happens on the real artifact or
   not at all: the development environment is not what ships, and a walkthrough that only works there
   has not happened. **A capture never closes this gate, and neither does a description of what you
   saw.**

## The owner's verdict

A step the owner reports as not working is written as one `**Not working:**` line under the
walkthrough, in the owner's words, and the next run reads it before anything else. It does not become
a smaller claim, and it does not close until the owner says that step works.

**An untriaged line is not work.** The ideate command triages each into what it is a symptom of and
writes a `→` line under the owner's words; until that line exists, this command does not act on the
verdict at all. It never decides what a symptom is a symptom of — that is the triage, and guessing at
it is how a lane spends a day breaking more than it fixes. **The report reads like the fix and is
not:** a report that read exactly like a spacing value turned out to be a claim the unit already owed
about a scrollbar keeping its own room. Changing the value would have moved every row, left the
overlap, and read as progress.

Then read the `→` line and do what it says:

- **it names a claim** — not this command's, at any point, however small the fix looks;
- **it says presentation** — this command's, and it now names the specific thing to change;
- **there is none yet** — carry on with the rest of the walkthrough, exactly as with a blocker.

**Say in the hand-over which lines this artifact still carries**, which are untriaged, and what each
triaged one waits on. Recording a verdict is not addressing it, and handing over something that
repeats a fault without saying so is what makes this command read as ignoring the owner.

## Closing one

Only on the owner's confirmation, for the walkthrough as stated, and only when it carries no `Open:`
or `Not working:` line:

1. **Delete it from the document.** No archive, no retrospective, no completed-history roll. Git
   history is the record.
2. Nothing else changes. A design detail the shipped look now expresses is the ideate command's to
   delete.

## Committing

One commit per coherent piece of the look. Land blockers the moment they are filed — a blocker nobody
can see is not filed.

## Stop conditions

- Nothing left in the walkthrough can be built without an answer. Land, and stop.
- A fix has shipped twice with no movement in the symptom. **The break is upstream of both**, and a
  third blind fix is the most expensive move available. Produce evidence of which path actually runs
  before touching it again.
- You are about to claim a step works without the owner having run it.
