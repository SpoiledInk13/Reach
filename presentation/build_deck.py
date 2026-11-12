"""Build the content-only Reach deck and its reviewable Markdown companion.

Narrative content and optional appendix content live in talk_slides.py.
Install presentation/requirements.txt, then run from the repository root:
  python presentation/build_deck.py
"""
from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCAL_DEPS = ROOT / 'presentation' / '.deps'
if LOCAL_DEPS.exists():
    sys.path.insert(0, str(LOCAL_DEPS))

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

OUT = Path(__file__).resolve().parent
VERSION = '2.0'
OUTPUT_STEM = f'Reach-developer-presentation-v{VERSION}'
from talk_slides import MAIN_SLIDES, APPENDIX_SLIDES

SLIDES = MAIN_SLIDES + APPENDIX_SLIDES


def textbox(slide, x, y, w, h, text, size, bold=False, color=(0, 0, 0)):
    shape = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    frame = shape.text_frame
    frame.word_wrap = True
    frame.margin_left = frame.margin_right = Inches(0.03)
    frame.margin_top = frame.margin_bottom = Inches(0.03)
    p = frame.paragraphs[0]
    p.text = text
    p.font.name = 'Arial'
    p.font.size = Pt(size)
    p.font.bold = bold
    p.font.color.rgb = RGBColor(*color)
    return shape


def build(output_name=f'{OUTPUT_STEM}.pptx'):
    prs = Presentation()
    prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
    prs.core_properties.title = f'Reach — developer presentation v{VERSION}'
    prs.core_properties.subject = 'Why Reach, practical walkthrough, and developer benefits; workplace talk'
    prs.core_properties.version = VERSION
    prs.core_properties.author = 'Amelia Bleeker'
    main_count = sum(not item.get('appendix', False) for item in SLIDES)
    appendix_count = len(SLIDES) - main_count
    markdown = [f'# Reach — developer presentation v{VERSION}',
                f'{main_count} main slides + {appendix_count} appendix slides. 13:45 planned speaking time plus 3-5 minutes for questions; 15-20 minutes total. Appendices optional. '
                'Plain editable companion to the illustrated presentation.',
                'Pip and the cottage fireplace are a fictional teaching story. Speaker notes distinguish repository mechanisms, presenter observations, '
                'inferred benefits, and fictional events. Developer remarks in subtitles are illustrative, not research quotations. '
                'The presentation contains no live demonstration or claimed application test results.']
    for i, item in enumerate(SLIDES, 1):
        slide = prs.slides.add_slide(prs.slide_layouts[6])
        slide.background.fill.solid()
        slide.background.fill.fore_color.rgb = RGBColor(255, 255, 255)
        textbox(slide, .65, .38, 12, .78, item['title'], 30, True)
        textbox(slide, .65, 1.3, 12, .8, item['subtitle'], 21, color=(65, 65, 65))
        count = len(item['bullets'])
        row_height = min(1.02, 4.5 / count)
        for j, line in enumerate(item['bullets']):
            textbox(slide, .8, 2.22 + j * row_height, 11.75, row_height - .08,
                    '\u2022 ' + line, 22)
        if item.get('payoff'):
            textbox(slide, .8, 6.55, 11.75, .4, item['payoff'], 17, True)
        label = f'v{VERSION} | Appendix' if item.get('appendix') else f'v{VERSION}'
        textbox(slide, .65, 7.06, 12, .25, f'Reach | {label} | {i:02d}', 10, color=(95, 95, 95))
        slide.notes_slide.notes_text_frame.text = (
            f"SLIDE {i}: {item['title']}\n\n"
            + (f"TARGET: {item['seconds']} seconds\n\n" if item.get('seconds') else 'OPTIONAL APPENDIX\n\n')
            + item['notes']
            + (f"\n\nPRACTICAL BENEFIT: {item['payoff']}" if item.get('payoff') else '')
            + f"\n\nSOURCE BASIS: {item['source']}"
        )
        markdown.extend([f"## {i:02d}. {item['title']}", item['subtitle'],
                         '\n'.join('- ' + x for x in item['bullets'])])
        if item.get('artifact'):
            heading, body = item['artifact']
            markdown.append(f'**{heading}**\n\n' + '\n'.join('> ' + line if line else '>' for line in body.split('\n')))
            slide.notes_slide.notes_text_frame.text += f'\n\n{heading}\n{body}'
        if item.get('cards'):
            markdown.append('\n'.join(f'- **{heading}:** {body}' for heading, body in item['cards']))
        if item.get('payoff'):
            markdown.append('**Practical benefit:** ' + item['payoff'])
        if item.get('seconds'):
            markdown.append(f"**Target time:** {item['seconds']} seconds")
        markdown.extend(['**Speaker notes**\n\n' + item['notes'],
                         '**Source basis:** ' + item['source']])
    target = OUT / output_name
    prs.save(target)
    (OUT / f'{OUTPUT_STEM}.md').write_text('\n\n'.join(markdown) + '\n', encoding='utf-8')
    # Check the saved package, notes, and geometry, rather than only the in-memory deck.
    saved = Presentation(target)
    assert len(saved.slides) == len(SLIDES)
    for slide, item in zip(saved.slides, SLIDES):
        assert item['notes'] in slide.notes_slide.notes_text_frame.text
        for shape in slide.shapes:
            assert shape.left >= 0 and shape.top >= 0
            assert shape.left + shape.width <= saved.slide_width
            assert shape.top + shape.height <= saved.slide_height
        texts = '\n'.join(s.text for s in slide.shapes if s.has_text_frame)
        assert item['title'] in texts
        assert all(line in texts for line in item['bullets'])
        if item.get('payoff'):
            assert item['payoff'] in texts
    print(f'Created and validated {len(saved.slides)} editable slides with speaker notes: {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=f'{OUTPUT_STEM}.pptx',
                        help='Output filename inside presentation/')
    build(parser.parse_args().output)
