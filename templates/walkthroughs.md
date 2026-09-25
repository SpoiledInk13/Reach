# Walkthroughs

Ordered. The top entry is the active one. A verified walkthrough is **deleted**, not archived — git
history is the record, and a completed-work roll is how a document that should shrink starts growing.

<!--
    Each entry is ONE SENTENCE describing a cold start, and its definition of done is that sentence
    happening on a real build with no developer shortcuts.

    If a piece of work cannot be stated that way, it is not a walkthrough -- it is a unit, and it
    belongs in the unit documents.

    That shape exists because per-bullet proof cannot see an assembly failure. A milestone can close
    with a dozen green bullets over a feature wired at one of its two start-up sites. One sentence,
    end to end, on the real artifact, is what catches that.

    Delete these comments when you write real entries.
-->

**A walkthrough is named by what it is, never by its number or its place in the list.** Confirming one
deletes it and the rest move up, so `walkthrough 3` and *the first walkthrough* both come to mean a
different entry, with nothing anywhere that would say so. Measured once: confirming a single entry left
six references across three documents pointing at things that no longer existed, and the commit that
deleted it noted they were going stale and left them — two more were written against the moved number
before anyone came back. Name an entry by its sentence — *the fireplace from a cold start* walkthrough —
or by what it does, as *the first walkthrough that runs a game* does, which identifies itself however the
list moves. **The top walkthrough** is the one position that may be used as a handle, because it is
defined as whichever is first. **A confirmed walkthrough is named at no handle at all**: what it brought
is shipped, so the sentence to write is about the thing rather than about the entry that delivered it.
`WalkthroughReferences` holds all three to the live entries.

## 1. <the sentence>

**Needs:** `row-one` `row-two` — the evidence rows this walkthrough actually runs on, never a unit.
A unit is a verdict about every claim it holds, so asking for one parks the lane behind work these
steps never touch. One project’s top walkthrough asked for a whole unit; the three rows it went on to
name by hand were all proven, and the one row still missing — which none of its steps reached — waited
on a unit nobody had started. Naming the unit would have held a ready walkthrough behind an unbuilt one.

**Open:** what is missing and the fact that shows it — the unit, the claim, a file and line. No
options and no recommendation. It sits here rather than under a unit's claim because a built unit
cannot carry a question, and answering it means writing the missing claim, which returns the work to
the build command's backlog.

**Not working:** a step the owner ran and found broken, in the owner's words. It does not get
rewritten smaller, and it does not close until they say so.
