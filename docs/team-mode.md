# Team mode — designed, not built

Nothing here exists. This is a design for letting two to five developers share one reach repository,
written down because the reasoning cost more than the code would, and recorded so a later decision
starts from it rather than from scratch.

**It ships as its own skills.** `/reach:ideate`, `/reach:build`, `/reach:milestone` and `/reach:adopt`
stay exactly as they are, and the single-developer path never pays for a mechanism it does not use. A
team installs additional skills alongside them, and `adopt` asks which shape the repository wants.
That is the constraint every decision below is made under: if something can only be done by changing
the four, it does not go in.

## The boundary: teams that land, not teams that review

`README.md`'s fit table currently rates a team repository a partial fit — "take the gate and the tier
contract; skip the document governance" — and `skills/adopt/SKILL.md` explains why: the governance
layer "assumes one owner who answers every question."

That advice is right for the wrong reason. The line is not team *size*, it is **how work reaches the
shared branch**:

- A team that **lands** — every developer's agent lands its own verified work onto the integration
  branch — can use the governance layer, once the mechanics below are remote-correct.
- A team that **reviews** — every change goes through a pull request — should not. Review already
  coordinates the humans, with humans attached, and the governance layer beside it is a second
  workflow in one repository, which is the failure `/reach:adopt` exists to prevent. Set
  `integration.mode` to `push` and take the universal layer alone.

If this is built, that is the distinction the fit table should draw.

## Mechanics

### Per-developer branches

`process.json` gains `integration.namespace`: `"none"` (today, unchanged) or `"who"`. Under `"who"`,
`integration.primary` becomes `<who>/working` and each lane's branch `<who>/build`, `<who>/milestone`.
The integration branch is never namespaced — it is the shared one by definition.

**Identity is derived, never configured**: `$env:REACH_WHO`, then `git config reach.who`, then the
local part of `git config user.email`. No second config file, and no registry to go stale when
somebody leaves.

Developer-first (`amelia/build`, not `build/amelia`) deliberately: `build/amelia` cannot coexist with
a legacy `build` ref, because git would see a directory/file conflict, and that breaks every
repository already on reach 0.7.

The reason this is worth doing is **backup**, not collision-avoidance. Collisions were already solved
by splitting the publish (shipped, see `Invoke-ReachPublish`), which is why same-named private
branches in different clones are now invisible to each other. Namespacing earns its place because a
lane's in-progress work should survive a dead laptop, and today it exists on exactly one disk.

### Remote-correct landing

Nothing in `scripts/` fetches. Every ancestry and staleness decision compares two *local* refs, so on
a team a teammate's land is discovered only as a push rejection — after the local merge is permanent
and not rolled back. The fix reorders the land:

1. Fetch narrowly: `+refs/heads/<branch>:refs/remotes/<remote>/<branch>`. No remote is still a
   legitimate local-only repository; an *unreachable* remote refuses and changes nothing.
2. `$old` is `refs/remotes/<remote>/<branch>`, read once.
3. `merge-tree --write-tree` against that base — unchanged code, new base.
4. `-Verified` keeps its exact meaning and finally gains teeth: "something arrived since you ran the
   tiers" now includes someone else's machine.
5. `commit-tree`, touching **no ref**.
6. **The push is the compare-and-swap**: `git push <remote> <new>:refs/heads/<branch>`, plain and
   non-forced. It succeeds only if the remote is still at `$old`; anything else is a non-fast-forward.
   Not `--force-with-lease`, which permits rewriting when the expectation matches — never wanted here.
7. Only on success does the local ref move. It becomes a cache, not an authority.

The state this removes is the worst one in the current design: a refused push leaves a permanent local
merge and prose telling a human to reconcile. Afterwards, a refused push leaves a dangling commit
object and nothing else, and the retry is re-running the same command.

`PrimaryIsStale` then compares against the remote-tracking ref as well as the local one. **The gate
still does not fetch** — it runs in CI, offline, and once per supervisor iteration, and a verdict that
depends on the network is not reproducible. `lane sync` fetches, because its name promises a side
effect.

## Governance

One line, one table, one column, one field — and nothing else.

| Where | What |
|---|---|
| the spine, under the title | `**Steward:** <handle>` |
| the spine, before the roster | an `## Areas` table: `\| Area \| Owner \|` |
| the spine, the roster table | an `Area` column |
| each walkthrough entry | `**Eyes:** <handle>` |

The `**Steward:**` line is the switch. A spine without one is a solo project and every skill takes
today's path unchanged.

**Two scopes of ownership, both durable, both read from documents.** The steward owns spine sections
1–5, the Areas table, roster rows and ordering, `process.json`, caps, scripts and gate checks — the
cross-cutting rules, which are exactly what a second writer can break without conflicting. An area
owner owns every unit document in that area.

