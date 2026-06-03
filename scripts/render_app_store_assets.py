#!/Users/aozkul/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "marketing" / "app-store" / "raw"
OUT_DIR = ROOT / "marketing" / "app-store" / "final"
ICON_PATH = ROOT / "PayGuard" / "Assets.xcassets" / "BrandMark.imageset" / "BrandMark-Primary.png"

WIDTH = 1320
HEIGHT = 2868


@dataclass(frozen=True)
class SlideSpec:
    source: str
    eyebrow: str
    title: str
    detail: str


SLIDES = [
    SlideSpec("01-onboarding.png", "WELCOME", "See every renewal.", "Start in seconds and keep subscriptions, receipts, returns, and warranty info in one polished workspace."),
    SlideSpec("02-dashboard.png", "DASHBOARD", "Know what is due next.", "Monthly cost, upcoming charges, and urgent deadlines stay visible without digging through settings or emails."),
    SlideSpec("03-subscriptions.png", "SUBSCRIPTIONS", "Track recurring spending cleanly.", "Catalog-assisted entry, smart import, filters, and archive controls make subscription management feel effortless."),
    SlideSpec("04-purchases.png", "WARRANTY", "Protect every purchase.", "Return windows, warranty dates, receipts, and quick search keep expensive items covered after checkout."),
    SlideSpec("05-family.png", "HOUSEHOLD", "Keep shared costs organized.", "Assign owners and payers, understand the household footprint, and keep everyone visible without clutter."),
    SlideSpec("06-settings.png", "PRO", "Unlock widgets and premium tools.", "Home Screen widgets, smart import, advanced summaries, and privacy-first controls are ready when you need more."),
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Helvetica.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def create_background() -> Image.Image:
    image = Image.new("RGBA", (WIDTH, HEIGHT), "#0D1E35")
    pixels = image.load()

    top = (10, 31, 53)
    middle = (28, 72, 120)
    bottom = (102, 195, 208)

    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        if t < 0.55:
            local = t / 0.55
            color = tuple(int(top[i] + (middle[i] - top[i]) * local) for i in range(3))
        else:
            local = (t - 0.55) / 0.45
            color = tuple(int(middle[i] + (bottom[i] - middle[i]) * local) for i in range(3))
        for x in range(WIDTH):
            pixels[x, y] = (*color, 255)

    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.ellipse((-180, -80, 700, 780), fill=(87, 214, 224, 46))
    draw.ellipse((760, 1600, 1480, 2480), fill=(255, 255, 255, 34))
    draw.ellipse((760, -140, 1540, 620), fill=(31, 95, 166, 54))
    overlay = overlay.filter(ImageFilter.GaussianBlur(70))

    grid = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    for x in range(-HEIGHT, WIDTH, 110):
        grid_draw.line((x, 0, x + HEIGHT, HEIGHT), fill=(255, 255, 255, 18), width=2)
    grid = grid.filter(ImageFilter.GaussianBlur(0.3))

    image.alpha_composite(overlay)
    image.alpha_composite(grid)
    return image


def draw_multiline(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    box: tuple[int, int, int, int],
    spacing: int,
) -> None:
    words = text.split()
    lines: list[str] = []
    current = ""

    for word in words:
        trial = word if not current else f"{current} {word}"
        width = draw.textbbox((0, 0), trial, font=font)[2]
        if width <= box[2] - box[0]:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)

    y = box[1]
    for line in lines:
        draw.text((box[0], y), line, font=font, fill=fill)
        y += draw.textbbox((0, 0), line, font=font)[3] + spacing


def build_slide(spec: SlideSpec, index: int) -> Path:
    screenshot = Image.open(RAW_DIR / spec.source).convert("RGBA")
    canvas = create_background()
    draw = ImageDraw.Draw(canvas)

    title_font = load_font(104, bold=True)
    detail_font = load_font(40)
    eyebrow_font = load_font(24, bold=True)
    badge_font = load_font(24, bold=True)

    left = 106
    right = WIDTH - 106

    draw.rounded_rectangle((left, 150, left + 202, 206), radius=28, fill=(255, 255, 255, 38))
    draw.text((left + 24, 165), spec.eyebrow, font=eyebrow_font, fill=(227, 248, 255, 255))

    draw_multiline(draw, spec.title, title_font, (255, 255, 255, 255), (left, 260, right - 40, 580), spacing=10)
    draw_multiline(draw, spec.detail, detail_font, (226, 240, 252, 228), (left, 610, right - 20, 840), spacing=8)

    card_width = WIDTH - 132
    max_card_height = HEIGHT - 1100
    scale = min(card_width / screenshot.width, max_card_height / screenshot.height)
    scaled = screenshot.resize((int(screenshot.width * scale), int(screenshot.height * scale)), Image.Resampling.LANCZOS)

    shadow = Image.new("RGBA", (scaled.width + 80, scaled.height + 80), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((20, 20, scaled.width + 60, scaled.height + 60), radius=86, fill=(3, 9, 19, 180))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.alpha_composite(shadow, ((WIDTH - shadow.width) // 2, 900))

    card = Image.new("RGBA", (scaled.width + 44, scaled.height + 44), (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card)
    card_draw.rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=84, fill=(255, 255, 255, 242), outline=(255, 255, 255, 46), width=2)
    card.paste(scaled, (22, 22), rounded_mask(scaled.size, 68))
    canvas.alpha_composite(card, ((WIDTH - card.width) // 2, 920))

    badge_box = (left, HEIGHT - 244, left + 246, HEIGHT - 162)
    draw.rounded_rectangle(badge_box, radius=30, fill=(255, 255, 255, 32))
    draw.text((badge_box[0] + 24, badge_box[1] + 18), "PAYGUARD", font=badge_font, fill=(14, 42, 72, 255))

    icon = Image.open(ICON_PATH).convert("RGBA").resize((98, 98), Image.Resampling.LANCZOS)
    icon_card = Image.new("RGBA", (130, 130), (0, 0, 0, 0))
    icon_draw = ImageDraw.Draw(icon_card)
    icon_draw.rounded_rectangle((0, 0, 129, 129), radius=34, fill=(255, 255, 255, 242))
    icon_card.paste(icon, (16, 16), icon)
    canvas.alpha_composite(icon_card, (WIDTH - 210, 156))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    output = OUT_DIR / f"{index:02d}-{spec.source}"
    canvas.convert("RGB").save(output, quality=95)
    return output


def main() -> None:
    outputs = [build_slide(spec, idx + 1) for idx, spec in enumerate(SLIDES)]
    print("\n".join(str(path) for path in outputs))


if __name__ == "__main__":
    main()
