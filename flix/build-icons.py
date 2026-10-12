#!/usr/bin/env python3
"""Turn the cone artwork into every icon surface the build and the installer use.

Source is the vector logo, modules/gui/qt/pixmaps/misc/cone.svg, rasterised with a
headless browser. That is the same drawing the interface shows, so the tray, the
window, the exe and the installer all carry one piece of art. Nothing here is
hand-drawn: edit the SVG, re-run, and every surface follows.

Writes, relative to the VLC source root:

    share/icons/<size>x<size>/vlc.png   the Qt window and tray icon, via assets.qrc
    share/icons/<size>x<size>/vlc-xmas.png, vlc-aprilfools.png, vlc-kb.png
                                        the seasonal and corporate variants, which the
                                        interface swaps in by date (qt.cpp picks the
                                        christmas one from day 354) and which were still
                                        carrying the stock VideoLAN artwork
    share/icons/vlc.ico                the exe icon, the installer icon, shortcuts
    extras/package/win32/NSIS/vlc_branding.bmp   the installer wizard banner
    share/lua/http/favicon.ico         the web interface tab icon
    share/lua/http/images/vlc16x16.png, vlc-48.png   the web interface header

Needs Pillow, and Chrome or Edge for the rasterising step:

    python -m pip install Pillow
    ./flix/build-icons.ps1
"""

import os
import shutil
import subprocess
import sys
import tempfile

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is not installed. Run:  python -m pip install Pillow")

# the sizes assets.qrc asks for, as <size>x<size> under share/icons
SIZES = (16, 32, 48, 128, 256)

# the resolution ladder written into vlc.ico
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)

# the variants assets.qrc names, as (size, [names]); see write_variants()
VARIANTS = (
    (16, ("vlc-xmas", "vlc-aprilfools")),
    (32, ("vlc-xmas", "vlc-aprilfools")),
    (48, ("vlc-xmas", "vlc-aprilfools")),
    (128, ("vlc-xmas", "vlc-aprilfools", "vlc-kb")),
    (256, ("vlc-xmas", "vlc-aprilfools")),
)

# the biggest raster we ask the browser for; everything else is scaled from it
RENDER = 1024

# NSIS welcome/finish banner; the stock one is this size
BRANDING_SIZE = (164, 314)

# the near-black the interface uses, so the banner does not flash white
BACKGROUND = (20, 20, 20, 255)

# where to look for a browser that can rasterise the SVG
BROWSERS = (
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
)


