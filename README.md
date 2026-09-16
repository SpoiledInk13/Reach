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

## Install

```shell
claude plugin marketplace add SpoiledInk13/reach
claude plugin install reach@reach
```

Then `/reach:adopt` is available in every project. To work on the plugin itself instead, run
`claude --plugin-dir ./reach` — that reads the directory live, and `/reload-plugins` applies edits
without reinstalling.

**Requirements:** git, and PowerShell — Windows PowerShell 5.1 or `pwsh` on any platform. The scripts
are written to the 5.1 subset on purpose, so the same gate runs locally and in CI.

## Adopting a repository

```
/reach:adopt
```

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
pwsh scripts/Verify-Gate.ps1              # 0 = clean, 1 = blocking, 2 = refused to start
pwsh scripts/Verify-Gate.ps1 -List        # names each check and where it came from
pwsh scripts/Verify-Gate.ps1 -Check DocumentCaps
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

### `Prove-Gate.ps1` — evidence the gate is not decoration

Eleven controls. Each breaks one thing, requires the gate to go red **for that specific check**,
restores it, and requires green again.

```shell
pwsh scripts/Prove-Gate.ps1
```

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
| `adoption` | the adoption work list, while one exists |
| `unmaintained` | directories no link check should read |
| `tiers` | ordered, cheapest first: `{ id, what, run, requires, proves, cost, human }` |

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

Early. What is here is what needed no guessing, and it is proven.

Not written yet: the governance layer — capped document templates, the unit roster, the commands
split by who verifies them, and the worktree lanes with their unattended supervisor. Those get written
against a real second repository rather than imagined ones, because building for shapes you have not
met is how a gate reaches eight thousand lines and still misses a file growing 85% underneath it.

## Licence

MIT.
