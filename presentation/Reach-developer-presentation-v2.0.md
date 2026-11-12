# Reach — developer presentation v2.0

12 main slides + 4 appendix slides. 13:45 planned speaking time plus 3-5 minutes for questions; 15-20 minutes total. Appendices optional. Plain editable companion to the illustrated presentation.

Pip and the cottage fireplace are a fictional teaching story. Speaker notes distinguish repository mechanisms, presenter observations, inferred benefits, and fictional events. Developer remarks in subtitles are illustrative, not research quotations. The presentation contains no live demonstration or claimed application test results.

## 01. Reach: a workflow for better code

Why I built it. How I use it. What it gives back.

- I use this workflow for all my coding, on projects of every size.
- Clear decisions, verified behavior, and human judgment improve the result.

**Target time:** 45 seconds

**Speaker notes**

I use this workflow for all my coding, regardless of project size, because it produces higher-quality results in my experience. Reach grew out of needing to preserve understanding and control while delegating implementation to AI. That origin led to a workflow I now use throughout my coding: think through the behavior, implement against the agreement, verify it, and judge the result. Today I will show how the plugin supports that process and connect each step to its benefit. You do not need experience with Claude Code or AI agents. We will follow a fictional feature in an illustrated walkthrough rather than a live application demo.

**Source basis:** Presenter clarification: used for all coding, regardless of size, for higher quality; README.md: introduction

## 02. The documentation outgrew the context

An agent can only work with so much information at once.

- Decisions and instructions accumulated across sessions.
- The original project reached 1,077 decision records and 662,000 lines of docs.
- Too much documentation to fit in the agent’s context at once.
- Relevant decisions were easy to miss; old rules competed with current ones.

**Practical benefit:** Keep the current rules small enough to find, load, and use.

**Target time:** 60 seconds

**Speaker notes**

These figures come from the project described in the Reach README. They are background, not a benchmark. Context means the information available to the model while it works: instructions, conversation, and the file content it has loaded. The documentation had grown far beyond what could fit there at once. Keeping a decision somewhere on disk did not mean it would be available when needed. Finding and loading the relevant pieces became more work, while obsolete instructions competed with current rules. Each extra document seemed useful, but almost nothing was allowed to leave; even consolidation added more material. Reach addresses this by maintaining small, current contracts, replacing obsolete text, and keeping history in Git. The goal is to make the relevant agreement practical to load and use, rather than expecting the agent to take in the entire archive.

**Source basis:** Presenter clarification: documentation exceeding context; README.md: The problem it was built for; The four rules

## 03. What the plugin actually adds

A repeatable workflow inside Claude Code, with records and checks in the project.

- An AI coding agent can read files, edit code, and run commands.
- Reach gives it named skills for different kinds of work.
- Project documents hold decisions that later sessions need.
- PowerShell scripts run verification and enforce repository rules.

- **SKILLS:** Instructions for how to work
- **DOCUMENTS:** The current agreement
- **SCRIPTS:** Executable checks

**Practical benefit:** Reuse the workflow without rebuilding it in every chat.

**Target time:** 60 seconds

**Speaker notes**

If your AI use has mostly been asking questions or accepting autocomplete, a coding agent goes further: it works in a repository and runs tools. A skill is a reusable set of instructions; a slash command invokes one. Reach packages skills, document templates, and scripts as a Claude Code plugin. Instructions guide the agent. Documents preserve the agreement. Scripts enforce specific mechanical checks. A skill instruction is not a guarantee that the agent will comply, and a passing script cannot decide whether the product is the one we wanted. That explains why the workflow still needs a developer.

**Source basis:** README.md: How to use it; skills/; templates/; scripts/

## 04. Three kinds of work. Three ways to judge it.

Use the command that matches the decision in front of you.

- /reach:ideate — agree on the behavior and write the contract.
- /reach:build — implement the agreed behavior and prove it.
- /reach:milestone — build the experience and bring it back to you.

**Practical benefit:** You stay involved where judgment matters.

**Target time:** 75 seconds

**Speaker notes**

A contract here means the written agreement about what the software should do. Ideate is where I discuss alternatives, resolve design questions, and maintain that agreement. Build implements it and runs automated checks. Milestone owns the configured presentation layer, including its testable behavior, and brings me a real build to judge. The split is about who can verify a claim: a person making a design choice, a machine checking behavior, or a person using the experience. This is a loop, not three agents you must run simultaneously. If no presentation layer is configured, build owns all code. If everything can be checked automatically, milestone may be unnecessary. We will use each role once in the example.

