"""Builds every app icon from one source: the crimson dithered moon.

The icon is a 24x24 grid of dots: the original moon disc (taken from
design/moon-icon/source.png) inset on a crimson square, its red patch as
a white ordered dither and the rest of the disc as a faint one. Sizes at or
above 24 px scale the grid up without smoothing so the dots stay square; 16 px
is reduced smoothly from 48 px. Run from the repository root:

    python tool/make_icons.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'design' / 'moon-icon' / 'source.png'
SQUARE, DOT = (165, 14, 30), (255, 242, 241)  # crimson square, warm-white dither
DOTS = 24
RED_DENSITY = (0.42, 0.72)  # white share across the red patch, light to dark
DISC_DENSITY = 0.14  # white share on the rest of the disc

_B4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])
BAYER8 = (np.array([[4 * _B4[y % 4, x % 4] + [[0, 2], [3, 1]][y // 4][x // 4]
                     for x in range(8)] for y in range(8)]) + 0.5) / 64


def dot_grid() -> np.ndarray:
    """The icon as a DOTS x DOTS boolean array, True for white."""
    canvas = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    disc = Image.open(SOURCE).convert('RGBA').resize((206, 206), Image.LANCZOS)
    canvas.paste(disc, (25, 25), disc)  # 80% disc, blue margin around it
    a = np.asarray(canvas).astype(float) / 255
    r, g, b, alpha = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    redness = np.clip(r - (g + b) / 2, 0, 1)
    red = (redness > 0.18) & (alpha > 0.5)
    disc_rest = ~red & (alpha > 0.5)
    lo, hi = np.percentile(redness[red], [5, 95])
    shade = np.clip((redness - lo) / (hi - lo + 1e-6), 0, 1)
    density = np.where(red, RED_DENSITY[0] + (RED_DENSITY[1] - RED_DENSITY[0]) * shade, 0)
    density += np.where(disc_rest, DISC_DENSITY, 0)
    small = Image.fromarray((np.clip(density, 0, 1) * 255).astype(np.uint8))
    v = np.asarray(small.resize((DOTS, DOTS), Image.BOX)).astype(float) / 255
    idx = np.arange(DOTS)
    return v > BAYER8[idx[:, None] % 8, idx[None, :] % 8]


def render(grid: np.ndarray, size: int) -> Image.Image:
    base = np.zeros((DOTS, DOTS, 3), np.uint8)
    base[:] = SQUARE
    base[grid] = DOT
    image = Image.fromarray(base)
    if size >= DOTS:
        return image.resize((size, size), Image.NEAREST)
    return image.resize((48, 48), Image.NEAREST).resize((size, size), Image.LANCZOS)


def main() -> None:
    grid = dot_grid()
    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    frames = [render(grid, s) for s in ico_sizes]
    for ico in ['windows/runner/resources/app_icon.ico', 'assets/tray_icon.ico']:
        frames[-1].save(ROOT / ico, sizes=[(s, s) for s in ico_sizes],
                        append_images=frames[:-1])
        print('wrote', ico)
    # Every platform PNG icon keeps its size and gets the new artwork.
    patterns = ['macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png',
                'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png',
                'android/app/src/main/res/mipmap-*/ic_launcher.png',
                'web/favicon.png', 'web/icons/*.png']
    for pattern in patterns:
        for path in sorted(ROOT.glob(pattern)):
            width, height = Image.open(path).size
            render(grid, width).save(path)
            print('wrote', path.relative_to(ROOT), width)
    render(grid, 512).save(ROOT / 'design' / 'moon-icon' / 'app-icon-512.png')


if __name__ == '__main__':
    main()
