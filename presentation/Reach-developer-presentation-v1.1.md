# Reach — developer presentation v1.1

19 main slides + 5 appendix slides. Approximately 25-30 minutes plus discussion; appendices optional. Plain editable layout; visual style and assets intentionally deferred.

Pip and the cottage fireplace are a fictional teaching story. Speaker notes distinguish repository mechanisms, presenter observations, inferred benefits, and fictional events. Developer remarks in subtitles are illustrative, not research quotations. The presentation contains no live demonstration or claimed application test results.

## 01. Reach: I just wanted the character to walk

Building with Claude while keeping sight of the game.

- Let Claude do more of the implementation while you stay involved in the decisions.
- One adventurer. One warm fireplace. One door that complicates everything.

**Speaker notes**

Reach grew out of game development. The original goal was simple: click a character and have them walk somewhere. As the project grew, keeping track of the decisions became harder than generating more code. This talk is about preserving that understanding while Claude does more of the implementation. We'll use a fictional game to make the workflow concrete.

**Source basis:** README.md: introduction and origin; presenter-approved fictional scenario

## 02. The paperwork got there first

More instructions. More checks. Still a character who needed to walk.

- 1,077 decision records and 662,000 lines of documentation.
- An 8,275-line verification gate that still missed defects.
- The active milestone: "click a character and walk them somewhere."
- New instructions kept arriving. Old ones rarely left.

**Practical benefit:** Keep the current rule. Let Git remember the old one.

**Speaker notes**

These are the figures reported in Reach's README about the project that inspired it. Much of that material had a purpose when it was written. The problem was that it kept accumulating. Even attempts to consolidate it added more material. Checks accumulated too, without enough evidence that they could catch the mistakes they were meant to prevent. More output was making the project harder to understand. Reach grew out of addressing that.

**Source basis:** README.md: The problem it was built for

## 03. Meet Pip. Pip would like to be warm.

A fictional game, a cozy cottage, and a fireplace just out of reach.

- Pip is outside. The fireplace is inside.
- The player clicks a spot beside the fireplace.
- In our first version, the door is the only usable entrance.
- "Just add click-to-move." Famous last words.

**Speaker notes**

Picture Pip outside a cottage. The player clicks on the floor beside the fireplace, and Pip should walk there. For now, the door is the only usable entrance, and movement doesn't automatically open it. This scene is invented for the talk. We'll follow it as the design becomes more interesting. First complication: what happens when the door is closed?

**Source basis:** Illustrative game scenario; not an implemented sample

## 04. The tests pass. Pip has questions.

"It works. It just isn't what I asked for."

- With the door open, Pip reaches the fireplace.
- With it closed, should Pip wait, refuse, or go somewhere else?
- Claude can implement any of those choices.
- We still need to decide which one belongs in this game.

**Practical benefit:** Catch an unanswered design question before it becomes an accidental feature.

**Speaker notes**

A pathfinder can tell us there's no route. That doesn't tell us what the game should do about it. A nearby destination might be a reasonable fallback in one game and deeply confusing in another. If we leave that choice unstated, implementation can turn a plausible guess into a design decision. I want to stay involved in that decision without supervising every line of code.

**Source basis:** Illustrative scenario; skills/build/SKILL.md: design blockers

## 05. Give the design conversation its own place

Reach is a Claude Code plugin built around three kinds of work.

- /reach:ideate: decide what we are building and record the contract.
- /reach:build: implement and prove the layers outside presentation.
- /reach:milestone: build and test presentation; hand you the experience.

**Practical benefit:** Focus your attention on the decisions that need you.

**Speaker notes**

The commands are /reach:ideate, /reach:build, and /reach:milestone. They divide work by who can judge the result. I judge design decisions in conversation. Tests judge behavior they can check. I judge the experience by using the actual build. The written agreement is the contract that later sessions read. This isn't a rigid sequence for every change: UI behavior can still need tests. Code ownership follows the layer; verification follows the claim. Milestone owns human.layer, including its controls, input, rendering, and the tests for assertable behavior there. Build owns the other layers. Without human.layer, build owns all code; milestone can still compose and tune an experience. A project with no human-judged outcomes may not need milestone. The plugin combines these instructions with documents and executable checks. Adoption is covered in the appendix.

