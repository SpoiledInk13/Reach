# Reach developer presentation — version 2.0

A 15–20 minute workplace talk for developers with mixed experience using AI.
12 main slides target **13 minutes 45 seconds**, leaving 3–5 minutes for questions.
Four optional appendix slides support discussion; they are outside the timed talk.

- [Illustrated PowerPoint](Reach-developer-presentation-storybook.pptx)
- [PDF preview](Reach-developer-presentation-storybook.pdf)
- [Slide copy, example artifacts, and speaker notes](Reach-developer-presentation-v2.0.md)
- [Plain editable PowerPoint](Reach-developer-presentation-v2.0.pptx)

## Presenting the talk

Lead with the presenter's reason for using Reach for all coding: higher-quality
results, regardless of project size. The original difficulty tracking intent and
verification explains its development; quality explains its continued use.
Explain what a plugin, skill, and contract mean before walking through the commands.
The fictional Pip example illustrates
one feature; it does not require game-development experience or a running demo.

| Slides | Purpose | Target |
|---|---|---|
| 1–4 | Why Reach exists, what it adds, and the three roles | 4:00 |
| 5–9 | Adopt, decide, build, resolve a missing decision, try the result | 6:45 |
| 10–12 | Continuity, quality benefits, and the takeaway | 3:00 |
| Discussion | Questions; use an appendix only when relevant | 3–5 minutes |

Speaker notes contain a time target, a talk track, and local source references.
The walkthrough shows the contract, evidence case, and question handoff. It is
illustrative, not a report of a tested sample application. Personal observations
are distinguished from expected benefits; no productivity multiplier is claimed.

For a strict 15-minute slot, keep the walkthrough to the displayed cases and
reserve about a minute for questions. For 20 minutes, use the full discussion
allowance. Rehearse once against the target times; these are pacing estimates.

## Rebuild

From the repository root:

```shell
python -m pip install -r presentation/requirements.txt
python presentation/build_deck.py
python presentation/build_storybook.py
powershell -NoProfile -ExecutionPolicy Bypass -File presentation/export_preview.ps1
```

An optional local dependency install is supported with
`python -m pip install --target presentation/.deps -r presentation/requirements.txt`.

Edit `talk_slides.py` for all current slide copy, example artifacts, and speaker
notes. `build_deck.py` generates the versioned plain deck and Markdown companion;
`build_storybook.py` generates the current illustrated deck. Layout choices travel
with the slide data, so reordering does not misassign diagrams or artwork.

The builders validate saved content, notes, and object bounds. The illustrated
builder also estimates text fit using Georgia and Calibri Windows font files.
The export script requires desktop PowerPoint on Windows and refreshes the PDF
and local PNG previews in `storybook-preview/`. It opens the deck without a window.

## Previous editions

The v1.0 and v1.2 plain decks and Markdown files remain available. `story_slides.py`
preserves the previous longer narrative; the current builders use `talk_slides.py`.
The current illustrated deck reuses the existing [storybook artwork](artwork/README.md).
Local drafts, dependency packages, Python caches, and PNG previews are ignored.
