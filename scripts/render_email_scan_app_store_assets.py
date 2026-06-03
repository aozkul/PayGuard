#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ICON_PATH = ROOT / "PayGuard" / "Assets.xcassets" / "BrandMark.imageset" / "BrandMark-Primary.png"


@dataclass(frozen=True)
class DeviceSpec:
    name: str
    raw_dir: Path
    final_dir: Path
    width: int
    height: int
    screenshot_corner_radius: int
    card_corner_radius: int
    title_size: int
    detail_size: int
    eyebrow_size: int
    badge_size: int
    card_top: int
    card_width_margin: int
    card_bottom_margin: int
    is_tablet: bool = False


PHONE = DeviceSpec(
    name="phone",
    raw_dir=ROOT / "marketing" / "app-store" / "raw",
    final_dir=ROOT / "marketing" / "app-store" / "final",
    width=1320,
    height=2868,
    screenshot_corner_radius=68,
    card_corner_radius=84,
    title_size=102,
    detail_size=38,
    eyebrow_size=24,
    badge_size=24,
    card_top=930,
    card_width_margin=132,
    card_bottom_margin=180,
)

TABLET = DeviceSpec(
    name="ipad",
    raw_dir=ROOT / "marketing" / "app-store-ipad" / "raw",
    final_dir=ROOT / "marketing" / "app-store-ipad" / "final",
    width=2064,
    height=2752,
    screenshot_corner_radius=62,
    card_corner_radius=74,
    title_size=120,
    detail_size=42,
    eyebrow_size=28,
    badge_size=28,
    card_top=880,
    card_width_margin=180,
    card_bottom_margin=210,
    is_tablet=True,
)


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


def fit_text(draw: ImageDraw.ImageDraw, text: str, max_width: int, start_size: int, min_size: int = 20, bold: bool = True) -> ImageFont.FreeTypeFont:
    size = start_size
    while size >= min_size:
        font = load_font(size, bold=bold)
        width = draw.textbbox((0, 0), text, font=font)[2]
        if width <= max_width:
            return font
        size -= 2
    return load_font(min_size, bold=bold)


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
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)

    y = box[1]
    for line in lines:
        draw.text((box[0], y), line, font=font, fill=fill)
        y += draw.textbbox((0, 0), line, font=font)[3] + spacing


def create_background(width: int, height: int) -> Image.Image:
    image = Image.new("RGBA", (width, height), "#0D1E35")
    pixels = image.load()

    top = (10, 31, 53)
    middle = (28, 72, 120)
    bottom = (102, 195, 208)

    for y in range(height):
        t = y / (height - 1)
        if t < 0.55:
            local = t / 0.55
            color = tuple(int(top[i] + (middle[i] - top[i]) * local) for i in range(3))
        else:
            local = (t - 0.55) / 0.45
            color = tuple(int(middle[i] + (bottom[i] - middle[i]) * local) for i in range(3))
        for x in range(width):
            pixels[x, y] = (*color, 255)

    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.ellipse((-220, -120, int(width * 0.55), int(height * 0.28)), fill=(87, 214, 224, 44))
    draw.ellipse((int(width * 0.62), int(height * 0.58), int(width * 1.08), int(height * 0.96)), fill=(255, 255, 255, 26))
    draw.ellipse((int(width * 0.60), -160, int(width * 1.08), int(height * 0.24)), fill=(31, 95, 166, 58))
    overlay = overlay.filter(ImageFilter.GaussianBlur(80))

    grid = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    for x in range(-height, width, 110 if width < 1800 else 140):
        grid_draw.line((x, 0, x + height, height), fill=(255, 255, 255, 18), width=2)

    image.alpha_composite(overlay)
    image.alpha_composite(grid)
    return image