**Source basis:** README.md: Work — the loop; skills/ideate/SKILL.md; skills/build/SKILL.md; skills/milestone/SKILL.md

## 06. Ideate keeps sight of the forest

/reach:ideate challenges the idea before it becomes a requirement.

- Ideate raises the tradeoff: a nearby destination could surprise the player.
- Together, we agree: Pip follows a valid route to the spot the player clicked.
- If no route exists, Pip stays put and the game explains why.
- Ideate writes the contract that build will work against.

**Practical benefit:** Get useful pushback while the idea is still cheap to change.

**Speaker notes**

This is where Claude and I think together about the game. We can discuss alternatives and challenge a convenient answer before it becomes code. Ideate is instructed to give real tradeoffs and flag conflicts with the architecture. Here, we choose predictable movement. Notice that we've only settled what happens when there's no route at the moment of the click. We haven't yet decided what happens if the route disappears during the walk. In an adopted repository, ideate searches the archive before calling a decision missing. Past owner rulings are recovered whole; an unapproved draft is offered as a proposal. The archive records past direction, not automatic authority over the current contract.

**Source basis:** Fictional design decision; skills/ideate/SKILL.md; presenter metaphor

## 07. Build turns the agreement into working behavior

/reach:build must test the agreed behavior before calling it built.

- Build writes evidence before or with the code: a closed door leaves Pip in place.
- It tests Pip’s position and the blocked-route state the presentation reads.
- It runs the project’s verification tiers, including the actual game build.
- The verification runner reports unavailable tiers as SKIPPED, never passed.

**Practical benefit:** Know what was checked, and what still wasn't.

**Speaker notes**

The build skill carries this requirement: write evidence before or with the code and run the configured tiers before marking work built. The scripts enforce the reported verification result. In this first scene, there's no alternative entrance. The test should verify that Pip stays put and the game reports no route. A named evidence row, such as blocked-route-does-not-teleport, connects that behavior to the document. Reach checks that connection; the test itself must check meaningful behavior. Build writes evidence before or with the implementation so the test doesn't simply describe whatever code it ended up writing. Verification runs from cheap checks through the real build. An unavailable automated tier is reported as skipped, and human acceptance remains separate. Build proves the movement state; milestone writes and tests the cue in the presentation layer. A state flip to built and any other change read by a check must precede verification. Anything changed afterwards must be verified again. Optional builders leave harness-dependent tiers to the integrator, which runs every tier before landing; the appendix explains that split.

**Source basis:** Fictional scenario; templates/unit.md; skills/build/SKILL.md; README.md: Verify-All.ps1

## 08. Then someone closes the door

/reach:build records the missing decision and keeps independent work moving.

- Build finds that the route can disappear after movement starts.
- It records: "Open: What should Pip do if the door closes on the way?"
- The question and its evidence go beside the claim for ideate to resolve.
- Build picks the next independent task instead of inventing the answer.

**Practical benefit:** Fewer "continue" prompts. Unanswered design decisions stay yours.

**Speaker notes**

The initial rule covers a door that's already closed. This is a different case. Build records the question instead of inventing an answer or starting a design discussion in the middle of implementation. In a real repository, the question includes the code location or observation that exposed the gap. A blocked claim doesn't have to stop the entire run: build can finish other work, land it, and pick the next buildable item. It stops when no independent work remains or another stop condition applies. That doesn't require the optional unattended supervisor. A question is committed on the working lane even when the implementation cannot land yet. Ideate reads additions on every local branch except integration and the primary branch, so a newly created lane does not become an invisible inbox.

**Source basis:** Illustrative blocker; skills/build/SKILL.md; skills/ideate/SKILL.md: The inbox

## 09. Decide once. Put the answer where it lasts.

/reach:ideate turns the answer into the contract future sessions read.

