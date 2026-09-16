# Reach

**A process for building software with coding agents, packaged as a Claude Code plugin.**

Agents are fast enough that the bottleneck stops being *writing* and becomes *knowing what is true*.
Which claims in your docs are still accurate. Which were ever implemented. Which of your guards would
actually catch anything. Reach is a small set of mechanisms that keep those answerable as a project
grows, and a gate that fails the build when they stop being.

---

## The problem it was built for

One project accumulated 1,077 decision records, 662,000 lines of documentation, 218 scripts and an
8,275-line verification gate — around software whose active milestone was still *"click a character
and walk them somewhere."*

Nothing in it was wrong when it was written. The generative defect was that **nothing was ever allowed
to delete anything**, so every artifact was append-only, including the ones written to consolidate the
others. The domain model ran to 9,067 lines; one entry in it was seventy lines long, carried
twenty-five citations, described four retired mechanisms, and contained a dated correction to itself.
The gate, meanwhile, could not see a core file grow 85% under its own watch, because most of its
checks had never been observed failing.

Reach is what survived rebuilding that from scratch. It is deliberately small, and it stays small
because deleting is built into it.

## The four rules

Everything else here is an implementation of these.

1. **Split work by who verifies it**, not by what it touches — your judgement, the machine, or your
   own eyes. Then nothing falls between the roles.
2. **The document is the record, and it is capped.** Caps are what force deletion. Git history is the
   why-trail: no decision records, no supersession notes, no dated corrections, no `(deprecated)`.
3. **No lane addresses another.** Anyone blocked files a question in the document whoever answers it
   already reads. That is the whole coordination protocol, and it needs no scheduler.
4. **Every guard has an observed failure path.** Break it on purpose, watch it go red, restore. A
   check whose failure has never been seen is decoration.

## Is this for you?

Honest answer, because the fit is uneven:

| | |
|---|---|
| **Good fit** | One owner, greenfield or actively growing, a backlog of fairly independent pieces, and enough agent throughput that you have stopped being able to verify everything by reading it |
| **Partial fit** | A team repository. Take the gate and the tier contract; skip the document governance — pull requests and review already coordinate humans, and they do it better |
| **Bad fit** | A small utility, or a repository that is mostly maintenance. The roster has nothing to say and the ceremony costs more than it returns |

It makes no assumptions about your language, your test framework, or your branching model.

## How to use it

**Requirements:** git, and PowerShell — Windows PowerShell 5.1 or `pwsh` on any platform. The scripts
are written to the 5.1 subset on purpose, so the same commands run locally and in CI.

### 1. Install the plugin — once, in a terminal

```shell
claude plugin marketplace add SpoiledInk13/Reach
claude plugin install reach@reach
```

The first command registers the catalogue and installs nothing; the second installs from it. The
default scope is **user**, so `reach` is then available in every project you open. Use
`--scope project` to commit it to one repository's `.claude/settings.json` for collaborators, or
`--scope local` for yourself in one repository only.

```shell
claude plugin list                  # what is installed, and whether it is enabled
claude plugin details reach         # its components and what they cost in context
claude plugin update reach          # after a new release
claude plugin uninstall reach@reach
```

### 2. Adopt a repository — once per project, inside Claude Code

```
/reach:adopt
```

Plugin skills are namespaced, so it is always `/reach:adopt` and never `/adopt` — which means it can
never shadow a command your project already has. If a skill does not appear, run `/reload-plugins`.

This is the conversation described below. It ends with `process.json`, a `Scripts/reach.ps1` you
commit, and a gate you have watched fail.

### 3. Work — the loop, inside Claude Code

Three commands, split by **who verifies the work**. That split is the whole design: it is why nothing
falls between them, and why none of them can quietly do another's job.

```
/reach:ideate        decide, and write it down
/reach:build         implement it, and prove it
/reach:milestone     make it look and sound right, and hand it over
```

| | Owns | Reads | Verified by |
|---|---|---|---|
| `/reach:ideate` | the documents, the architecture, the tooling | everything | **your judgement**, in conversation |
| `/reach:build` | everything that can be asserted | the unit documents | **the machine** — every tier |
| `/reach:milestone` | how it looks, sounds and feels | the walkthroughs | **your eyes and ears**, on a real build |

