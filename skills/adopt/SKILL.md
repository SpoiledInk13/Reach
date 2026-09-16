---
description: Replace a repository's existing agent workflow with this one, by distilling what is already there rather than adding beside it. Use when a project is adopting reach for the first time, or when its CLAUDE.md and commands have stopped being read.
---

# Adopt

A repository adopts this process because the one it has is not working. So this **replaces** what is
there. It does not add a section beside it, and it does not leave the old instructions in place to be
read alongside the new ones — two workflows in one repository means the failed one is still live, and
the reason the first one failed is usually that nothing was ever allowed to be deleted.

Replacement is only safe because nothing is lost. Every claim in the existing files is either carried
to a named destination or archived whole, and the archive is read-only and gate-enforced. **You never
delete a lesson. You move it, or you keep it where it can be found.**

This is a conversation, not a scaffolder. There is a classification step the owner signs off, because
the judgement is made dozens of times and a claim removed by mistake looks exactly like one that was
never there. Do not run it unattended, and do not offer to.

---

## 0. Which of the two jobs this is

**Check for `process.json` first.** It decides everything below.

**If there is none, this is a first adoption** — steps 1 to 7.

**If there is one, this repository has already adopted, and you are topping it up.** Adoption happens
once; reach keeps changing, so a repository set up against an earlier version is missing whatever
arrived since — and nothing about that is visible, because the gate passes and a mechanism that was
never wired in simply never fires.

In that case, **do not tag, do not archive, and do not re-classify anything.** Those steps replace a
workflow, and this repository has already replaced its own; running them again would archive the
structure you are meant to be completing and re-sort claims that are already claims.

Instead, measure the gap:

```shell
pwsh Scripts/reach.ps1 audit
```

**If `Scripts/reach.ps1` is not there, that is gap zero and you fix it before anything else** — copy
`templates/reach.ps1` from this plugin into the repository as `Scripts/reach.ps1`, then run the audit
through it. A repository that adopted before the shim existed cannot run the command that would tell
it what it is missing, and the missing shim is one of the things it would say.

The audit names every gap, why it matters, and the fix. Show the list, say which ones you propose to
fill, and fill only what the owner agrees to. Then set `"reach"` in `process.json` to the installed
version, so the next audit measures from here.

A top-up writes; it never replaces. If filling a gap would overwrite a document the owner has written
in — a spine, a unit document — say so and stop rather than doing it.

## 1. Read what is there, and measure it

Before proposing anything:

- `CLAUDE.md`, `AGENTS.md`, and any equivalent at the repository root
- `.claude/` — commands, skills, agents, settings, hooks
- any `docs/` or `Documentation/` tree, and the README
- how the project is actually built and tested: scripts, task runners, CI workflows
- the branches that exist, whether pull requests are used, and how many people commit

Report line counts, not impressions. A repository is routinely wrong about its own state, and every
later step depends on this being measured rather than remembered.

## 2. Decide how much of the process this repository can take

Two layers, and the split is **team size, not language**.

**The universal layer** — every repository gets this. The tier contract and a single verdict, the
gate with its checks, and the traps. It touches no branching and imposes no document structure.

**The governance layer** — capped documents, the unit roster with `built`/`unbuilt`, evidence marks,
the `Open:` inbox, and the split of work by who verifies it. This assumes **one owner who answers
every question**. On a repository with several committers, the sole-writer rule is a bottleneck and
the `Open:` inbox is a ticket queue nobody owns; pull requests and review already do that job, and
they do it better because they have humans attached.

On a repository you do not own, "replace" means replace **how the agent is instructed and verified**.
The team's own workflow — pull requests, review, CI — is not yours to replace, and the universal layer
is the whole of what you propose. Say this out loud rather than quietly scoping down.

## 3. Tag, then archive

Before a single file changes:

    git tag -a pre-reach-<yyyymmdd> -m "the working tree before adopting reach"

Then `git mv` every file being replaced into the archive directory — `Reference/` by default — whole
and unedited. Sources are **archived, never deleted**. The archive is what makes step 4 safe, and
`ArchiveImmutable` keeps it honest afterwards.

## 4. Classify every claim, and show the table before writing

Go through the archived files claim by claim. Each one gets a destination or an explicit decision to
drop it, and you present the whole table before writing anything:

| What it is | Where it goes |
|---|---|
| A platform or engine gotcha — *"this API silently no-ops in editor mode"* | the spine, or the project's trap list |
| A rule about how the software behaves — *"weapons are never auto-equipped"* | a **unit document, as a claim** — which immediately shows whether anything proves it |
| How to build, test, run, deploy | the `tiers` array in `process.json` |
| A coding standard the model would follow from the surrounding code anyway | dropped — keep only what is counterintuitive |
| An existing command | kept if it earns its place, dropped if the new structure covers it |
| Anything you cannot place | **stays, flagged.** Never dropped because it did not fit |

The last row is the one that matters. A claim you cannot classify is a claim you do not understand
well enough to delete.

Converting behaviour rules into claims is the most valuable thing adoption does, and it is also the
uncomfortable part: a document full of confident prose becomes a roster where most rows have nothing
proving them. That is not the adoption going wrong. That was already true.

## 5. Write the documents and `process.json`

Start from the plugin's templates rather than from a blank page — the gate reads the shape of these
documents, and that contract lives nowhere else:

| Template | Becomes |
|---|---|
| `templates/process.json` | `process.json` — every field something reads |
| `templates/spine.md` | the architecture document |
| `templates/unit.md` | the first unit document, and the pattern for the rest |
| `templates/walkthroughs.md` | the walkthrough list, if anything here needs a person to judge it |
| `templates/reach.ps1` | `Scripts/reach.ps1` |

If the repository has a corpus still to distil — documents whose content is going into unit documents
over the coming weeks rather than today — write an adoption map, set `adoption` to its path, and give
every source a row with its line count. Without the field, `AdoptionCounts` reads nothing and a
stalled distillation stays invisible. If there is no such corpus, leave the field out entirely rather
than pointing it at a file that does not exist.

**Caps are set from each document's own size plus a small margin** — never inherited from another
project. A cap only does its work while it pinches.

### The branching lanes require

Lanes are what let a command run its tiers against exactly the tree that lands, and let a long
unattended run happen without touching the checkout the owner is working in. They need one thing from
the repository, and it is not negotiable:

- an **integration branch checked out nowhere** — that is what lets a land advance it by ref while
  every lane is busy, and it is the difference between landing and waiting;
- the **primary checkout on its own branch**, the owner's and ideate's;
- **each lane a worktree** on its own long-lived branch.

On a repository that currently commits straight to its default branch, that is four commands and
`/reach:adopt` runs them with the owner's agreement:

```shell
git branch <integration>            # if it does not exist
git checkout -b <primary>           # the owner's checkout stops being on the integration branch
Scripts/reach.ps1 lane seed build
```

On a repository you do not own, do none of this. Set `integration.mode` to `push`: lanes still isolate
the work, and landing stays with the reviewers.

Then copy `templates/reach.ps1` from the plugin into the repository as `Scripts/reach.ps1` and commit
it. The plugin's scripts live at a path carrying its version number, so it moves on every update and
nothing may hard-code it; that file resolves the installed plugin at run time and is what the owner
and CI both invoke. Without it, every command in the README names a path that will be wrong by the
next release.

**The tiers are the project's, the contract is not.** Cheapest first. Ask what the expensive tier
actually is — the thing that compiles, bundles or ships for real — because a project whose tiers stop
at unit tests has a whole class of defect no tier can see. Ask what cannot always run, and give it a
`requires`. Ask whether any tool here exits 0 having done nothing, and if so give that tier a `proves`
pattern; that failure is common and it reads as green.

A tier marked `human` is never run. If an outcome can only be verified by looking at it or listening
to it, nothing that runs may claim otherwise.

## 6. Prove it, or it did not happen

Three things, in order, and report the actual output of each:

1. `Scripts/reach.ps1 prove` — the reach checks go red on purpose and green again.
2. **A negative control on this repository.** Break one real claim — flip a unit to `built` with
   nothing proving it — watch `Scripts/reach.ps1 gate` go red, restore, watch it go green. A gate that
   has never been observed failing on *this* repository is decoration here regardless of what it does
   elsewhere.
3. `Scripts/reach.ps1 all` — every tier runs. A tier reported `SKIPPED` is not a pass; say so.

## 7. Finish the replacement

The old files are in the archive and their content is in its new homes, so remove them from where
they were being read. Leaving a stale `CLAUDE.md` section beside the new structure is the exact
failure this whole procedure exists to avoid.

Then say plainly what was dropped and why. The owner signed off on a table in step 4; the closing
report is what lets them check that the table is what actually happened.

---

## What this must never do

- Run without the step 4 sign-off.
- Delete anything that is not already in the archive.
- Invent a tier. If nobody knows how the project is verified, that is the finding — report it.
- Report a pass when a tier was skipped.
- Leave two workflows in the repository.