- In ideate, we agree: if the route becomes blocked, Pip stops before the obstacle.
- Pip stays at the last valid position, and the game explains the interruption.
- Ideate rewrites the claim and publishes the decision.
- Build syncs the answer, removes its lane’s question, and implements the rule.

**Practical benefit:** The answer becomes part of the project, not another message to dig up.

**Speaker notes**

Ideate checks the premise, then we decide how the game should behave. The answer replaces the relevant contract text. It doesn't become another comment underneath an unresolved question. Old wording leaves the active document, and Git keeps the history. Publishing matters too: a decision that exists only in my checkout hasn't reached the builder. When a new claim needs implementation, its missing evidence is recorded explicitly. The next session can see both the decision and the work still owed. If the question is already on integration, ideate deletes it with the answer. If it exists only on a lane, the answering commit identifies the lane, unit, and claim using Answers <lane>'s Open under <unit> claim <N>. The originating lane reads those answers after syncing and deletes the resolved Open itself. A clean merge alone does not remove the line beside the rewritten claim.

**Source basis:** Fictional resolution; skills/ideate/SKILL.md; templates/unit.md; scripts/lib/Common.ps1: Invoke-ReachPublish

## 10. The door is locked. What about the window?

/reach:ideate reviews the design beyond the immediate feature.

- The next request: let Pip reach the fireplace through a window.
- The easy move is to add window code beside the door code.
- Now both need rules for opening, closing, locking, and movement.
- Ideate asks: are these separate systems, or instances of the same idea?

**Practical benefit:** Step back before every new feature becomes another special case.

**Speaker notes**

We're extending the game now. The first version only supported the door; this request adds a usable window. Pip's destination hasn't changed. The tempting implementation is a second path through the code, with its own version of every check. Ideate gives us a place to question that structure. I've found it useful for spotting this kind of shared concept. This particular Pip episode is fictional, but the generalization benefit comes from my experience.

**Source basis:** Presenter observation about generalization; fictional extension; skills/ideate/SKILL.md

## 11. Doors and windows share an opening contract

Ideate defines the shared contract. Build implements it.

- Ideate identifies the common concept: an opening can be open or closed, locked or unlocked.
- We agree: a lock prevents opening it. Unlocking does not open it.
- Pip can pass through if it is open, reachable, and large enough.
- Ideate records those rules; build implements and tests them for doors and windows.

**Practical benefit:** Extend the shared model instead of copying the logic.

**Speaker notes**

Ideate does the generalizing here. It is responsible for architecture and contracts, so it can question the model across features. Build then implements the approved model rather than inventing a different contract. The common concept is an opening. Its current state is separate from whether Pip is allowed to open it. An unlocked window isn't necessarily open, and an open window isn't necessarily big enough to climb through. Those are design decisions to settle explicitly. For this example, movement still doesn't open or unlock anything automatically; Pip can use an already open, reachable window that fits. That gives us another route to the same fireplace. The rule about stopping when the active route becomes blocked still applies. We haven't added automatic replanning during movement. This is a shared domain contract, not a requirement to build an inheritance hierarchy. Door and window animations can still differ. Ideate updates the contract; build implements the common rules and tests both cases.

**Source basis:** Presenter’s opening example and agreed design distinction; fictional contract; skills/ideate/SKILL.md; skills/build/SKILL.md

## 12. Catch the bug now. Catch it again later.

/reach:build must show that the test can catch the broken rule.

- Build tests each opening as the only entrance: when it is closed, Pip must stay put.
- It deliberately allows passage through a closed opening and requires the test to fail.
- It restores the correct behavior and requires both cases to pass again.
- Future build runs rerun those tests so a window change does not break the door.

**Practical benefit:** Break it once to check the test. Keep the test to catch regressions.

**Speaker notes**

The deliberate break is an instruction in the build skill. The agent performs it and observes the result; there is no automatic application-mutation engine hidden behind this example. There are two benefits here. First, we check that the test can catch the behavior we care about. We deliberately allow passage through a closed opening, require failure because Pip moved, then restore the rule and require green. An unrelated compile error wouldn't prove that assertion works. Second, we keep running those cases so later changes can't quietly bring the bug back. Each test makes its opening the only possible entrance: an open alternative route would make staying put the wrong expectation. Locking and unlocking need their own cases, as do successful crossings. Reach instructs build to prove a negative control and runs similar controls for its own guards; it doesn't automatically mutate every application. This remains a fictional explanation, not a live demonstration. Next, we need to know that the code we accept is the code we checked.