A normal week: **`/reach:ideate`** to decide what a piece of the system *is* and write the contract;
**`/reach:build`** to implement it until nothing is left that it can build without an answer;
**`/reach:milestone`** when there is something a person has to look at. Then back to ideate with
whatever the other two could not answer.

**Only `/reach:ideate` ever answers a question.** When build or milestone hits something it cannot do —
a claim contradicted by the code, a choice no document makes — it does not guess, and it does not ask
you mid-run. It writes one line into the document that blocks it:

```markdown
- Rooms reheat from the corridor they open onto.
  **Open:** `Thermal.cs:88` mixes across every shared edge, not just open ones. Which is the contract?
```

That line is the entire coordination protocol. There is no queue, no ticket system and no scheduler.
`/reach:ideate` finds them with one grep, answers by **rewriting the claim**, and deletes the line in
the same commit — so the answer lands where the next run already reads, rather than in a thread nobody
opens again.

**`/reach:milestone` is optional.** If everything your project produces can be asserted, `/reach:build`
owns all of it and walkthroughs would be ceremony. You need it when there is an outcome only a person
can judge.

### 4. Lanes — where the work actually happens

A lane is a persistent **worktree** on its own branch, with its own build cache. `/reach:build` and
`/reach:milestone` each work in one, and never in the checkout you have open.

```shell
pwsh Scripts/reach.ps1 lane seed build     # create the worktree and branch, and warm it
pwsh Scripts/reach.ps1 lane status         # every lane: branch, lock, dirt, how far ahead or behind
pwsh Scripts/reach.ps1 lane sync build     # bring the integration branch in
pwsh Scripts/reach.ps1 land -Lane build -Message msg.txt -Verified <sha>
```

Lanes remove the two collisions that come from two agents sharing one checkout — one index they both
stage into, and one working tree one edits while the other is mid-task. They also mean a command runs
its tiers against **exactly the tree that lands**, where a lane that merely mirrored your source would
be testing something else.

That requires one thing of the repository, and `/reach:adopt` sets it up:

- the **integration branch is checked out nowhere**, so a land advances it by ref while every lane is
  busy — this is the difference between landing and queueing;
- your checkout sits on **its own branch**;
- each lane is a **worktree** on its own long-lived branch.

A land is always a merge commit built from objects and swapped in with a **compare-and-swap** against
the integration SHA read once. Read it twice — once to merge, once to swap — and the swap can succeed
against a commit you never merged, silently discarding whatever landed in between. Pass `-Verified`
with the commit you actually ran the tiers against and the land is refused outright if the merge would
produce a different tree.

On a repository you do not own, set `integration.mode` to `push`: lanes still isolate the work, and
landing stays with the reviewers.

### 5. Unattended — one lane, running itself

```shell
pwsh Scripts/reach.ps1 run build            # until a run commits nothing
pwsh Scripts/reach.ps1 run build -Status -Follow    # from another terminal
pwsh Scripts/reach.ps1 run build -Stop      # finishes the run in flight, then stops
```

Each run is a **new agent process**, not another turn in one session. That is the point: several of
`/reach:build`'s stop conditions are *"this session has run long enough to stop trusting its own
memory of the documents"*, and only a fresh process answers them. It halts when a run commits nothing,
which means everything buildable is blocked on a question for `/reach:ideate`.

> **This runs the agent with permission prompts disabled**, which is the only way an unattended loop
> gets past its first tool call. It is **off unless you ask for it** — set `"unattended": true` on the
> lane — and the setting is printed in the ledger on every run. Use it on a lane whose worktree you
> own, and read `Logs/reach-lane/<lane>/` afterwards.

`-SelfTest` checks the decision, the guards and the renderer in seconds. `-DryRun` runs one whole
iteration against the real lane with a trivial prompt in place of the command — it exists because the
self-test cannot see the loop, and in the original every guard passed on the first real invocation
before it died three lines into the loop body.

### 6. Verify — any time, in a terminal or from CI

```shell
pwsh Scripts/reach.ps1 gate         # the gate alone      0 clean · 1 blocking · 2 refused to start
pwsh Scripts/reach.ps1 all          # gate + every tier   0 pass · 1 fail · 3 something was skipped
pwsh Scripts/reach.ps1 prove        # the plugin's own negative controls
```