**Source basis:** README.md: Work — the loop; skills/build/SKILL.md; skills/milestone/SKILL.md

## 05. Start with one repository and one feature

Install once. Adopt the project. Describe the outcome you want.

- Install the Reach plugin in Claude Code.
- Run /reach:adopt to agree on documents, checks, and integration.
- Our example: click beside the fireplace and have Pip walk there.
- First version: one entrance. Movement does not open the door.

**Practical benefit:** Adoption connects the workflow to the project you actually have.

**Target time:** 60 seconds

**Speaker notes**

Adopt is a setup conversation, not an instruction to impose the same structure on every repository. It identifies the project, verification commands, documents, and integration approach. It produces process.json and a script entry point and establishes checks whose failure paths are exercised. Installation commands are in the appendix. For the walkthrough, assume adoption is complete. Pip is outside a cottage and the player clicks near the fireplace. We have only one usable entrance. The same process applies to a web form or API behavior: the important part is turning an outcome into an explicit agreement.

**Source basis:** README.md: Install, Adopt; skills/adopt/SKILL.md; fictional Pip scenario

## 06. 1. Decide before the agent fills in the gaps

Use /reach:ideate to turn the request into an agreed behavior.

- You ask: “What should happen when the door is closed?”
- Ideate explores the tradeoff: wait, refuse, or choose another destination.
- You decide: follow a valid route; otherwise stay put and explain why.
- Ideate records that decision in the movement contract.

**ILLUSTRATIVE CONTRACT**

> When a route exists, Pip walks to the clicked destination.
>
> When no route exists, Pip stays in place and exposes a blocked-route state.

**Practical benefit:** A plausible implementation choice becomes an explicit product decision.

**Target time:** 90 seconds

**Speaker notes**

I start with /reach:ideate and describe the feature in ordinary language. The value is the discussion: Claude can question the request and help me consider consequences. A nearby destination might be useful in one game and confusing in another. It should not become the design simply because the agent could implement it. We choose predictable movement and record the answer. The text shown here is a shortened teaching example, not a complete unit document. The actual document also names evidence and dependencies. Movement exposes the blocked state; presentation explains it to the player. We have settled the initial click, but not every possible event during movement. That gap will matter shortly.

**Source basis:** skills/ideate/SKILL.md; templates/unit.md; fictional design decision

## 07. 2. Build against that agreement

Run /reach:build. The agent implements and verifies the behavior.

- Build reads the contract and implements movement.
- A named test checks that a closed door leaves Pip in place.
- Build runs the project’s configured verification stages.
- The report distinguishes passed, failed, and skipped checks.

**ILLUSTRATIVE EVIDENCE**

> closed-door-stays-put
>
> Given: the only entrance is closed.
> When: the player clicks inside.
> Then: position is unchanged and the blocked-route state is set.

**Practical benefit:** “Done” has evidence you can inspect.

**Target time:** 90 seconds

**Speaker notes**

I do not need to restate the design in a new implementation prompt. Build reads the current documents. It is instructed to write evidence before or with the code and run the configured verification stages before landing its work. The evidence name links a documented behavior to a test; the test still needs a meaningful assertion. Reach checks the link, not the semantic quality of an arbitrary test. The build skill also calls for deliberately breaking the behavior, observing the expected failure, and restoring it. That checks whether the test can catch the mistake. An unavailable verification stage is reported as skipped, not quietly treated as success. This is the intended test case, not a claim that this fictional application was run.

**Source basis:** skills/build/SKILL.md: Proving; templates/unit.md; scripts/Verify-All.ps1

## 08. 3. Bring missing decisions back to ideate

The door closes while Pip is walking. The rule does not cover it yet.

- Build records an Open question beside the affected claim.
- It continues independent work where the contract is clear.
- You return to /reach:ideate and decide: stop before the obstacle.
- Ideate updates the contract; build reads the answer and tests it.

- **BUILD FINDS A GAP:** Open: what if the route closes mid-walk?
- **YOU + IDEATE DECIDE:** Stop at the last valid position.
- **BUILD RESUMES:** Read the updated rule. Implement and prove it.

**Practical benefit:** Delegate implementation while keeping product decisions visible.

**Target time:** 90 seconds

**Speaker notes**