**Source basis:** Fictional movement example; skills/build/SKILL.md: Proving; README.md: negative controls

## 13. Keep the work separate. Share the decisions.

The skills follow the workflow; Reach’s scripts enforce the landing checks.

- Build and milestone each work in their own Git worktree.
- Ideate syncs before reading the current contracts.
- The skills pass the verified commit; the landing script refuses a different merged tree.
- The publish script shares integration first; a stale lane backup cannot hold it up.

**Practical benefit:** Check the version you actually accept.

**Speaker notes**

Separate worktrees give each lane its own files, staging index, branch, and build cache. They don't eliminate design conflicts, but they remove the collision caused by editing and testing the same checkout. Build supplies the commit whose verification tiers ran; ideate supplies the commit whose gate ran. Passing -Verified makes landing refuse a different merged tree. Without that flag the script can warn and proceed, so using it is part of the workflow. The stale-primary guard catches decisions made from an outdated checkout. When publication is enabled and a remote exists, the integration push determines success; other branch backups are best-effort. If publishing fails after the merge, retry publish. Team repositories can retain reviewer-controlled landing through push mode.

**Source basis:** skills/ideate/SKILL.md: Landing; scripts/Land.ps1; scripts/lib/Common.ps1

## 14. Verification takes longer. Keep the work moving.

/reach:iterate carries build work across runs while you follow progress.

- As Pip’s game grows, each full test and build cycle takes longer.
- /reach:iterate starts a supervisor that runs build in fresh agent processes.
- Each run finishes its checks; the next picks up from committed work.
- You can step away, follow progress, or request a stop after the current run.

**Practical benefit:** Long verification no longer means waiting around to start the next run.

**Speaker notes**

The door and window cases are small, but a growing game accumulates tests, integration checks, and a real artifact to build. Waiting for each long cycle and then returning to start another session becomes its own job. /reach:build already continues through independent work within a run. /reach:iterate adds a supervisor that carries that work across fresh agent processes when runs finish, while the observing chat follows short progress events. It saves supervision time; it does not make the tests themselves faster or skip required verification. Each run keeps its verification in the foreground and finishes its checks before landing. A fresh process starts per run, not per test or tier, so the next session rereads the documents and resumes from committed work without stretching one conversation indefinitely. A long quiet verification call is not treated as a dead supervisor: the lane lock determines whether it is still running. Unattended operation requires explicit opt-in with unattended: true and disables agent permission prompts. The same lock excludes a second supervisor or a manual build in that lane. Start from the primary checkout with /reach:iterate; status, watch, and stop are also available. A stop request lets the run in flight finish. Ordinary operation halts when a successful run commits nothing and has nothing to wait for; unanswered design questions go back to ideate. API 429/5xx failures retry with capped backoff; other failures halt with their cause rather than being called design blockers. With builders configured, iterate follows the integrator and seeded builders as a set; an integrator can idle and a builder can wait for its ready tip to land. Terminal equivalents are pwsh Scripts/reach.ps1 run build, run build -Status -Follow, and run build -Stop. Logs live under Logs/reach-lane. These are workflow mechanisms, not a claim that our fictional Pip example was benchmarked.

**Source basis:** User’s long-verification use case; README.md: Unattended; skills/iterate/SKILL.md; scripts/Run-Lane.ps1

## 15. Pip can get inside. Does it feel right?

/reach:milestone builds the experience. You decide whether it works.

- Milestone builds and tests the cues over the movement state build has proved.
- It drives the walkthrough on the real build, then hands that build to you.
- You judge: does Pip’s response make sense, or do the controls seem broken?
- Milestone records your verdict; only your confirmation accepts the experience.

**Practical benefit:** You decide when the experience works.