def draw_pill(draw: ImageDraw.ImageDraw, rect: tuple[int, int, int, int], fill: tuple[int, int, int, int], text: str, text_fill: tuple[int, int, int, int], font: ImageFont.FreeTypeFont) -> None:
    draw.rounded_rectangle(rect, radius=(rect[3] - rect[1]) // 2, fill=fill)
    text_box = draw.textbbox((0, 0), text, font=font)
    text_x = rect[0] + (rect[2] - rect[0] - text_box[2]) / 2
    text_y = rect[1] + (rect[3] - rect[1] - text_box[3]) / 2 - 2
    draw.text((text_x, text_y), text, font=font, fill=text_fill)


def draw_small_icon(draw: ImageDraw.ImageDraw, center: tuple[int, int], radius: int, fill: tuple[int, int, int, int], symbol: str, symbol_font: ImageFont.FreeTypeFont) -> None:
    draw.ellipse((center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius), fill=fill)
    font = symbol_font
    if len(symbol) > 1:
        font = fit_text(draw, symbol, radius * 2 - 10, symbol_font.size - 6, min_size=12, bold=True)
    bbox = draw.textbbox((0, 0), symbol, font=font)
    draw.text((center[0] - bbox[2] / 2, center[1] - bbox[3] / 2 - 2), symbol, font=font, fill=(24, 53, 86, 255))


def screen_background(spec: DeviceSpec) -> Image.Image:
    image = Image.new("RGBA", (spec.width, spec.height), "#EEF4FB")
    overlay = Image.new("RGBA", (spec.width, spec.height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.ellipse((-180, 220, int(spec.width * 0.58), int(spec.height * 0.48)), fill=(82, 198, 222, 26))
    draw.ellipse((int(spec.width * 0.48), int(spec.height * 0.66), int(spec.width * 1.06), int(spec.height * 1.08)), fill=(33, 108, 176, 18))
    overlay = overlay.filter(ImageFilter.GaussianBlur(56))
    image.alpha_composite(overlay)
    return image


def draw_phone_ui(spec: DeviceSpec) -> Image.Image:
    image = screen_background(spec)
    draw = ImageDraw.Draw(image)

    title_font = load_font(54, bold=True)
    section_font = load_font(34, bold=True)
    body_font = load_font(26)
    strong_font = load_font(28, bold=True)
    tiny_font = load_font(20, bold=True)
    pill_font = load_font(20, bold=True)
    icon_font = load_font(24, bold=True)

    draw.text((86, 54), "09:41", font=load_font(34, bold=True), fill=(12, 21, 36, 255))
    island = (spec.width // 2 - 125, 42, spec.width // 2 + 125, 118)
    draw.rounded_rectangle(island, radius=38, fill=(0, 0, 0, 255))

    action_bar = (spec.width - 510, 118, spec.width - 86, 210)
    draw.rounded_rectangle(action_bar, radius=44, fill=(255, 255, 255, 180), outline=(255, 255, 255, 110), width=2)
    draw_small_icon(draw, (action_bar[0] + 76, 164), 34, (245, 249, 253, 255), "AI", icon_font)
    draw_small_icon(draw, (action_bar[0] + 210, 164), 34, (245, 249, 253, 255), "SC", icon_font)
    draw_small_icon(draw, (action_bar[0] + 344, 164), 34, (69, 180, 214, 255), "+", icon_font)

    draw.text((86, 252), "Email scan", font=load_font(70, bold=True), fill=(30, 56, 92, 255))
    draw.text((86, 338), "Find renewals, invoices, and recurring charges from one selected mailbox.", font=load_font(31), fill=(87, 109, 138, 255))

    hero = (58, 422, spec.width - 58, 870)
    draw.rounded_rectangle(hero, radius=58, fill=(241, 248, 253, 210), outline=(255, 255, 255, 150), width=3)

    mailbox = (92, 470, spec.width - 92, 560)
    draw.rounded_rectangle(mailbox, radius=34, fill=(255, 255, 255, 220))
    draw.text((126, 496), "CONNECTED MAILBOX", font=tiny_font, fill=(102, 123, 149, 255))
    draw.text((126, 526), "ali.ozkul@icloud.com", font=strong_font, fill=(27, 49, 78, 255))
    draw_pill(draw, (spec.width - 292, 488, spec.width - 124, 544), (231, 247, 252, 255), "INBOX", (37, 130, 163, 255), pill_font)

    progress = (92, 590, spec.width - 92, 832)
    draw.rounded_rectangle(progress, radius=40, fill=(255, 255, 255, 218))
    draw.text((126, 626), "LIVE EMAIL DISCOVERY", font=tiny_font, fill=(96, 120, 148, 255))
    draw.text((126, 660), "This first scan may take a little longer while PayGuard checks mailbox history.", font=body_font, fill=(68, 92, 123, 255))
    draw_pill(draw, (126, 724, 386, 786), (236, 250, 253, 255), "4 subscriptions found", (29, 139, 169, 255), load_font(22, bold=True))
    bar = (126, 800, spec.width - 126, 824)
    draw.rounded_rectangle(bar, radius=12, fill=(226, 234, 243, 255))
    draw.rounded_rectangle((bar[0], bar[1], int(bar[0] + (bar[2] - bar[0]) * 0.72), bar[3]), radius=12, fill=(73, 191, 220, 255))

    section_y = 926
    draw.text((86, section_y), "Detected subscriptions", font=section_font, fill=(48, 72, 103, 255))

    results = [
        ("Apple TV", "Recurring invoice • Monthly", "€9.99", "CONFIRMED"),
        ("ChatGPT Plus", "Renewal email • Monthly", "€22.99", "CONFIRMED"),
        ("Lingard Pro", "Subscription renewal • Quarterly", "€35.99", "CONFIRMED"),
        ("Resume Genius", "Trial converted • Monthly", "€24.95", "REVIEWED"),
    ]

    y = section_y + 66
    for index, (name, subtitle, price, badge) in enumerate(results):
        card = (58, y, spec.width - 58, y + 204)
        draw.rounded_rectangle(card, radius=42, fill=(255, 255, 255, 228))
        draw_small_icon(draw, (122, y + 76), 34, (229, 245, 251, 255), name[:1].upper(), icon_font)
        draw.text((176, y + 42), name, font=fit_text(draw, name, 560, 36), fill=(29, 52, 80, 255))
        draw.text((176, y + 92), subtitle, font=body_font, fill=(98, 122, 149, 255))
        draw.text((spec.width - 298, y + 44), price, font=load_font(34, bold=True), fill=(27, 49, 78, 255))
        draw_pill(
            draw,
            (176, y + 136, 398 if badge == "CONFIRMED" else 378, y + 182),
            (244, 250, 253, 255),
            badge,
            (64, 141, 166, 255),
            load_font(18, bold=True),
        )
        chevron_font = load_font(32, bold=True)
        draw.text((spec.width - 114, y + 78), "›", font=chevron_font, fill=(173, 188, 205, 255))
        y += 224
        if index == 2:
            break

    bottom_bar = (70, spec.height - 130, spec.width - 70, spec.height - 54)
    draw.rounded_rectangle(bottom_bar, radius=38, fill=(248, 251, 253, 235))
    draw.text((134, spec.height - 108), "Search", font=load_font(32), fill=(113, 129, 149, 255))
    draw.text((90, spec.height - 110), "Q", font=load_font(30, bold=True), fill=(23, 31, 45, 255))
    return image


def draw_tablet_ui(spec: DeviceSpec) -> Image.Image:
    image = screen_background(spec)
    draw = ImageDraw.Draw(image)

    section_font = load_font(40, bold=True)
    body_font = load_font(28)
    strong_font = load_font(34, bold=True)
    tiny_font = load_font(22, bold=True)
    pill_font = load_font(20, bold=True)
    icon_font = load_font(26, bold=True)

    draw.text((34, 34), "09:41   Sat May 6", font=load_font(28, bold=True), fill=(12, 21, 36, 255))
    action_bar = (spec.width - 690, 44, spec.width - 520, 138)
    draw.rounded_rectangle(action_bar, radius=44, fill=(255, 255, 255, 180), outline=(255, 255, 255, 110), width=2)
    draw_small_icon(draw, (action_bar[0] + 72, 91), 34, (245, 249, 253, 255), "AI", icon_font)
    draw_small_icon(draw, (action_bar[0] + 206, 91), 34, (245, 249, 253, 255), "SC", icon_font)
    draw_small_icon(draw, (action_bar[0] + 340, 91), 34, (69, 180, 214, 255), "+", icon_font)
    search = (spec.width - 468, 44, spec.width - 40, 138)
    draw.rounded_rectangle(search, radius=44, fill=(249, 252, 254, 220))
    draw.text((search[0] + 84, 74), "Search", font=load_font(28), fill=(108, 126, 147, 255))
    draw.text((search[0] + 36, 72), "Q", font=load_font(28, bold=True), fill=(23, 31, 45, 255))

    draw.text((66, 170), "Email scan", font=load_font(80, bold=True), fill=(30, 56, 92, 255))
    draw.text((66, 254), "Scan one selected mailbox, validate recurring billing signals, and review detected subscriptions before saving.", font=load_font(33), fill=(87, 109, 138, 255))

    left_card = (38, 350, 930, 1120)
    right_card = (972, 350, spec.width - 38, 1120)
    draw.rounded_rectangle(left_card, radius=58, fill=(241, 248, 253, 210), outline=(255, 255, 255, 150), width=3)
    draw.rounded_rectangle(right_card, radius=58, fill=(241, 248, 253, 210), outline=(255, 255, 255, 150), width=3)

    draw.text((78, 402), "SCAN STATUS", font=tiny_font, fill=(100, 122, 149, 255))
    draw.text((78, 444), "Connected mailbox", font=section_font, fill=(35, 61, 92, 255))
    draw.rounded_rectangle((78, 510, 888, 630), radius=36, fill=(255, 255, 255, 228))
    draw.text((118, 546), "ali.ozkul@icloud.com", font=strong_font, fill=(26, 48, 78, 255))
    draw_pill(draw, (694, 538, 848, 596), (230, 246, 251, 255), "INBOX", (37, 130, 163, 255), pill_font)

    draw.rounded_rectangle((78, 674, 888, 1032), radius=40, fill=(255, 255, 255, 220))
    draw.text((118, 718), "FIRST SCAN NOTE", font=tiny_font, fill=(96, 120, 148, 255))
    draw.text((118, 760), "The first pass can take a little longer because PayGuard checks mailbox history and confirms recurring results one by one.", font=body_font, fill=(69, 92, 123, 255))
    draw_pill(draw, (118, 888, 440, 952), (236, 250, 253, 255), "4 subscriptions found", (29, 139, 169, 255), load_font(24, bold=True))
    draw.rounded_rectangle((118, 980, 848, 1006), radius=13, fill=(228, 235, 243, 255))
    draw.rounded_rectangle((118, 980, 654, 1006), radius=13, fill=(73, 191, 220, 255))

    draw.text((1012, 402), "CONFIRMED RESULTS", font=tiny_font, fill=(100, 122, 149, 255))
    draw.text((1012, 444), "Detected subscriptions", font=section_font, fill=(35, 61, 92, 255))

    results = [
        ("Apple TV", "Recurring invoice • Monthly", "€9.99"),
        ("ChatGPT Plus", "Renewal email • Monthly", "€22.99"),
        ("Lingard Pro", "Subscription renewal • Quarterly", "€35.99"),
        ("Resume Genius", "Trial converted • Monthly", "€24.95"),
    ]
    y = 520
    for name, subtitle, price in results:
        card = (1012, y, spec.width - 78, y + 124)
        draw.rounded_rectangle(card, radius=34, fill=(255, 255, 255, 226))
        draw_small_icon(draw, (1064, y + 62), 28, (229, 245, 251, 255), name[:1].upper(), icon_font)
        draw.text((1114, y + 26), name, font=fit_text(draw, name, 420, 30), fill=(29, 52, 80, 255))
        draw.text((1114, y + 66), subtitle, font=load_font(22), fill=(98, 122, 149, 255))
        draw.text((spec.width - 274, y + 30), price, font=load_font(30, bold=True), fill=(27, 49, 78, 255))
        draw.text((spec.width - 102, y + 50), "›", font=load_font(30, bold=True), fill=(173, 188, 205, 255))
        y += 144

    lower = (38, 1180, spec.width - 38, spec.height - 118)
    draw.rounded_rectangle(lower, radius=58, fill=(241, 248, 253, 205), outline=(255, 255, 255, 140), width=3)
    draw.text((78, 1240), "EMAIL EVIDENCE PREVIEW", font=tiny_font, fill=(100, 122, 149, 255))
    draw.text((78, 1280), "Each result stays reviewable before import, with sender trust, recurring clues, and amount evidence kept visible.", font=load_font(30), fill=(69, 92, 123, 255))

    preview_cards = [
        (78, 1384, 648, 1760, "Apple TV", "Trusted Apple sender\nMonthly cycle detected\nRenewal date found"),
        (710, 1384, 1280, 1760, "ChatGPT Plus", "Invoice matched\nRecurring billing signal\nAmount extracted"),
        (1342, 1384, 1926, 1760, "Lingard Pro", "Quarterly renewal\nSubscription context confirmed\nDraft ready"),
    ]
    for x1, y1, x2, y2, title, lines in preview_cards:
        draw.rounded_rectangle((x1, y1, x2, y2), radius=38, fill=(255, 255, 255, 226))
        draw.text((x1 + 34, y1 + 30), title, font=load_font(30, bold=True), fill=(28, 51, 80, 255))
        draw_multiline(draw, lines, load_font(24), (95, 118, 146, 255), (x1 + 34, y1 + 92, x2 - 34, y2 - 34), 10)

    bottom_bar = (spec.width - 620, spec.height - 102, spec.width - 52, spec.height - 34)
    draw.rounded_rectangle(bottom_bar, radius=34, fill=(248, 251, 253, 235))
    draw.text((bottom_bar[0] + 84, bottom_bar[1] + 18), "Search", font=load_font(26), fill=(113, 129, 149, 255))
    draw.text((bottom_bar[0] + 34, bottom_bar[1] + 14), "Q", font=load_font(26, bold=True), fill=(23, 31, 45, 255))
    return image


def build_raw_email_scan(spec: DeviceSpec) -> Path:
    image = draw_tablet_ui(spec) if spec.is_tablet else draw_phone_ui(spec)
    spec.raw_dir.mkdir(parents=True, exist_ok=True)
    output = spec.raw_dir / "07-email-scan.png"
    image.convert("RGB").save(output, quality=95)
    return output


def build_final_slide(spec: DeviceSpec, raw_path: Path) -> Path:
    screenshot = Image.open(raw_path).convert("RGBA")
    canvas = create_background(spec.width, spec.height)
    draw = ImageDraw.Draw(canvas)

    title_font = load_font(spec.title_size, bold=True)
    detail_font = load_font(spec.detail_size)
    eyebrow_font = load_font(spec.eyebrow_size, bold=True)
    badge_font = load_font(spec.badge_size, bold=True)

    left = 106 if not spec.is_tablet else 126
    right = spec.width - left
    top_y = 150 if not spec.is_tablet else 140

    draw.rounded_rectangle((left, top_y, left + (220 if not spec.is_tablet else 248), top_y + 56), radius=28, fill=(255, 255, 255, 38))
    draw.text((left + 24, top_y + 14), "EMAIL SCAN", font=eyebrow_font, fill=(227, 248, 255, 255))

    title = "Turn renewal emails into ready-to-review subscriptions."
    detail = "Scan one selected mailbox, surface recurring invoices and renewals, and confirm detected subscriptions before saving anything."
    draw_multiline(draw, title, title_font, (255, 255, 255, 255), (left, top_y + 112, right - 40, top_y + 430), spacing=10)
    draw_multiline(draw, detail, detail_font, (226, 240, 252, 228), (left, top_y + 472, right - 20, top_y + 720), spacing=8)

    card_width = spec.width - spec.card_width_margin
    max_card_height = spec.height - spec.card_top - spec.card_bottom_margin
    scale = min(card_width / screenshot.width, max_card_height / screenshot.height)
    scaled = screenshot.resize((int(screenshot.width * scale), int(screenshot.height * scale)), Image.Resampling.LANCZOS)

    shadow = Image.new("RGBA", (scaled.width + 80, scaled.height + 80), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((20, 20, scaled.width + 60, scaled.height + 60), radius=spec.card_corner_radius + 2, fill=(3, 9, 19, 180))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.alpha_composite(shadow, ((spec.width - shadow.width) // 2, spec.card_top - 20))

    card = Image.new("RGBA", (scaled.width + 44, scaled.height + 44), (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card)
    card_draw.rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=spec.card_corner_radius, fill=(255, 255, 255, 242), outline=(255, 255, 255, 46), width=2)
    card.paste(scaled, (22, 22), rounded_mask(scaled.size, spec.screenshot_corner_radius))
    canvas.alpha_composite(card, ((spec.width - card.width) // 2, spec.card_top))

    badge_box = (left, spec.height - 244, left + 246, spec.height - 162) if not spec.is_tablet else (left, spec.height - 184, left + 286, spec.height - 92)
    draw.rounded_rectangle(badge_box, radius=30, fill=(255, 255, 255, 32))
    draw.text((badge_box[0] + 24, badge_box[1] + 18), "PAYGUARD", font=badge_font, fill=(14, 42, 72, 255))

    icon = Image.open(ICON_PATH).convert("RGBA").resize((98 if not spec.is_tablet else 112, 98 if not spec.is_tablet else 112), Image.Resampling.LANCZOS)
    card_size = 130 if not spec.is_tablet else 146
    icon_card = Image.new("RGBA", (card_size, card_size), (0, 0, 0, 0))
    icon_draw = ImageDraw.Draw(icon_card)
    icon_draw.rounded_rectangle((0, 0, card_size - 1, card_size - 1), radius=34 if not spec.is_tablet else 40, fill=(255, 255, 255, 242))
    icon_card.paste(icon, ((card_size - icon.width) // 2, (card_size - icon.height) // 2), icon)
    canvas.alpha_composite(icon_card, (spec.width - 210 if not spec.is_tablet else spec.width - 250, 156 if not spec.is_tablet else 134))

    spec.final_dir.mkdir(parents=True, exist_ok=True)
    output = spec.final_dir / "07-07-email-scan.png"
    canvas.convert("RGB").save(output, quality=95)
    return output


def main() -> None:
    outputs: list[Path] = []
    for spec in (PHONE, TABLET):
        raw_path = build_raw_email_scan(spec)
        outputs.append(raw_path)
        outputs.append(build_final_slide(spec, raw_path))
    print("\n".join(str(path) for path in outputs))


if __name__ == "__main__":
    main()
