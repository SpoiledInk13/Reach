---
description: Run a lane unattended from this window — check nothing holds it, start its supervisor, follow what each run lands, and stop it on request. This window never builds. Use to run the builder non-stop, to see how an unattended lane is getting on, or to stop one.
argument-hint: "[start | watch | status | stop | dry-run] [lane]"
---

# Iterate

Starts the lane supervisor (`Scripts/reach.ps1 run <lane>`), which runs the lane's command as a **fresh
agent process per run** until a run commits nothing, and keeps this window as its console: what it is
doing, what each run landed, and a stop when the owner asks for one.

**This window never builds.** Every run is its own process with its own context, which is the whole
point of the supervisor: an in-session loop grows one context until it compacts, and compaction is
exactly what the builder's *stop trusting your own memory* conditions exist to prevent. This window
holds only short event lines, so it can follow a night of runs.

Run it from the **primary checkout**. The supervisor refuses to drive a lane from inside itself,
because syncing the lane rewrites the scripts the loop is running.

## Parse the request

Read the arguments as an action and a lane. No action means `start`; no lane means `build`.

| Action | Does |
|---|---|
| `start` | check, pre-flight, launch, follow — or follow, if one is already running |
| `watch` | follow a supervisor that is already running |
| `status` | `Scripts/reach.ps1 run <lane> -Status`, printed verbatim, then stop |
| `stop` | **Stopping**, below |
| `dry-run` | as `start`, launching with `-DryRun`: one real but trivial agent call, then a halt. Use it after upgrading the agent CLI or this plugin. |

## start

1. **Check.** `Scripts/reach.ps1 run <lane> -Check`, and show its lines. It reads the lane lock, so it
   answers for any supervisor on this machine.
   - **exit 1, RUNNING** — do not start a second one. One agent per lane. Say so, then go to **watch**.
   - **exit 0** with `lane: N uncommitted change(s)` — a session started by hand in the lane, or a run
     that died mid-work. Nothing records which, so ask the owner whether to start anyway.
   - **exit 0** with `lane: not seeded` — stop, and give the seed command it printed.
2. **Pre-flight.** `Scripts/reach.ps1 run <lane> -SelfTest`. It proves the halt decision, the watch and
   the stop request on synthetic input in seconds. Anything but `SELF-TEST PASSED` and exit 0: show it
   and stop.
3. **Launch it detached**, in its own terminal window, so it outlives this session and any cap on a
   background command, and so the owner has a window to interrupt. On Windows:

       powershell -NoProfile -Command "Start-Process pwsh -WorkingDirectory '<primary>' -ArgumentList '-NoProfile','-NoExit','-File','<primary>/Scripts/reach.ps1','run','<lane>'"

   Elsewhere, open it in a new terminal or under `nohup`. For `dry-run`, append `-DryRun`.
4. **Follow it**: **watch**, with `-NewRun`.

## watch

Follow `Scripts/reach.ps1 run <lane> -Watch -NewRun` straight after a launch, or `-Watch -FromEnd` to
attach to one already running, with the longest timeout the tool allows and each output line arriving as
an event. Before attaching to a running one, show `-Status` once so the owner sees where it has got to.

Each event is a ledger line — a run starting, its verdict, what it landed — a `progress:` line when
the lane branch moves, or a `quiet:` line. Relay each to the owner as it arrives, in a line or two, and
keep this window otherwise quiet.

**A `quiet:` line is not a stall.** The status is written when the agent says something, and one long
tool call — a whole verification sweep — says nothing for as long as it runs. Whether the supervisor is
there is the lane lock's to answer, never the status file's age, so a quiet with the lock held is
followed and only a lock released without a last line is stale.

| Exit | Means | Do |
|---|---|---|
| 0 | the supervisor finished: a run committed nothing, or a stop was honoured | Say which, from the lines before it. A halt on nothing committed means everything buildable is blocked on a question — name the design command as what comes next. |
| 4 | it crashed | Show the crash line and the log path from `-Status`. Never restart it on your own. |
| 2 | nothing holds the lane and its ledger never said it finished | It was killed or its window was closed. Show `-Status`; the owner's window is the record. |
| 3 | `-NewRun` saw it never start | It failed a guard before its loop, and its window says which. |
| 1 | nothing to watch | No ledger has been written. Nothing is running. |

**A watch that times out is not a halt.** Re-arm it with `-Watch -FromEnd`, silently, for as long as the
supervisor runs. `-FromEnd` still finds a last line written in the gap, so a finish is never missed.

The owner can type in this window while it follows. Answer them, and keep the watch armed.

## Stopping

**A stop is a request, and it lets the run in flight finish**, so that run still lands.
`Scripts/reach.ps1 run <lane> -Stop`, and show what it prints. Keep the watch armed until the finish
line arrives, and report it. Do this whenever the owner says stop, in words or with `stop`.

**Never kill the supervisor or its agent process yourself**, even when asked to hurry. That loses
everything the run has not committed. If the owner wants it gone now, the hard stop is theirs: an
interrupt in the supervisor's window. Say exactly that.

## What it never does

- start a second supervisor on a lane, or start one over uncommitted work without the owner's word;
- build, test or land anything itself — the runs do that, in the lane;
- answer a question a run parked on — that is the design command's, and a halt is its cue.