**Speaker notes**

Milestone owns the presentation work as well as the handoff. It adjusts visual and audio feedback, tries the walkthrough itself, and asks the owner for the final verdict. If it finds missing behavior or an unsettled design decision underneath the presentation, it records a blocker for ideate rather than inventing the answer. Milestone brings this back to a person using the real artifact. Our fictional walkthrough starts from a fresh launch: reach the fireplace by either usable entrance, then understand why Pip stops when all routes are blocked or the active route closes. The cases need to be reachable through ordinary actions, without developer shortcuts. Milestone works on presentation over the implemented behavior. Perhaps the blocked-route cue flashes too quickly or sounds like success. That's a presentation problem we can now judge. A failure the owner reports stays in the document in their words. A screenshot or completion report doesn't close the walkthrough; owner confirmation does. Automated checks still cover UI behavior they can assert, and milestone writes those checks for its layer. A defect in that layer is milestone’s own to repair; an unsettled contract goes to ideate. The walkthrough names the specific evidence rows it needs. Unrelated unfinished claims in the same unit do not hold it up. Milestone records Confirmed lines in the owner’s words. Ideate preserves any lasting decisions and deletes the walkthrough only when wholly confirmed; confirming three steps of four leaves the fourth open.

**Source basis:** Fictional walkthrough; skills/milestone/SKILL.md

## 16. The tests passed. You found a bug.

The rule was clear. The tests missed a case you encountered while playing.

- Pip should stop before the door. In your playthrough, he crosses it.
- You report the bug. Ideate connects it to the movement rule.
- Build adds a test that catches the crossing, fixes it, and reruns the checks.
- You retry the real build and confirm the fix.

**Practical benefit:** Your feedback becomes a tested repair, and you confirm the result.

**Speaker notes**

This is another fictional episode, not a reported application test result. The contract already says Pip stops before the obstacle, but our earlier test missed a crossing during one movement update. Milestone records a Not working line in the owner’s words. Ideate triages it with an arrow naming the claim, evidence row, and responsible lane; milestone does not guess the fix from an untriaged symptom. Because movement is outside the presentation layer, build owns this repair. A proven claim that still fails needs a stronger fixture: add an owed row for the crossing case while retaining the original proof. If the fault were in presentation code, milestone would implement and test that repair. The arrow is refreshed as the work becomes proven, while the owner’s report remains. Passing tests sends the build back for judgment. Confirmation retires only the steps the owner actually names; ideate captures any new rules before deleting the completed entry.

**Source basis:** Fictional regression; skills/ideate/SKILL.md: The owner’s verdict; skills/milestone/SKILL.md: The owner’s verdict, Closing one

## 17. Pip gets warm. Tomorrow's session can pick up.

Each skill leaves the next session something concrete to work from.

- Ideate maintains the current contract: openings, not the old door-only rule.
- Build records the evidence and leaves unfinished claims and questions visible.
- Milestone records your acceptance; ideate retires the completed walkthrough.
- The next build session rereads the documents and picks up the next buildable task.

**Practical benefit:** Less reconstruction when you start again.

**Speaker notes**

Pip can get to the fireplace, and the reasoning hasn't disappeared into a long chat. The current contract says what openings do. The tests record what we've checked. Any remaining work or question is visible. Build rereads documents at unit boundaries rather than relying on its recollection. Keeping that working record small helps the next session recover without carrying every abandoned explanation. It doesn't guarantee perfect memory. It gives us somewhere reliable to restart. That's the point of the story: I can delegate more implementation while staying engaged with what we're building. The same deletion principle applies to the agent’s memory index: once a lesson is stated in a document or enforced by a guard, remove its whole index entry. The note remains searchable on disk. Shortening entries to fit keeps the accumulation problem alive. Reach explains this practice but does not enforce agent memory.

**Source basis:** Fictional story resolution; current Reach mechanisms

## 18. What changed in my own work

Pip is fictional. These benefits come from my experience.

- Ideate gives Claude and me a place to think about the whole system.
- Keeping the design discussion there makes the interaction feel more human.
- Separating build’s implementation from ideate’s broader review has improved my code.
- Ideate helps find shared rules before new features become parallel code paths.

