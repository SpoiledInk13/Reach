"""Slide copy and speaker notes for the fictional Pip story."""

MAIN_SLIDES = [{'title': 'Reach: I just wanted the character to walk',
  'subtitle': 'Building with Claude while keeping sight of the game.',
  'bullets': ['Let Claude do more of the implementation while you stay involved in the decisions.',
              'One adventurer. One warm fireplace. One door that complicates everything.'],
  'notes': 'Reach grew out of game development. The original goal was simple: click a character and have '
           'them walk somewhere. As the project grew, keeping track of the decisions became harder than '
           'generating more code. This talk is about preserving that understanding while Claude does more of '
           "the implementation. We'll use a fictional game to make the workflow concrete.",
  'source': 'README.md: introduction and origin; presenter-approved fictional scenario'},
 {'title': 'The paperwork got there first',
  'subtitle': 'More instructions. More checks. Still a character who needed to walk.',
  'bullets': ['1,077 decision records and 662,000 lines of documentation.',
              'An 8,275-line verification gate that still missed defects.',
              'The active milestone: "click a character and walk them somewhere."',
              'New instructions kept arriving. Old ones rarely left.'],
  'payoff': 'Keep the current rule. Let Git remember the old one.',
  'notes': "These are the figures reported in Reach's README about the project that inspired it. Much of "
           'that material had a purpose when it was written. The problem was that it kept accumulating. Even '
           'attempts to consolidate it added more material. Checks accumulated too, without enough evidence '
           'that they could catch the mistakes they were meant to prevent. More output was making the '
           'project harder to understand. Reach grew out of addressing that.',
  'source': 'README.md: The problem it was built for'},
 {'title': 'Meet Pip. Pip would like to be warm.',
  'subtitle': 'A fictional game, a cozy cottage, and a fireplace just out of reach.',
  'bullets': ['Pip is outside. The fireplace is inside.',
              'The player clicks a spot beside the fireplace.',
              'In our first version, the door is the only usable entrance.',
              '"Just add click-to-move." Famous last words.'],
  'notes': 'Picture Pip outside a cottage. The player clicks on the floor beside the fireplace, and Pip '
           "should walk there. For now, the door is the only usable entrance, and movement doesn't "
           "automatically open it. This scene is invented for the talk. We'll follow it as the design "
           'becomes more interesting. First complication: what happens when the door is closed?',
  'source': 'Illustrative game scenario; not an implemented sample'},
 {'title': 'The tests pass. Pip has questions.',
  'subtitle': '"It works. It just isn\'t what I asked for."',
  'bullets': ['With the door open, Pip reaches the fireplace.',
              'With it closed, should Pip wait, refuse, or go somewhere else?',
              'Claude can implement any of those choices.',
              'We still need to decide which one belongs in this game.'],
  'payoff': 'Catch an unanswered design question before it becomes an accidental feature.',
  'notes': "A pathfinder can tell us there's no route. That doesn't tell us what the game should do about "
           'it. A nearby destination might be a reasonable fallback in one game and deeply confusing in '
           'another. If we leave that choice unstated, implementation can turn a plausible guess into a '
           'design decision. I want to stay involved in that decision without supervising every line of '
           'code.',
  'source': 'Illustrative scenario; skills/build/SKILL.md: design blockers'},
 {'title': 'Give the design conversation its own place',
  'subtitle': 'Reach is a Claude Code plugin built around three kinds of work.',
  'bullets': ['/reach:ideate: decide what we are building and record the contract.',
              '/reach:build: implement that contract and prove the behavior.',
              '/reach:milestone: build the look and feel, then hand it to you to judge.'],
  'payoff': 'Focus your attention on the decisions that need you.',
  'notes': 'The commands are /reach:ideate, /reach:build, and /reach:milestone. They divide work by who can '
           'judge the result. I judge design decisions in conversation. Tests judge behavior they can check. '
           'I judge the experience by using the actual build. The written agreement is the contract that '
           "later sessions read. This isn't a rigid sequence for every change: UI behavior can still need "
           'tests, and a project with no human-judged outcomes may not need milestone. The plugin combines '
           'these instructions with documents and executable checks. Adoption is covered in the appendix.',
  'source': 'README.md: Work — the loop; skills/ideate/SKILL.md; skills/build/SKILL.md; '
            'skills/milestone/SKILL.md'},
 {'title': 'Ideate keeps sight of the forest',
  'subtitle': '/reach:ideate challenges the idea before it becomes a requirement.',
  'bullets': ['Ideate raises the tradeoff: a nearby destination could surprise the player.',
              'Together, we agree: Pip follows a valid route to the spot the player clicked.',
              'If no route exists, Pip stays put and the game explains why.',
              'Ideate writes the contract that build will work against.'],
  'payoff': 'Get useful pushback while the idea is still cheap to change.',
  'notes': 'This is where Claude and I think together about the game. We can discuss alternatives and '
           'challenge a convenient answer before it becomes code. Ideate is instructed to give real '
           'tradeoffs and flag conflicts with the architecture. Here, we choose predictable movement. Notice '
           "that we've only settled what happens when there's no route at the moment of the click. We "
           "haven't yet decided what happens if the route disappears during the walk.",
  'source': 'Fictional design decision; skills/ideate/SKILL.md; presenter metaphor'},
 {'title': 'Build turns the agreement into working behavior',
  'subtitle': '/reach:build must test the agreed behavior before calling it built.',
  'bullets': ['Build writes evidence before or with the code: a closed door leaves Pip in place.',
              'It tests Pip’s position and the feedback that says the route is blocked.',
              'It runs the project’s verification tiers, including the actual game build.',
              'The verification runner reports unavailable tiers as SKIPPED, never passed.'],
  'payoff': "Know what was checked, and what still wasn't.",
  'notes': 'The build skill carries this requirement: write evidence before or with the code and run the '
           'configured tiers before marking work built. The scripts enforce the reported verification '
           "result. In this first scene, there's no alternative entrance. The test should verify that Pip "
           'stays put and the game reports no route. A named evidence row, such as '
           'blocked-route-does-not-teleport, connects that behavior to the document. Reach checks that '
           'connection; the test itself must check meaningful behavior. Build writes evidence before or with '
           "the implementation so the test doesn't simply describe whatever code it ended up writing. "
           'Verification runs from cheap checks through the real build. An unavailable automated tier is '
           'reported as skipped, and human acceptance remains separate.',
  'source': 'Fictional scenario; templates/unit.md; skills/build/SKILL.md; README.md: Verify-All.ps1'},
 {'title': 'Then someone closes the door',
  'subtitle': '/reach:build records the missing decision and keeps independent work moving.',
  'bullets': ['Build finds that the route can disappear after movement starts.',
              'It records: "Open: What should Pip do if the door closes on the way?"',
              'The question and its evidence go beside the claim for ideate to resolve.',
              'Build picks the next independent task instead of inventing the answer.'],
  'payoff': 'Fewer "continue" prompts. Unanswered design decisions stay yours.',
  'notes': "The initial rule covers a door that's already closed. This is a different case. Build records "
           'the question instead of inventing an answer or starting a design discussion in the middle of '
           'implementation. In a real repository, the question includes the code location or observation '
           "that exposed the gap. A blocked claim doesn't have to stop the entire run: build can finish "
           'other work, land it, and pick the next buildable item. It stops when no independent work remains '
           "or another stop condition applies. That doesn't require the optional unattended supervisor.",
  'source': 'Illustrative blocker; skills/build/SKILL.md; skills/ideate/SKILL.md: The inbox'},
 {'title': 'Decide once. Put the answer where it lasts.',
  'subtitle': '/reach:ideate turns the answer into the contract future sessions read.',
  'bullets': ['In ideate, we agree: if the route becomes blocked, Pip stops before the obstacle.',
              'Pip stays at the last valid position, and the game explains the interruption.',
              'Ideate replaces the old wording, removes the question, and publishes the decision.',
              'Build reads the updated contract and implements the settled rule.'],
  'payoff': 'The answer becomes part of the project, not another message to dig up.',
  'notes': 'Ideate checks the premise, then we decide how the game should behave. The answer replaces the '
           "relevant contract text. It doesn't become another comment underneath an unresolved question. Old "
           'wording leaves the active document, and Git keeps the history. Publishing matters too: a '
           "decision that exists only in my checkout hasn't reached the builder. When a new claim needs "
           'implementation, its missing evidence is recorded explicitly. The next session can see both the '
           'decision and the work still owed.',
  'source': 'Fictional resolution; skills/ideate/SKILL.md; templates/unit.md; scripts/lib/Common.ps1: '
            'Invoke-ReachPublish'},
 {'title': 'The door is locked. What about the window?',
  'subtitle': '/reach:ideate reviews the design beyond the immediate feature.',
  'bullets': ['The next request: let Pip reach the fireplace through a window.',
              'The easy move is to add window code beside the door code.',
              'Now both need rules for opening, closing, locking, and movement.',
              'Ideate asks: are these separate systems, or instances of the same idea?'],
  'payoff': 'Step back before every new feature becomes another special case.',
  'notes': "We're extending the game now. The first version only supported the door; this request adds a "
           "usable window. Pip's destination hasn't changed. The tempting implementation is a second path "
           'through the code, with its own version of every check. Ideate gives us a place to question that '
           "structure. I've found it useful for spotting this kind of shared concept. This particular Pip "
           'episode is fictional, but the generalization benefit comes from my experience.',
  'source': 'Presenter observation about generalization; fictional extension; skills/ideate/SKILL.md'},
 {'title': 'Doors and windows share an opening contract',
  'subtitle': 'Ideate defines the shared contract. Build implements it.',
  'bullets': ['Ideate identifies the common concept: an opening can be open or closed, locked or unlocked.',
              'We agree: a lock prevents opening it. Unlocking does not open it.',
              'Pip can pass through if it is open, reachable, and large enough.',
              'Ideate records those rules; build implements and tests them for doors and windows.'],
  'payoff': 'Extend the shared model instead of copying the logic.',
  'notes': 'Ideate does the generalizing here. It is responsible for architecture and contracts, so it can '
           'question the model across features. Build then implements the approved model rather than '
           'inventing a different contract. The common concept is an opening. Its current state is separate '
           "from whether Pip is allowed to open it. An unlocked window isn't necessarily open, and an open "
           "window isn't necessarily big enough to climb through. Those are design decisions to settle "
           "explicitly. For this example, movement still doesn't open or unlock anything automatically; Pip "
           'can use an already open, reachable window that fits. That gives us another route to the same '
           'fireplace. The rule about stopping when the active route becomes blocked still applies. We '
           "haven't added automatic replanning during movement. This is a shared domain contract, not a "
           'requirement to build an inheritance hierarchy. Door and window animations can still differ. '
           'Ideate updates the contract; build implements the common rules and tests both cases.',
  'source': 'Presenter’s opening example and agreed design distinction; fictional contract; '
            'skills/ideate/SKILL.md; skills/build/SKILL.md'},
 {'title': 'Catch the bug now. Catch it again later.',
  'subtitle': '/reach:build must show that the test can catch the broken rule.',
  'bullets': ['Build tests each opening as the only entrance: when it is closed, Pip must stay put.',
              'It deliberately allows passage through a closed opening and requires the test to fail.',
              'It restores the correct behavior and requires both cases to pass again.',
              'Future build runs rerun those tests so a window change does not break the door.'],
  'payoff': 'Break it once to check the test. Keep the test to catch regressions.',
  'notes': 'The deliberate break is an instruction in the build skill. The agent performs it and observes '
           'the result; there is no automatic application-mutation engine hidden behind this example. There '
           'are two benefits here. First, we check that the test can catch the behavior we care about. We '
           'deliberately allow passage through a closed opening, require failure because Pip moved, then '
           "restore the rule and require green. An unrelated compile error wouldn't prove that assertion "
           "works. Second, we keep running those cases so later changes can't quietly bring the bug back. "
           'Each test makes its opening the only possible entrance: an open alternative route would make '
           'staying put the wrong expectation. Locking and unlocking need their own cases, as do successful '
           'crossings. Reach instructs build to prove a negative control and runs similar controls for its '
           "own guards; it doesn't automatically mutate every application. This remains a fictional "
           'explanation, not a live demonstration. Next, we need to know that the code we accept is the code '
           'we checked.',
  'source': 'Fictional movement example; skills/build/SKILL.md: Proving; README.md: negative controls'},
 {'title': 'Keep the work separate. Share the decisions.',
  'subtitle': 'The skills follow the workflow; Reach’s scripts enforce the landing checks.',
  'bullets': ['Build and milestone each work in their own Git worktree.',
              'Ideate syncs before reading the current contracts.',
              'The skills pass the verified commit; the landing script refuses a different merged tree.',
              'The publish script shares integration first; a stale lane backup cannot hold it up.'],
  'payoff': 'Check the version you actually accept.',
  'notes': 'Separate worktrees give each lane its own files, staging index, branch, and build cache. They '
           "don't eliminate design conflicts, but they remove the collision caused by editing and testing "
           'the same checkout. Build supplies the commit whose verification tiers ran; ideate supplies the '
           'commit whose gate ran. Passing -Verified makes landing refuse a different merged tree. Without '
           'that flag the script can warn and proceed, so using it is part of the workflow. The '
           'stale-primary guard catches decisions made from an outdated checkout. When publication is '
           'enabled and a remote exists, the integration push determines success; other branch backups are '
           'best-effort. If publishing fails after the merge, retry publish. Team repositories can retain '
           'reviewer-controlled landing through push mode.',
  'source': 'skills/ideate/SKILL.md: Landing; scripts/Land.ps1; scripts/lib/Common.ps1'},
 {'title': 'Pip can get inside. Does it feel right?',
  'subtitle': '/reach:milestone builds the experience. You decide whether it works.',
  'bullets': ['Milestone refines the movement feedback using the behavior build has already proved.',
              'It drives the walkthrough on the real build, then hands that build to you.',
              'You judge: does Pip’s response make sense, or do the controls seem broken?',
              'Milestone records your feedback and keeps the walkthrough open until you confirm it.'],
  'payoff': 'You decide when the experience works.',
  'notes': 'Milestone owns the presentation work as well as the handoff. It adjusts visual and audio '
           'feedback, tries the walkthrough itself, and asks the owner for the final verdict. If it finds '
           'missing behavior or an unsettled design decision underneath the presentation, it records a '
           'blocker for ideate rather than inventing the answer. Milestone brings this back to a person '
           'using the real artifact. Our fictional walkthrough starts from a fresh launch: reach the '
           'fireplace by either usable entrance, then understand why Pip stops when all routes are blocked '
           'or the active route closes. The cases need to be reachable through ordinary actions, without '
           'developer shortcuts. Milestone works on presentation over the implemented behavior. Perhaps the '
           "blocked-route cue flashes too quickly or sounds like success. That's a presentation problem we "
           'can now judge. A failure the owner reports stays in the document in their words. A screenshot or '
           "completion report doesn't close the walkthrough; owner confirmation does. Automated checks still "
           'cover UI behavior they can assert.',
  'source': 'Fictional walkthrough; skills/milestone/SKILL.md'},
 {'title': "Pip gets warm. Tomorrow's session can pick up.",
  'subtitle': 'Each skill leaves the next session something concrete to work from.',
  'bullets': ['Ideate maintains the current contract: openings, not the old door-only rule.',
              'Build records the evidence and leaves unfinished claims and questions visible.',
              'Milestone keeps the walkthrough open until you accept the experience.',
              'The next build session rereads the documents and picks up the next buildable task.'],
  'payoff': 'Less reconstruction when you start again.',
  'notes': "Pip can get to the fireplace, and the reasoning hasn't disappeared into a long chat. The current "
           "contract says what openings do. The tests record what we've checked. Any remaining work or "
           'question is visible. Build rereads documents at unit boundaries rather than relying on its '
           'recollection. Keeping that working record small helps the next session recover without carrying '
           "every abandoned explanation. It doesn't guarantee perfect memory. It gives us somewhere reliable "
           "to restart. That's the point of the story: I can delegate more implementation while staying "
           "engaged with what we're building.",
  'source': 'Fictional story resolution; current Reach mechanisms'},
 {'title': 'What changed in my own work',
  'subtitle': 'Pip is fictional. These benefits come from my experience.',
  'bullets': ['Ideate gives Claude and me a place to think about the whole system.',
              'Keeping the design discussion there makes the interaction feel more human.',
              'Separating build’s implementation from ideate’s broader review has improved my code.',
              'Ideate helps find shared rules before new features become parallel code paths.'],
  'notes': 'These are my observations from using the process. Ideate has become the main place where Claude '
           'and I discuss the project, and that makes the collaboration feel more coherent. Separating '
           'implementation from review has improved the code in my experience. The opening example also '
           'captures something I value: recognizing a common rule instead of accumulating special cases. '
           "These aren't benchmark results. Other benefits, such as easier handoff and less repeated "
           'explanation, are things to look for in use. The full inventory is in the appendix.',
  'source': 'Presenter observations in planning conversation; inferred benefits'},
 {'title': 'Where Reach earns its keep',
  'subtitle': 'Enough structure to stay in control, with real upkeep attached.',
  'bullets': ['Best fit: one owner, a growing project, and more agent output than they can comfortably '
              'review.',
              'Team repositories can use the verification layer with their existing review process.',
              'Contracts and worktrees take upkeep. A small utility may not need them.',
              'The repository documents 50 negative controls; the packaged workflow still needs adoption '
              'mileage.'],
  'notes': 'This is most useful when understanding and reviewing the work have become the bottleneck. It '
           'also has costs: someone has to maintain the contracts, evidence, and lanes. For a small or '
           'mostly maintenance project, that can be more process than the work needs. Team repositories can '
           'take the verification layer without replacing their review practices. The documented control '
           'suites include 15 gate controls and 35 lane, landing, and audit controls. Those were not rerun '
           'to prepare this presentation. The README still reports limited end-to-end adoption experience '
           "for the generic plugin workflow. That's the current position: useful mechanisms and encouraging "
           'personal experience, with more real-project mileage needed.',
  'source': 'README.md: Is this for you?, Status; commit d6fa11d'}]

