"""Build the illustrated edition using the current versioned slide copy.

python presentation/build_storybook.py
"""
from pathlib import Path
from build_deck import SLIDES, VERSION
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.oxml.xmlchemy import OxmlElement
from PIL import ImageFont

ROOT = Path(__file__).resolve().parent
ART = ROOT / 'artwork'
OUTPUT = ROOT / 'Reach-developer-presentation-storybook.pptx'
PAPER = 'F7F2E7'
INK = '253D35'
MUTED = '667166'
RUST = 'A44F32'
GOLD = '9B742D'
LINE = 'D8CEB9'
CARD = 'EDE6D7'
WHITE = 'FFFCF5'
GREEN = '3D7258'
FONT = 'Calibri'
TITLE = 'Georgia'


def rgb(h):
    return RGBColor.from_string(h)


def box(slide, x, y, w, h, fill, line=None, radius=False):
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE if radius else MSO_SHAPE.RECTANGLE,
                                  Inches(x), Inches(y), Inches(w), Inches(h))
    shape.fill.solid()
    shape.fill.fore_color.rgb = rgb(fill)
    if line:
        shape.line.color.rgb = rgb(line)
    else:
        shape.line.fill.background()
    if radius:
        shape.adjustments[0] = .07
    shape._element.spPr.append(OxmlElement('a:effectLst'))
    return shape


def text(slide, x, y, w, h, value, size=20, color=INK, bold=False, font=FONT):
    shape = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = shape.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = 0
    tf.margin_top = tf.margin_bottom = 0
    for i, line in enumerate(value.split('\n')):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line
        p.font.name = font
        p.font.size = Pt(size)
        p.font.bold = bold
        p.font.color.rgb = rgb(color)
        p.space_before = p.space_after = Pt(0)
        p.line_spacing = 1.08
    return shape


def line(slide, x1, y1, x2, y2, color=LINE, width=1):
    shape = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    shape.line.color.rgb = rgb(color)
    shape.line.width = Pt(width)
    shape._element.spPr.append(OxmlElement('a:effectLst'))


def card(slide, x, y, w, h, heading, body, accent=INK):
    box(slide, x, y, w, h, WHITE, LINE, True)
    box(slide, x, y, .055, h, accent)
    text(slide, x+.2, y+.15, w-.4, .36, heading, 19, accent, True)
    text(slide, x+.2, y+.64, w-.4, h-.72, body, 18)


def picture(slide, name, x, y, w):
    # Preserve the full composition and aspect ratio; never crop Pip or the entrances.
    return slide.shapes.add_picture(str(ART/name), Inches(x), Inches(y), width=Inches(w))


def fit_check(prs):
    issues=[]
    for i,s in enumerate(prs.slides,1):
        for sh in s.shapes:
            assert sh.left >= 0 and sh.top >= 0
            assert sh.left+sh.width <= prs.slide_width+10
            assert sh.top+sh.height <= prs.slide_height+10
            if not sh.has_text_frame or not sh.text:
                continue
            available_w=(sh.width-sh.text_frame.margin_left-sh.text_frame.margin_right)/914400*96
            available_h=(sh.height-sh.text_frame.margin_top-sh.text_frame.margin_bottom)/914400*96
            needed=0
            for p in sh.text_frame.paragraphs:
                size=p.font.size.pt
                filename=('georgiab.ttf' if p.font.bold else 'georgia.ttf') if p.font.name==TITLE else ('calibrib.ttf' if p.font.bold else 'calibri.ttf')
                font=ImageFont.truetype('C:/Windows/Fonts/'+filename,round(size*96/72))
                count=1
                current=''
                for word in p.text.split():
                    trial=(current+' '+word).strip()
                    if current and font.getlength(trial)>available_w:
                        count+=1
                        current=word
                    else:
                        current=trial
                needed+=count*size*96/72*1.15
            if needed>available_h+1:
                issues.append((i,sh.text,round(needed),round(available_h)))
    assert not issues,issues