**Speaker notes**

These are my observations from using the process. Ideate has become the main place where Claude and I discuss the project, and that makes the collaboration feel more coherent. Separating implementation from review has improved the code in my experience. The opening example also captures something I value: recognizing a common rule instead of accumulating special cases. These aren't benchmark results. Other benefits, such as easier handoff and less repeated explanation, are things to look for in use. The full inventory is in the appendix.

**Source basis:** Presenter observations in planning conversation; inferred benefits

## 19. Where Reach earns its keep

Enough structure to stay in control, with real upkeep attached.

- Best fit: one owner, a growing project, and more agent output than they can comfortably review.
- Team repositories can use the verification layer with their existing review process.
- Contracts and worktrees take upkeep. A small utility may not need them.
- 83 controls; used daily on one downstream project. A second adoption is still untested.

**Speaker notes**

This is most useful when understanding and reviewing the work have become the bottleneck. It also has costs: someone has to maintain the contracts, evidence, and lanes. For a small or mostly maintenance project, that can be more process than the work needs. Team repositories can take the verification layer without replacing their review practices. The documented control suites include 24 gate controls and 59 lane, landing, supervisor, and audit controls, with nine gate checks. Counts were checked against source; the proof suites were not rerun to prepare this presentation. The README now reports daily use of the commands, lanes, builders, and unattended supervisor on one downstream project. Recent repairs came from that use. A second adoption remains untested, so this is experience with one project rather than broad validation.

**Source basis:** README.md: Is this for you?, Status; scripts/Prove-Gate.ps1; scripts/Prove-Lanes.ps1

## 20. Appendix: the practical benefits

What I've observed, and what the design should help with.

- Ideate: useful pushback, shared rules, and decisions that survive the conversation.
- Build: fewer "continue" prompts, visible blockers, and evidence against the agreed behavior.
- Build + ideate: focused implementation followed by broader review in a fresh session.
- Milestone: a real build to judge, with acceptance kept in your hands.
- Documents + scripts: easier handoffs, clear verification results, and checked landings.

**Speaker notes**

The interaction, code-quality, and generalization benefits are observations from my use. Other benefits are reasonable expectations to evaluate, not measured guarantees. The complete set includes decisions that survive conversations, lower context load, focused attention, evidence-backed questions, easier interruption and handoff, fewer blind guesses, clearer failures, explicit evidence links, better-defined responsibilities, and less dependence on an individual session. Build can continue through independent work and has stop rules for repeated unsuccessful fixes. Tests should follow the agreed behavior, skipped verification stays visible, and the owner retains acceptance of the experience. These instructions don't guarantee agent compliance. Smaller context may reduce repeated exploration, but there is no measured token-saving claim.

**Source basis:** Presenter observations; inferred benefits from current Reach mechanisms

## 21. Appendix: getting started

Install once, then adopt a repository.

- Requires Claude Code and PowerShell. Objects-mode landing needs Git 2.38 or newer.
- claude plugin marketplace add SpoiledInk13/Reach
- claude plugin install reach@reach
- In Claude Code: /reach:adopt
- Then use /reach:ideate, /reach:build, and /reach:milestone.

**Speaker notes**

These are the commands documented in this repository. Use Windows PowerShell 5.1 or pwsh; Git is required in either landing mode. Objects-mode landing needs merge-tree --write-tree from Git 2.38. Adoption is a conversation about the repository's existing workflow, not a blind scaffolding step. It writes process.json and the script entry point, configures verification, and ignores local logs and locks. On an already-adopted repository, it audits for gaps instead of repeating the original replacement. Milestone is optional when there is no outcome that needs human judgment. Commands were sourced locally; external compatibility was not rechecked for the presentation.

**Source basis:** README.md: How to use it; scripts/Land.ps1; scripts/lib/Common.ps1: Get-PowerShellExe; skills/adopt/SKILL.md

## 22. Appendix: where the workflow lives

The decisions and checks live with the repository.

