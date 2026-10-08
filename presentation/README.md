# Reach developer presentation — version 1.1

19 main slides and 5 appendix slides, with speaker notes. Allow approximately
25–30 minutes for the main story; use the appendix for discussion.

Version 1.1 updates ownership, lane questions, acceptance, contract readiness, and
project status against Reach 0.14.1 and the current README. It adds the owner-feedback
loop, builders and the integrator, and unattended operation. `/reach:iterate` is in
the main story, showing how long verification can continue across runs without
waiting around to restart the work. The 83 control definitions
were counted in source; the proof suites were not rerun for this presentation.

## Storybook visual edition

The illustrated edition uses the v1.1 copy and speaker notes, with the existing
five storybook illustrations, skill labels, and editable diagrams. New diagrams
show the feedback loop, unattended iteration, and the builder/integrator split.

- [Illustrated PowerPoint](Reach-developer-presentation-storybook.pptx)
- [PDF preview](Reach-developer-presentation-storybook.pdf)
- [Artwork and visual references](artwork/README.md)

Build it with `python presentation/build_storybook.py` after installing the same
requirements below. The layout uses Georgia and Calibri, and its text-fit check
uses their Windows font files. PowerPoint-rendered previews were used for review.
The original v1.0 files remain available as the previous content baseline.

- [Plain PowerPoint presentation](Reach-developer-presentation-v1.1.pptx)
- [Slide text and speaker notes](Reach-developer-presentation-v1.1.md)
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
