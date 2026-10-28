# Reach developer presentation — version 1.2

19 main slides and 6 appendix slides, with speaker notes. Allow approximately
25–30 minutes for the main story; use the appendix for discussion.

Version 1.2 brings the deck to Reach 0.17.0. It adds an appendix slide on the
personal overlay — the whole process run over one contributor's own tasks on a
team repository, promoting verified commits into the team's review — and mentions
it where the deck discusses team repositories and landing. Both proof suites, 110
controls, were run green for this version.

## Storybook visual edition

The illustrated edition uses the v1.2 copy and speaker notes, with the existing
five storybook illustrations, skill labels, and editable diagrams, including the
feedback loop, unattended iteration, the builder/integrator split, and the overlay.

- [Illustrated PowerPoint](Reach-developer-presentation-storybook.pptx)
- [PDF preview](Reach-developer-presentation-storybook.pdf)
- [Artwork and visual references](artwork/README.md)

Build it with `python presentation/build_storybook.py` after installing the same
requirements below. The layout uses Georgia and Calibri, and its text-fit check
uses their Windows font files. PowerPoint-rendered previews were used for review.
The original v1.0 files remain available as the previous content baseline.

- [Plain PowerPoint presentation](Reach-developer-presentation-v1.2.pptx)
- [Slide text and speaker notes](Reach-developer-presentation-v1.2.md)
- [Previous v1.0 content](Reach-developer-presentation-v1.0.md)

The fictional Pip story illustrates the workflow. The deck distinguishes that story
from the presenter's experience and the repository's implemented mechanisms.

## Rebuild

From the repository root:

```shell
python -m pip install -r presentation/requirements.txt
python presentation/build_deck.py
python presentation/build_storybook.py
powershell -NoProfile -ExecutionPolicy Bypass -File presentation/export_preview.ps1
```

Edit `story_slides.py` for the main narrative and benefit inventory.
Edit `build_deck.py` for the technical appendix and plain layout.
The generators write the versioned plain PowerPoint and Markdown files and the
current illustrated PowerPoint. They check slide contents, speaker notes, and
object bounds; the illustrated generator also checks text fit. The export script
requires desktop PowerPoint on Windows and refreshes the illustrated PDF and local
PNG previews in `storybook-preview/`.

Local review drafts and Python caches are ignored. Version 1.0 preserves the content
approved in review draft v13.