def build():
    prs = Presentation()
    prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
    prs.core_properties.title = 'Reach — a workflow for better code'
    prs.core_properties.subject = f'Workplace developer talk v{VERSION}; 15–20 minutes including questions'
    prs.core_properties.version = VERSION
    prs.core_properties.author = 'Amelia Bleeker'
    for index, item in enumerate(SLIDES):
        s = prs.slides.add_slide(prs.slide_layouts[6])
        s.background.fill.solid()
        s.background.fill.fore_color.rgb = rgb(PAPER)
        accent = RUST if 'BUILD' in item['section'] else INK
        box(s, .58, .43, .11, .18, accent)
        text(s, .83, .39, 11, .3, item['section'] + '  /  REACH', 12, accent, True)
        if index == 0:
            box(s, 6.6, 0, 6.733, 7.5, INK)
            picture(s, item['scene'], 6.82, 1.5, 6.28)
            text(s, .7, 1.22, 5.55, 2.2, item['title'], 34, INK, False, TITLE)
            text(s, .7, 3.58, 5.3, .85, item['subtitle'], 22, MUTED)
            for j, b in enumerate(item['bullets']):
                text(s, .7, 4.65+j*.86, 5.25, .8, b, 20)
            text(s, 7.04, 6.06, 5.5, .8, item['caption'], 20, PAPER)
        else:
            text(s, .65, .95, 12.05, .72, item['title'], 28, INK, False, TITLE)
            text(s, .68, 1.7, 12, .43, item['subtitle'], 19, MUTED)
            line(s, .68, 2.13, 12.65, 2.13)
            if item.get('layout') == 'roles':
                for j, (heading, body, color, judge) in enumerate(zip(
                    ['IDEATE', 'BUILD', 'MILESTONE'], item['bullets'], [INK, RUST, GOLD],
                    ['Your design judgment', 'Automated evidence', 'Tests + your judgment'])):
                    x = .68 + j*4.06
                    card(s, x, 2.64, 3.82, 2.62, heading, body, color)
                    text(s, x+.2, 5.49, 3.42, .65, judge, 20, color, True)
                text(s, .88, 6.12, 11.3, .35, 'Missing decision? Return to ideate. Update the agreement. Resume.', 17, MUTED)
            else:
                split = any(key in item for key in ('scene', 'cards', 'artifact'))
                width = 5.8 if split else 11.52
                for j, b in enumerate(item['bullets']):
                    text(s, .72, 2.49+j*.98, .34, .36, f'{j+1:02}', 11, accent, True)
                    text(s, 1.16, 2.42+j*.98, width, .88, b, 20 if split else 23)
                if item.get('scene'):
                    picture(s, item['scene'], 7.35, 2.4, 5.3)
                    text(s, 7.38, 5.97, 5.25, .65, item['caption'], 16, MUTED)
                elif item.get('cards'):
                    for j, (heading, body) in enumerate(item['cards']):
                        card(s, 7.45, 2.43+j*1.38, 5.2, 1.36, heading, body, accent)
                elif item.get('artifact'):
                    heading, body = item['artifact']
                    box(s, 7.45, 2.43, 5.2, 3.9, WHITE, LINE, True)
                    box(s, 7.45, 2.43, .055, 3.9, accent)
                    text(s, 7.67, 2.64, 4.76, .4, heading, 16, accent, True)
                    text(s, 7.67, 3.2, 4.76, 2.9, body, 21)
            if item.get('payoff'):
                box(s, .66, 6.7, 12, .045, accent)
                text(s, .72, 6.87, 11.95, .34, item['payoff'], 16, accent, True)
        footer = f'REACH  ·  v{VERSION}  ·  DEVELOPER TALK'
        if item.get('appendix'):
            footer += '  /  OPTIONAL APPENDIX'
        text(s, .68, 7.25, 11.55, .18, footer, 9, MUTED)
        text(s, 12.12, 7.21, .5, .23, f'{index+1:02}', 11, PAPER if index == 0 else MUTED)
        timing = f"TARGET: {item['seconds']} seconds" if item.get('seconds') else 'OPTIONAL APPENDIX'
        s.notes_slide.notes_text_frame.text = (
            f"SLIDE {index+1}: {item['title']}\n\n{timing}\n\n{item['notes']}"
            + (f"\n\nPRACTICAL BENEFIT: {item['payoff']}" if item.get('payoff') else '')
            + f"\n\nSOURCE BASIS: {item['source']}"
            + '\n\nART: Existing AI-generated fictional artwork; diagrams and text are editable.'
        )
    fit_check(prs)
    prs.save(OUTPUT)
    check = Presentation(OUTPUT)
    assert len(check.slides) == len(SLIDES)
    for s, item in zip(check.slides, SLIDES):
        content = '\n'.join(sh.text for sh in s.shapes if sh.has_text_frame)
        assert item['title'] in content and item['subtitle'] in content
        assert all(b in content for b in item['bullets'])
        assert item['notes'] in s.notes_slide.notes_text_frame.text
    print(f'Built {OUTPUT}; {len(check.slides)} slides; copy, notes, text fit and geometry checked.')


if __name__ == '__main__':
    build()