**Work selection** becomes: take the earliest unbuilt unit *in an area you own* whose dependencies are
built. Two builders never pick the same unit **by construction** — no claim, no lease, no race,
nothing to go stale. This is the decision the whole design turns on, and it is why ownership beat the
alternative: a transient `Held by` claim needs stale-claim rules, a held-twice check, and a
release-on-park rule, and ownership removes the collision instead of detecting it.

An unowned area is a question, not a free-for-all. Taking one means giving it an owner first — a
one-line edit landed before the work — so claiming collapses into the ownership mechanism rather than
adding a second one, and `-Verified` gives that land atomicity for free.

**The `Open:` inbox** gains nothing. An addressee would violate "no lane addresses another" and
duplicate what the roster already says. Instead: a question is answered by the owner of its unit's
area, and an answer that would change anything outside that area is the steward's. Questions are
**pulled, not pushed**, which is the actual answer to "a ticket queue nobody owns".

**The unreviewed-decision detector** fires on every teammate's legitimate work as written, and a
detector that fires on everything gets switched off, taking the real detection with it. It was never
about the *size* of a change — it was about whether something that may not decide, decided. A land is
reviewed if authored by the steward, or by the owner of the area of the unit whose document it
touches.

**The milestone verdict** belongs to the entry's Eyes. `**Not working:**` gains no author, because only
one person may write it. Two sign-offs means two walkthroughs, not two signatures. Confirmation is
still not recorded in any document — the deletion *is* the confirmation — but the commit that deletes a
walkthrough names the confirmer, which makes "git history is the record" true rather than aspirational.

**Caps change nothing.** Two writers wanting spine lines is the same pressure as one writer wanting
them twice, arriving sooner; and two lands that individually fit but jointly exceed a cap produce a
tree that was never gated, so `-Verified` already refuses the second.

**Roster conflicts stay conflicts.** One row per file would destroy the ordering, the cap, and "one
document that outranks every other" — the three properties the roster exists for. Area ownership means
two people are nearly always on different rows, so a conflict there means they touched the same row,
which is the collision surfacing at the only moment it can be resolved correctly.

One new gate check, `RosterAreas`, failing when: a steward is named but there is no Areas table, no
Area column, or no roster table at all; ownership exists with no steward; a roster row names an area
the table does not list; or the table lists an area no row names. Each owes a negative control.

## Rejected, with reasons

This is the most useful part on a second reading.

- **Transient claims** — a `Held by` column, `refs/reach/claims/*`, any lease, TTL or heartbeat.
  Ownership removes the collision; a lease adds a scheduler and a clock, and reach has neither.
- **`process.local.json` or any second config file.** Identity is derived, worktree paths are already
  relative and per-machine, and `unattended` should be a command-line switch. A permanent uncapped
  second file makes every bug report start with "what does your local file say?".
- **An addressee on `Open:` lines.** Violates "no lane addresses another", and manufactures the ticket
  queue that `adopt` already names as the failure mode.
- **A `**Confirmed by:**` record on walkthroughs, or a people registry in `process.json`.** A
  completed-work roll with a signature. `git log` holds it for free.
- **An author-matching gate check.** Needs author-to-handle heuristics that fail on a rename, fires on
  every legitimate steward edit, and is pre-emptive — add it the first time two people actually
  rewrite one claim.
- **A cross-machine "who has develop checked out" guard.** The corruption `Get-WorktreeFor` prevents is
  per-clone, so a cross-machine version protects against nothing. Expect it to be proposed; refuse it.
- **Fetching inside the gate**, `git pull` anywhere, `--force-with-lease`, a retry loop inside `Land`,
  and ticket or issue integration of any kind.
- **Unattended lanes on a shared branch.** Recommend `unattended: false` wherever a steward is named.

## The dissent

One reviewer argued the governance half should not be built at all: "replace, never append" makes
reach's documents maximally hostile to automatic merge, and objects mode resolves merges with no human
and no working tree — so objects mode is structurally least able to merge the exact artifact the
governance layer produces, and every additional person multiplies it. Their alternative was to keep
the sole-writer rule and let the team decide who holds the seat this month: zero implementation, and
it is what the rules already say.

Area ownership answers that better than claims did, because different people rewrite different files.
But the objection is recorded rather than won by omission, and if the steward seat turns out to be the
bottleneck that `adopt` predicts, that is the observed failure which would earn a redesign.

## The precondition

The four commands are "written, not yet weathered" — a distillation of a process that ran daily on one
large project for months, whose generic form here has not been through an adoption end to end. **None
of this should be built on top of that until the single-developer form has real mileage.** Building
team mechanics over an untested single-user mechanism means debugging both at once, and the first
repository to adopt will find seams in the simpler thing first.