def source_root():
    """flix/build-icons.py -> the vlc source tree (the parent of flix/)."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def find_browser():
    for path in BROWSERS:
        if os.path.isfile(path):
            return path
    for name in ("chrome", "chrome.exe", "msedge", "msedge.exe"):
        found = shutil.which(name)
        if found:
            return found
    return None


def rasterise(svg, size):
    """Render the SVG square at `size` px and return it as a Pillow image."""
    browser = find_browser()
    if browser is None:
        sys.exit(
            "no browser found to rasterise the artwork.\n"
            "Install Chrome or Edge, or put chrome.exe on PATH, and re-run.\n"
            "(Qt, which draws the SVG in the interface, cannot render filters or "
            "write PNGs from the command line.)"
        )

    url = "file:///" + svg.replace("\\", "/")
    out = os.path.join(tempfile.mkdtemp(prefix="flixicons"), "cone.png")
    try:
        subprocess.run(
            [
                browser,
                "--headless",
                "--disable-gpu",
                "--hide-scrollbars",
                "--default-background-color=00000000",
                "--force-device-scale-factor=1",
                "--window-size=%d,%d" % (size, size),
                "--screenshot=" + out,
                url,
            ],
            check=True,
            capture_output=True,
            timeout=120,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        sys.exit("the browser failed to render the artwork: %s" % exc)
    if not os.path.isfile(out):
        sys.exit("the browser produced no image for %s" % svg)

    with Image.open(out) as img:
        return img.convert("RGBA")


def fit(img, box):
    """Largest centred copy of img that fits in box, so nothing is stretched."""
    scale = min(box[0] / img.width, box[1] / img.height)
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    return img.resize(size, Image.LANCZOS)


def write_png_sizes(art, root):
    for size in SIZES:
        folder = os.path.join(root, "share", "icons", f"{size}x{size}")
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "vlc.png")
        art.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)
        print(f"  {size:>3}x{size:<3} {path}")


def write_variants(art, root):
    """The seasonal and corporate icons, which are still stock VideoLAN artwork.

    assets.qrc pulls these in, and qt.cpp swaps the christmas one in from day 354 of
    the year - so leaving them behind means the fork quietly wears the old cone in
    December, and shows it in the About dialog and the plugins list all year round.
    """
    # only the sizes assets.qrc actually names
    for size, names in VARIANTS:
        folder = os.path.join(root, "share", "icons", f"{size}x{size}")
        if not os.path.isdir(folder):
            continue
        for name in names:
            path = os.path.join(folder, f"{name}.png")
            if not os.path.isfile(path):
                continue
            art.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)
            print(f"  {size:>3}x{size:<3} {path}")


def write_web(art, root):
    """The web interface's own icons, reached from share/lua/http/index.html."""
    http = os.path.join(root, "share", "lua", "http")
    favicon = os.path.join(http, "favicon.ico")
    if os.path.isfile(favicon):
        art.save(favicon, "ICO", sizes=[(s, s) for s in ICO_SIZES])
        print(f"  favicon {favicon}")

    images = os.path.join(http, "images")
    for name, size in (("vlc16x16.png", 16), ("vlc-48.png", 48)):
        path = os.path.join(images, name)
        if os.path.isfile(path):
            art.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)
            print(f"  web    {path}")


def write_ico(art, root):
    path = os.path.join(root, "share", "icons", "vlc.ico")
    art.save(path, "ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"  ico    {path}  ({', '.join(str(s) for s in ICO_SIZES)})")


def write_branding(art, root):
    path = os.path.join(root, "extras", "package", "win32", "NSIS", "vlc_branding.bmp")
    canvas = Image.new("RGBA", BRANDING_SIZE, BACKGROUND)
    art = fit(art, (BRANDING_SIZE[0] - 24, BRANDING_SIZE[0] - 24))
    canvas.alpha_composite(art, ((BRANDING_SIZE[0] - art.width) // 2, 24))
    # NSIS bitmaps carry no alpha
    canvas.convert("RGB").save(path, "BMP")
    print(f"  bmp    {path}  ({BRANDING_SIZE[0]}x{BRANDING_SIZE[1]})")


def touch_inputs(root):
    """Nudge the build files that embed these images.

    Neither build system declares the icons as prerequisites: bin/Makefile.am builds
    the resource script from vlc_win32_rc.rc.in without listing share/icons/vlc.ico,
    and modules/gui/qt regenerates assets.cpp from assets.qrc without listing the PNGs
    it pulls in. Without this, new artwork silently ships the old one.
    """
    for rel in (
        os.path.join("bin", "vlc_win32_rc.rc.in"),
        os.path.join("modules", "gui", "qt", "assets.qrc"),
    ):
        path = os.path.join(root, rel)
        if os.path.isfile(path):
            os.utime(path, None)
            print(f"  touch  {rel}  (so the build re-embeds the icons)")


def main():
    root = source_root()
    svg = os.path.join(root, "modules", "gui", "qt", "pixmaps", "misc", "cone.svg")
    if not os.path.isfile(svg):
        sys.exit(f"artwork not found: {svg}")

    print(f"artwork: {svg}")
    print(f"rendering at {RENDER}px with {find_browser()}")
    art = rasterise(svg, RENDER)
    print(f"writing into: {root}")
    write_png_sizes(art, root)
    write_variants(art, root)
    write_ico(art, root)
    write_branding(art, root)
    write_web(art, root)
    touch_inputs(root)


if __name__ == "__main__":
    main()