Anything after the verb passes straight through:

```shell
pwsh Scripts/reach.ps1 gate -List               # name every check and where it came from
pwsh Scripts/reach.ps1 gate -Check DocumentCaps # run one
pwsh Scripts/reach.ps1 all -Tier A              # run one tier
```

`Scripts/reach.ps1` is written into your repository by `/reach:adopt`, and it exists because the
plugin's scripts live at a path carrying its version number — that path moves every time the plugin
updates, so nothing may hard-code it. The file resolves the installed plugin at run time. Set
`REACH_ROOT` to a checkout of this repository to run a change before publishing it.

### Working on the plugin itself

```shell
claude --plugin-dir ./Reach
```

That reads the directory live with no install, and `/reload-plugins` applies edits mid-session.
Install is for *using* reach; `--plugin-dir` is for *changing* it — an installed copy is a snapshot
pinned to a version and will not see your edits.

## What `/reach:adopt` does

A repository adopts this because the setup it has is not working. So adoption **replaces** what is
there rather than adding beside it — two workflows in one repository means the failed one is still
being read, and "we never deleted anything" is usually why the first one failed.

Replacement is safe because nothing is lost. It is a distillation, not a rewrite:

1. **Read and measure** what exists — instructions, commands, docs, how the project is really built.
2. **Decide how much applies.** On a repository you do not own, it replaces how the *agent* is
   instructed and verified, and leaves the team's own workflow alone.
3. **Tag, then archive.** Every file being replaced is `git mv`'d into an archive directory, whole.
4. **Classify every claim to a named destination — and show you the table before writing anything.**
   Platform gotchas become traps; behaviour rules become claims with evidence attached; build
   invocations become tiers; boilerplate the model already follows is dropped. Anything that cannot
   be placed **stays, flagged** — a claim you cannot classify is one you do not understand well
   enough to delete.
5. **Write `process.json`** — the parameters below.
6. **Prove it**, with the control suite and a real negative control on your repository.
7. **Finish the replacement**, and report what was dropped.

It is a conversation with a sign-off step, not a scaffolder. It will not run unattended, by design:
the judgement is made dozens of times, and a lesson deleted by mistake looks exactly like one that
was never there.

The uncomfortable part is step 4. A document full of confident prose becomes a roster where most rows
have nothing proving them. That is not adoption going wrong — that was already true, and is most of
the value.

## What you get

### `Verify-Gate.ps1` — the blocking gate

A driver that **finds** its checks instead of listing them: one `.ps1` per check, defining one
function named for the file, discovered by reading two directories — the five that ship here, and
your own. Adding a check never edits the driver.

| Check | Fails when |
|---|---|
| `DocumentCaps` | a document outgrows its line cap, or nothing was measured at all |
| `ArchiveImmutable` | the archive is edited, renamed or pruned — additions are fine |
| `ClaimsAreProven` | a unit is marked built with claims nothing proves; evidence names a claim no document makes; an `*(owed)*` mark sits where it should not; a built unit holds a question it does not owe |
| `DocLinks` | a maintained document links to something that no longer exists |
| `AdoptionCounts` | a recorded line count stops matching its file, so a stalled adoption stays visible |

```shell
pwsh Scripts/reach.ps1 gate
pwsh Scripts/reach.ps1 gate -List
pwsh Scripts/reach.ps1 gate -Check DocumentCaps
```

### `Verify-All.ps1` — the gate plus every tier, one verdict

Your tiers are yours. The **contract** between them is not:

- cheapest first, so red arrives in seconds rather than minutes;
- a non-zero exit is never a pass — and neither is every zero, so a tier that has been bitten by a
  tool reporting success having recompiled nothing declares a `proves` pattern its output must match;
- a tier that **could not run** is reported `SKIPPED` and the run exits **3**. It is never folded
  into a pass: a green that quietly covers less than yesterday is worse than a failure, because it is
  a failure you will not go looking for;
- a tier marked `human` is never run. If an outcome can only be verified by looking at it or
  listening to it, nothing that runs may claim otherwise.

### `Prove-Gate.ps1` and `Prove-Lanes.ps1` — evidence none of it is decoration

