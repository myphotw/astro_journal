"""Generate Android/iOS/Web launcher icons from assets/icon/app_icon.png."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "icon" / "app_icon.png"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICON_DIR = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WEB_ICON_DIR = ROOT / "web" / "icons"
WINDOWS_ICON = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

ANDROID_LAUNCHER_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ANDROID_FOREGROUND_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

IOS_ICONS = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

WEB_ICONS = [
    ("Icon-192.png", 192),
    ("Icon-512.png", 512),
    ("Icon-maskable-192.png", 192),
    ("Icon-maskable-512.png", 512),
]


def _resize(src: Image.Image, size: int) -> Image.Image:
    return src.resize((size, size), Image.Resampling.LANCZOS)


def _save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def _write_android_adaptive_files() -> None:
    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    values = ANDROID_RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    colors_path = values / "ic_launcher_colors.xml"
    colors_path.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="ic_launcher_background">#080B14</color>
</resources>
""",
        encoding="utf-8",
    )


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Missing source icon: {SRC}")

    source = Image.open(SRC).convert("RGBA")

    for folder, size in ANDROID_LAUNCHER_SIZES.items():
        _save_png(_resize(source, size), ANDROID_RES / folder / "ic_launcher.png")

    for folder, size in ANDROID_FOREGROUND_SIZES.items():
        _save_png(
            _resize(source, size),
            ANDROID_RES / folder / "ic_launcher_foreground.png",
        )

    _write_android_adaptive_files()

    IOS_ICON_DIR.mkdir(parents=True, exist_ok=True)
    for filename, size in IOS_ICONS:
        _save_png(_resize(source, size), IOS_ICON_DIR / filename)

    WEB_ICON_DIR.mkdir(parents=True, exist_ok=True)
    for filename, size in WEB_ICONS:
        _save_png(_resize(source, size), WEB_ICON_DIR / filename)

    WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)
    ico_sizes = [16, 32, 48, 64, 128, 256]
    source.save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
    )

    print(f"Generated launcher icons from {SRC}")


if __name__ == "__main__":
    main()
