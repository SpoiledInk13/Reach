# Reach

A process for building software with coding agents, packaged as a Claude Code plugin.

It comes out of one project that got this badly wrong before it got it right: 1,077 decision records,
662,000 lines of documentation, 218 scripts and an 8,275-line gate, around software whose active
milestone was *"click a character and walk them somewhere"*. The generative defect was that nothing
was ever allowed to delete anything, so every artifact was append-only — including the ones written
to consolidate the others. What is here is what survived the rebuild.

## The four rules

Everything else is an implementation of these.

1. **Split work by who verifies it**, not by what it touches. Then nothing falls between the commands.
2. **The document is the record, and it is capped.** Caps are what force deletion. Git history is the
   why-trail; there are no decision records, no supersession notes, no dated corrections.
3. **No lane addresses another.** A lane that cannot proceed files a question in the document whoever
   answers it reads. That is the whole coordination protocol, and it needs no scheduler.
4. **Every guard has an observed failure path.** Break it on purpose, watch it go red, restore. A
   check whose failure has never been seen is decoration.

## What is here now

| | |
|---|---|
| `/reach:adopt` | replaces a repository's existing agent workflow by distilling it, not adding beside it |
| `scripts/Verify-Gate.ps1` | the gate: a driver that finds its checks, five generic, plus the project's own |
| `scripts/Verify-All.ps1` | runs the gate and every declared tier, and reports one verdict |
| `scripts/Prove-Gate.ps1` | proves each generic check can fail, fails for the right reason, and passes again |

The five generic checks are `DocumentCaps`, `ArchiveImmutable`, `ClaimsAreProven`, `DocLinks` and
`AdoptionCounts`. A project adds its own to `Scripts/gate-checks/`: one `.ps1` per check, defining one
function named for the file. A check is added when a real defect proves one is wanted, never
pre-emptively, and one that has never caught anything gets deleted.

Scripts are written to the PowerShell 5.1 subset, so the same gate runs on Windows PowerShell and on
`pwsh` anywhere — locally and in CI.

## Not here yet

The governance layer — capped document templates, the unit roster, the three verifier-split commands,
lanes and the unattended lane supervisor — is deliberately unwritten. It gets written against a real
second repository rather than against imagined ones, because building for shapes you have not met is
how a gate reaches eight thousand lines and still misses a file growing 85% under its own watch.

## Install

```
claude plugin marketplace add <this repo>
claude plugin install reach
```

To work on it: `claude --plugin-dir ./reach`, then `/reload-plugins` after changes.

## Proving it

```
pwsh scripts/Prove-Gate.ps1      # or: powershell -File scripts/Prove-Gate.ps1
```

Every control breaks one thing, requires the gate to go red **for that specific check**, restores, and
requires green again. The middle condition matters: a gate that goes red for the wrong reason is how a
check gets believed for years while testing nothing.

## Licence

MIT.
