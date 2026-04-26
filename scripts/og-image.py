"""Generate the YeboSell Open Graph image (1200x630)."""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

W, H = 1200, 630
OUT = Path(__file__).resolve().parent.parent / 'assets' / 'og-image.png'

# Brand palette
DARK_GREEN = (0x15, 0x80, 0x3d)   # left edge of gradient
LIGHT_GREEN = (0x25, 0xd3, 0x66)  # right edge of gradient
GOLD = (0xd4, 0xa0, 0x17)
WHITE = (255, 255, 255)
WHITE_DIM = (255, 255, 255, 220)

img = Image.new('RGB', (W, H))
px = img.load()
for x in range(W):
    t = x / (W - 1)
    r = int(DARK_GREEN[0] + (LIGHT_GREEN[0] - DARK_GREEN[0]) * t)
    g = int(DARK_GREEN[1] + (LIGHT_GREEN[1] - DARK_GREEN[1]) * t)
    b = int(DARK_GREEN[2] + (LIGHT_GREEN[2] - DARK_GREEN[2]) * t)
    for y in range(H):
        px[x, y] = (r, g, b)

# Overlay layer for the speech-bubble decoration with alpha
overlay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)
# subtle WhatsApp-style speech bubble, top right
bx, by, bw, bh = 1000, 60, 140, 110
od.rounded_rectangle((bx, by, bx + bw, by + bh), radius=22,
                     outline=(255, 255, 255, 90), width=4)
# tail
od.polygon([(bx + 30, by + bh), (bx + 50, by + bh + 22), (bx + 60, by + bh)],
           fill=(255, 255, 255, 30), outline=(255, 255, 255, 90))
# three dots inside
for i, cx in enumerate((bx + 45, bx + 70, bx + 95)):
    od.ellipse((cx - 6, by + bh // 2 - 6, cx + 6, by + bh // 2 + 6),
               fill=(255, 255, 255, 110))

img = Image.alpha_composite(img.convert('RGBA'), overlay).convert('RGB')
draw = ImageDraw.Draw(img)

# Fonts
ARIAL_BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
ARIAL = '/System/Library/Fonts/Supplemental/Arial.ttf'
title_font = ImageFont.truetype(ARIAL_BOLD, 180)
sub_font = ImageFont.truetype(ARIAL_BOLD, 38)
tag_font = ImageFont.truetype(ARIAL, 30)
attr_font = ImageFont.truetype(ARIAL, 22)

def text_w(s, font):
    return draw.textlength(s, font=font)

# Wordmark — single line: "Yebo" white + "Sell" gold
yebo, sell = 'Yebo', 'Sell'
yw = text_w(yebo, title_font)
sw = text_w(sell, title_font)
total = yw + sw
title_y = 200
start_x = (W - total) // 2
draw.text((start_x, title_y), yebo, fill=WHITE, font=title_font)
draw.text((start_x + yw, title_y), sell, fill=GOLD, font=title_font)

# Subtitle
sub = 'WhatsApp-Powered Commerce for Southern Africa'
draw.text(((W - text_w(sub, sub_font)) // 2, 430),
          sub, fill=WHITE, font=sub_font)

# Tagline
tag = 'Sell smarter.  Reach further.  Grow together.'
draw.text(((W - text_w(tag, tag_font)) // 2, 500),
          tag, fill=(235, 245, 235), font=tag_font)

# Attribution at bottom
attr = 'A product of InnovaEarth · Developed by 4D Climate Solutions'
draw.text(((W - text_w(attr, attr_font)) // 2, 580),
          attr, fill=(220, 240, 220), font=attr_font)

img.save(OUT, 'PNG', optimize=True)
print(f'wrote {OUT} ({OUT.stat().st_size:,} bytes)')
