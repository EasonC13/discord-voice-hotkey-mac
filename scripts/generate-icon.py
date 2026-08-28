#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw

SIZE = 1024
out = Path(__file__).resolve().parents[1] / "Resources" / "AppIcon-1024.png"
out.parent.mkdir(parents=True, exist_ok=True)

image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
pixels = image.load()
for y in range(SIZE):
    t = y / (SIZE - 1)
    for x in range(SIZE):
        s = x / (SIZE - 1)
        pixels[x, y] = (
            int(112 - 36 * t),
            int(91 - 35 * s),
            int(246 - 22 * t),
            255,
        )

mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask).rounded_rectangle((32, 32, 992, 992), radius=220, fill=255)
image.putalpha(mask)
draw = ImageDraw.Draw(image)
white = (255, 255, 255, 245)
soft = (255, 255, 255, 165)

# Microphone capsule.
draw.rounded_rectangle((382, 205, 642, 610), radius=130, fill=white)
# Open recording arc.
draw.arc((286, 318, 738, 738), start=0, end=180, fill=white, width=54)
draw.rounded_rectangle((485, 705, 539, 828), radius=27, fill=white)
draw.rounded_rectangle((365, 800, 659, 854), radius=27, fill=white)

# Subtle waveform marks around the mic.
for x, height in [(215, 110), (270, 180), (754, 180), (809, 110)]:
    cy = 492
    draw.rounded_rectangle((x, cy - height // 2, x + 28, cy + height // 2), radius=14, fill=soft)

image.save(out)
print(out)
