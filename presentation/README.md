# Reach developer presentation — version 1.0

Approved content and narrative: 17 main slides and 4 appendix slides, with speaker notes.
The layout remains plain; visual style and assets are deferred.

- [PowerPoint presentation](Reach-developer-presentation-v1.0.pptx)
- [Slide text and speaker notes](Reach-developer-presentation-v1.0.md)

The fictional Pip story illustrates the workflow. The deck distinguishes that story
from the presenter's experience and the repository's implemented mechanisms.

## Rebuild

From the repository root:

```shell
python -m pip install -r presentation/requirements.txt
python presentation/build_deck.py
```

Edit `story_slides.py` for the main narrative and benefit inventory.
Edit `build_deck.py` for the technical appendix and plain layout.
The generator writes the versioned PowerPoint and Markdown files and checks slide
contents, speaker notes, and object bounds.

Local review drafts and Python caches are ignored. Version 1.0 preserves the content
approved in review draft v13.