BENEFITS_SLIDE = {'title': 'Appendix: the practical benefits',
 'subtitle': "What I've observed, and what the design should help with.",
 'bullets': ['Ideate: useful pushback, shared rules, and decisions that survive the conversation.',
             'Build: fewer "continue" prompts, visible blockers, and evidence against the agreed behavior.',
             'Build + ideate: focused implementation followed by broader review in a fresh session.',
             'Milestone: a real build to judge, with acceptance kept in your hands.',
             'Documents + scripts: easier handoffs, clear verification results, and checked landings.'],
 'notes': 'The interaction, code-quality, and generalization benefits are observations from my use. Other '
          'benefits are reasonable expectations to evaluate, not measured guarantees. The complete set '
          'includes decisions that survive conversations, lower context load, focused attention, '
          'evidence-backed questions, easier interruption and handoff, fewer blind guesses, clearer '
          'failures, explicit evidence links, better-defined responsibilities, and less dependence on an '
          'individual session. Build can continue through independent work and has stop rules for repeated '
          'unsuccessful fixes. Tests should follow the agreed behavior, skipped verification stays visible, '
          "and the owner retains acceptance of the experience. These instructions don't guarantee agent "
          'compliance. Smaller context may reduce repeated exploration, but there is no measured '
          'token-saving claim.',
 'source': 'Presenter observations; inferred benefits from current Reach mechanisms',
 'appendix': True}