This is the most important handoff. Build is not asked to invent the missing rule, and one blocked claim need not stop every independent task. It writes a question where ideate already reads, including the code location or observation that exposed the gap. When I return to ideate, we decide that Pip stops at the last valid position before the obstacle. Ideate rewrites the current claim instead of adding another explanation below it. Build reads the answer and resumes. A question already on integration is removed with the answer; one still on a working branch is removed by that lane after it syncs. An unanswered decision stays visible and its answer survives the conversation.

**Source basis:** skills/build/SKILL.md: Picking work; skills/ideate/SKILL.md: The inbox; fictional blocker

## 09. 4. Try the result yourself

Use /reach:milestone when the experience needs a human verdict.

- Milestone builds and tests feedback over the movement behavior.
- It walks through a real build and hands it to you.
- You try an open door, a closed door, and a route interrupted mid-walk.
- You confirm the result, or report what still does not work.

**Practical benefit:** Passing tests and accepting the experience are separate decisions.

**Target time:** 75 seconds

**Speaker notes**

Pip can behave correctly while the interaction still feels broken. Perhaps the blocked cue flashes too quickly or sounds like success. Milestone owns presentation work, including tests for behavior a machine can assert. It tries the documented walkthrough on a real build and brings it to me. My acceptance is explicit. A screenshot or an agent saying it looks good does not substitute for that. If I find a movement bug, the report stays in my words while ideate connects it to the responsible claim and lane. Build adds the missing test case and repairs movement; milestone repairs defects in its own layer. I retry the resulting build. That closes the loop between an agreed design, tested behavior, and the actual experience.

**Source basis:** skills/milestone/SKILL.md; skills/ideate/SKILL.md: The owner’s verdict; fictional walkthrough

## 10. The next session starts from the record

Current decisions, evidence, and open questions stay with the work.

- The contract says what should happen now.
- Evidence links show what was checked; missing work stays visible.
- Open questions show where a decision is still needed.
- Document limits force old text out. Git keeps the history.

- **AGREED:** Stop before a newly blocked route.
- **CHECKED:** Tests for the starting and mid-walk cases.
- **NEXT SESSION:** Read the current record and pick up the work.

**Practical benefit:** Less time reconstructing the project from a long chat.

**Target time:** 60 seconds

**Speaker notes**

The main artifact is the small current record that the next session can read. Reach caps documents so keeping them current includes deleting obsolete text. If a rule changes, we replace the active wording; Git remains the history. Evidence and questions show what is understood, implemented, and unresolved. That makes a fresh session or an interruption easier to recover from. It is also where the workflow avoids repeating the original accumulation problem. This is not perfect memory or a guarantee of agent compliance. It is a concrete place to restart, and someone still has to maintain it.

**Source basis:** README.md: The four rules; skills/build/SKILL.md; templates/unit.md

## 11. What I get back from the workflow

Higher-quality results are why I use it for all my coding.

- Better design conversations: ideate creates room to question the approach.
- Useful delegation: build keeps moving and surfaces decisions it cannot make.
- Clearer review: contracts and evidence give me something concrete to inspect.
- Easier restarts: the next session reads the current record.

**Practical benefit:** My experience: better results across projects of every size.

**Target time:** 75 seconds

**Speaker notes**

Higher-quality results are the reason I continue to use this workflow for all coding. The strongest benefits in my own use have been the design discussion and the separation between deciding and implementing. Ideate gives Claude and me a place to think about the whole system. When adding a window to the cottage, for example, we can ask whether doors and windows share an opening contract before duplicating their rules. That broader discussion and separate review have improved the code and made the interaction feel more human. Visible questions, evidence against agreed behavior, and a clear place to restart support that quality on small tasks as well as large projects. This is my experience, not a measured productivity multiplier or guaranteed token savings.

**Source basis:** Presenter clarification: quality across all coding; previous presentation: presenter observations; README.md: workflow mechanisms

## 12. Why I use Reach for all my coding

Project size changes. Clear decisions and verification still matter.

- I use the workflow on small tasks and large projects because the results are better.
- Decide what should happen, implement it, verify it, and judge the result.
- On team projects, the workflow works alongside the existing review process.
- Ask: what was decided, what was checked, and what still needs me?

**Practical benefit:** The reason I keep using it: higher-quality results.

**Target time:** 45 seconds

**Speaker notes**

I use this workflow for all my coding, no matter how big the project is. The original accumulation problem explains why I developed it; the quality of the results explains why I keep using it. A small task still benefits from a clear decision, an implementation checked against that decision, and a review of the result. On a team I retain the established review process; Reach supports a verification layer or a personal overlay, covered in the appendix. The three questions on this slide are the takeaway. Leave three to five minutes for discussion. Suggested prompt: which part of your current AI workflow would most benefit from clearer decisions or stronger verification?