Twenty-two controls across two suites, run together:

```shell
pwsh Scripts/reach.ps1 prove
```

**Eleven gate controls.** Each breaks one thing, requires the gate to go red **for that specific
check**, restores it, and requires green again.

**Eleven lane controls.** Each breaks one assumption landing depends on and requires the refusal to
come from the guard it names — the integration branch being checked out, a tree nobody verified, a
lane on the wrong branch, a supervisor driving a lane from inside itself, a second holder of the lock.
Landing advances a shared ref from objects while other work may be arriving, so it is the most
dangerous code here and gets the most controls.

All three conditions matter. Red proves the check can fire; *red from the named check* stops a check
being believed for years because something else was failing; green-after-restore proves the red was
caused by the break rather than by something ambient.

## `process.json`

One file at your repository root. Everything reads it.

| Field | Means |
|---|---|
| `spine` | `{ path, cap }` — the one architecture document and its line cap |
| `unit` | `{ noun, dir, cap }` — what you call a unit of the system, where its documents live, their cap |
| `evidence` | `{ noun, mark, search, files, heading }` — what proves a claim, and how it is marked |
| `caps` | any other document → its cap |
| `archive` | the read-only directory replaced files move into |
| `checks` | where your own gate checks live (default `Scripts/gate-checks`) |
| `human` | `{ doc, noun }` — the walkthrough document `/reach:milestone` reads. Omit it if nothing needs a person to judge it |
| `adoption` | the adoption work list, while one exists |
| `unmaintained` | directories no link check should read |
| `tiers` | ordered, cheapest first: `{ id, what, run, requires, proves, cost, human }` |
| `integration` | `{ branch, primary, mode, remote }` — where lanes land. `mode` is `objects` or `push` |
| `lanes` | `[{ name, branch, worktree, command, warm, unattended }]` — `warm` takes `{ run }` or `{ copy }` |

```json
{
  "project": "example",
  "spine":    { "path": "Docs/ARCHITECTURE.md", "cap": 600 },
  "unit":     { "noun": "system", "dir": "Docs/systems", "cap": 500 },
  "evidence": { "noun": "scenario", "mark": "// scenario:", "search": ["Tests"] },
  "archive":  "Reference",
  "checks":   "Scripts/gate-checks",
  "tiers": [
    { "id": "A", "what": "pure logic",       "run": "npm test",        "cost": "~2s" },
    { "id": "B", "what": "integration",      "run": "npm run e2e",     "requires": "docker info", "cost": "~40s" },
    { "id": "C", "what": "the real artifact","run": "npm run build",   "proves": "compiled \\d+ modules" },
    { "id": "D", "what": "the owner's eyes and ears", "human": true }
  ]
}
```

**Set every cap from the document's own size plus a small margin.** Never inherit a number from
another project — a cap only does its work while it pinches, and raising one is a conversation with a
stated reason, never an edit.

## Writing your own checks

Drop a `.ps1` into the directory `checks` names. The filename is the check name and it defines one
function called `Test-<filename>`:

```powershell
# Scripts/gate-checks/MigrationsAreOrdered.ps1
function Test-MigrationsAreOrdered {
    # $RepoRoot, $Process, Get-Field, Read-TextUtf8, Get-LineCount are all in scope.
    Add-Failure "0042 runs before 0041. Renumber it, or the deploy applies them out of order."
}
```

Two rules keep this from becoming the eight-thousand-line gate it replaced:

- **Add a check when a real defect proves one is wanted**, never pre-emptively.
- **Prove its failure path before you trust it**, then delete it if it never catches anything again.

## Status

Early, and honest about which parts have been through a fire.

**Proven:** the gate and its five checks, the tier contract, the lane and landing guards, and the
supervisor's decision about whether a run did anything — twenty-two controls, each watched to fail for
its own named reason and pass again, by a script you can run.

**Written, not yet weathered:** the four commands. They are a distillation of a process that ran daily
on one large project for months, but their generic form here has not yet been through an adoption end
to end. Expect the first repository that adopts to find the seams — that is what a 0.x is.

**Deliberately absent:** nothing structural now. What is missing is mileage — this has not yet driven a
real project end to end, and the first repository that adopts will find seams. That is what a 0.x is.

## Licence

MIT.