- process.json: document locations, size limits, evidence conventions, checks, and lanes.
- Architecture + separately capped roster: shared rules and the list of units.
- Unit documents: contract readiness, claims, dependencies, and evidence.
- Walkthroughs: human acceptance, with specific evidence rows as prerequisites.
- Scripts/reach.ps1: the entry point for verification and lane operations.

**Speaker notes**

The architecture document is called the spine in Reach. Unit documents describe smaller parts of the system. Their state is built or unbuilt; a new claim on a built unit can carry owed evidence until implemented. The gate checks the links between evidence and documents, while tests check the behavior. The script entry point resolves the installed plugin so the repository doesn't hard-code a versioned cache path. The template's reach version, 0.0.0, is a placeholder; adoption records the actual baseline. Audit compares that baseline with the running plugin in both directions and reports which plugin path answered. The roster can be its own capped document, so splitting a unit does not consume the architecture’s line budget. The Contract header declares none when missing decisions prevent starting, or partial when the written part can be built; a whole contract omits the header. ContractIsDeclared checks those declarations and missing roster documents. Walkthrough Needs names evidence rows, never whole units: an unrelated unfinished row must not park a ready experience.

**Source basis:** templates/process.json; templates/unit.md; templates/roster.md; templates/walkthroughs.md; scripts/gate-checks/ContractIsDeclared.ps1; README.md: process.json

## 23. Appendix: checking the process

Use the same entry point locally and in automation.

- pwsh Scripts/reach.ps1 gate — check repository constraints and evidence links.
- pwsh Scripts/reach.ps1 all — run the gate and automated verification tiers.
- pwsh Scripts/reach.ps1 prove — exercise the 83 supplied controls.
- pwsh Scripts/reach.ps1 audit — find adoption gaps and version mismatches.
- Add custom checks when a real defect shows the need, then prove they can fail.

**Speaker notes**

A custom check is a PowerShell file in the configured checks directory with a matching Test-<filename> function. The supplied proof suite doesn't automatically cover new custom checks or application behavior. A recent archive-check fix illustrates the need for realistic controls: it caught edits before commit but missed them after commit. It now checks both uncommitted changes and branch commits, including deletion of the last archive file. Controls can also check diagnostic wording. An unset document cap is now reported as missing configuration, and audit identifies version drift. Optional unattended operation requires explicit opt-in and disables agent permission prompts. The suites contain 24 gate controls and 59 lane, landing, supervisor, and audit controls. Nine gate checks include ContractIsDeclared, TriageLines, and WalkthroughReferences, keeping contract readiness, feedback routing, and live walkthrough references queryable. Counts were checked in source; these suites were not rerun for this presentation.

**Source basis:** README.md: Verify, Writing your own checks; scripts/Audit.ps1; scripts/Prove-Gate.ps1; scripts/Prove-Lanes.ps1

## 24. Appendix: many builders, one game harness

Use the split when an editor, emulator, or device limits parallel work.

- Each builder claims a unit and proves the tiers that can run without the harness.
- A builder marks its proven commit ready. It never lands.
- The integrator merges ready commits, runs every tier over the batch, and lands.
- When every tier runs anywhere, an ordinary second lane is simpler.

**Speaker notes**

This is optional. Declare builders on the build lane and mark harness-dependent tiers builders: false. lane seed build-1 creates a separate worktree without the integrator’s harness warm-up. builders take claims a unit before writing; builders ready marks a clean, proven HEAD. The integrator reads builders pending, merges ready tips, verifies the combined tree through every tier, and lands it. A rejection includes a reason; the builder repairs and re-proves its work. land refuses builders. This does not turn a skipped required tier into a pass: the harness tiers are explicitly assigned to the integrator. The README reports about 65 proven rows per day in the preceding week and about 240 during the first two days with two builders. The day before the split already reached 156, so this is a qualified observation from one project, not a controlled benchmark or a promised speedup.

**Source basis:** README.md: Builders, when one harness is the bottleneck; scripts/Builders.ps1; scripts/Verify-All.ps1; skills/build/SKILL.md: Builders