**Source basis:** Presenter clarification: used for all coding for higher-quality results; README.md: A personal overlay on a team repository

## 13. Appendix: install and start

Commands from this repository; run adoption in the target project.

- Requires Claude Code, Git, and Windows PowerShell 5.1 or pwsh.
- Terminal: claude plugin marketplace add SpoiledInk13/Reach
- Terminal: claude plugin install reach@reach
- Inside Claude Code: /reach:adopt

**Speaker notes**

Commands are sourced locally; external compatibility was not rechecked for this deck. Installation defaults to user scope. Start the adoption conversation in the target repository. Objects-mode landing needs Git 2.38 or newer. Adoption writes process.json and Scripts/reach.ps1, configures documents and verification stages, and exercises the gate. A personal overlay keeps the entry point inside its own folder. Then use ideate, build, and milestone as appropriate. Adoption changes the repository, so follow its usual review process.

**Source basis:** README.md: How to use it; skills/adopt/SKILL.md; scripts/Land.ps1

## 14. Appendix: what the checks can prove

Gates check repository rules. Tests check behavior. People judge the experience.

- pwsh Scripts/reach.ps1 gate — check document rules and evidence links.
- pwsh Scripts/reach.ps1 all — run the gate and verification stages.
- pwsh Scripts/reach.ps1 prove — exercise Reach’s supplied controls.
- Break a guarded condition, observe the intended failure, restore, and rerun.

**Practical benefit:** A useful check can detect the mistake it is meant to catch.

**Speaker notes**

The gate enforces mechanical properties such as document caps, contract declarations, and evidence references. It cannot prove that every assertion in an arbitrary test is meaningful. Build instructs the agent to demonstrate a negative control for application behavior; Reach does not automatically mutate every application. The supplied proof suites exercise guard failure paths. New custom checks need their own controls. The local README reports 110 controls and nine gate checks for Reach 0.17.0; this presentation edit does not rerun or newly certify those suites. Scripts/reach.ps1 is an adopted project’s entry point, not a file to invoke at this plugin repository root.

**Source basis:** README.md: Verify, Status; scripts/Verify-All.ps1; scripts/Prove-Gate.ps1; scripts/Prove-Lanes.ps1

## 15. Appendix: isolation and unattended work

Add these mechanisms when the project needs them.

- A lane is a Git worktree: its own files, branch, staging area, and build cache.
- Landing with -Verified refuses a merged tree different from the one checked.
- /reach:iterate carries work across fresh agent runs and follows progress.
- Unattended mode requires explicit opt-in and disables agent permission prompts.

**Speaker notes**

Lanes prevent two runs from editing and testing the same checkout. They do not eliminate design or merge conflicts. In the standard workflow, skills supply the verified commit to land; without -Verified the script can warn and proceed. The primary checkout must sync to read integrated decisions. Iterate supervises repeated runs, not individual tests, and runs finish verification before landing. It reduces restart supervision, not test duration. Stop lets the current run finish. Ordinary operation ends when a successful run commits nothing and has nothing to wait for; failures have their own stop and retry behavior. Builders and an integrator are optional when one editor, device, or harness must run final verification.

**Source basis:** README.md: Lanes, Unattended; skills/iterate/SKILL.md; scripts/Land.ps1

## 16. Appendix: using Reach on a team

Choose the scope that fits the team’s existing workflow.

- Shared verification: use the gate and verification contract with normal review.
- Personal overlay: keep your Reach documents in a locally excluded folder.
- The owner promotes a verified task commit for team review.
- Code, tests, and evidence marks reach the team. Reviewers still merge.

**Practical benefit:** Personal structure can coexist with the team’s review process.

**Speaker notes**

Full document governance assumes one owner answering design questions. A team can use the verification layer without replacing pull requests and review. One contributor can instead run the full process over their own tasks in a personal overlay. Its documents, process.json, and shim live in a folder excluded through .git/info/exclude. There are no lanes or land in this mode: work happens on a task branch. Build ends at a green verification report. Promotion is the owner’s action; promote verifies every stage on the exact commit and pushes it for review. The merge request is opened by hand. The overlay needs its own backup because its documents are not committed to the team repository. See README.md for setup and limitations.

**Source basis:** README.md: A personal overlay on a team repository; skills/build/SKILL.md; skills/adopt/SKILL.md
