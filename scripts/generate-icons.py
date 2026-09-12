"""Deterministic functional status icons. Requires Pillow; generated ICOs are committed."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "assets" / "icons"
root.mkdir(parents=True, exist_ok=True)
colors = {"todo": "#64748B", "doing": "#1976D2", "done": "#008875", "issue": "#D74436", "app": "#008875"}
for name, color in colors.items():
    image = Image.new("RGBA", (256, 256))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((18, 47, 125, 109), radius=14, fill="#D89213")
    draw.rounded_rectangle((18, 73, 237, 215), radius=18, fill="#F1B939")
    draw.rounded_rectangle((18, 90, 237, 215), radius=18, fill="#F9CC62")
    draw.ellipse((131, 133, 250, 252), fill="#FFFFFF")
    draw.ellipse((139, 141, 242, 244), fill=color)
    if name in ("done", "app"):
        draw.line([(161, 191), (183, 213), (222, 171)], fill="white", width=13, joint="curve")
    elif name == "doing":
        draw.arc((160, 161, 222, 223), -80, 190, fill="white", width=10)
        draw.polygon([(151, 185), (174, 184), (163, 204)], fill="white")
    elif name == "todo":
        draw.ellipse((165, 166, 217, 218), outline="white", width=9)
    else:
        draw.rounded_rectangle((186, 161, 197, 201), radius=5, fill="white")
        draw.ellipse((185, 213, 198, 226), fill="white")
    image.save(root / f"{name}.ico", sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
print(f"Generated {len(colors)} multi-resolution icons in {root}")
