"""Generates every platform app icon from one vector design.

Run from the repo root:  python3 app/tool/icon/make_icons.py
Needs: pip install cairosvg pillow
"""
import io, json, math, os
import cairosvg
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
OUT_SVG = os.path.join(os.path.dirname(__file__), 'icon.svg')

BG_TOP, BG_BOT = '#4A3420', '#1E140C'


def gear_path(cx, cy, r_out, r_in, teeth):
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4)
        r = r_out if (i % 4) in (1, 2) else r_in
        pts.append(f'{cx + r * math.cos(a):.1f},{cy + r * math.sin(a):.1f}')
    return 'M' + ' L'.join(pts) + ' Z'


def art(scale=1.0, small=False):
    """The column, centred on a 1024 canvas, scaled about the centre."""
    rivets = ''
    for y in (352, 548, 744):
        for x in (398, 455, 512, 569, 626):
            rivets += f'<circle cx="{x}" cy="{y}" r="7" fill="url(#rivet)"/>'
    bands = ''.join(
        f'<rect x="356" y="{y - 24}" width="312" height="48" rx="8" fill="url(#band)" stroke="#2A1B0E" stroke-width="5"/>'
        for y in (352, 548, 744))
    if small:
        rivets = ''
    hl = '' if small else '<path d="M414 840 V290 A100 100 0 0 1 462 206" fill="none" stroke="#FFE7A8" stroke-opacity="0.55" stroke-width="14" stroke-linecap="round"/>'
    return f'''
<g transform="translate(512 512) scale({scale}) translate(-512 -512)">
  <!-- overhead vapour line -->
  <path d="M512 150 V114 Q512 88 538 88 H716 Q746 88 746 118 V280" fill="none" stroke="#2A1B0E" stroke-width="50" stroke-linecap="round"/>
  <path d="M512 150 V114 Q512 88 538 88 H716 Q746 88 746 118 V280" fill="none" stroke="url(#pipe)" stroke-width="34" stroke-linecap="round"/>
  <rect x="716" y="262" width="60" height="24" rx="6" fill="url(#band)" stroke="#2A1B0E" stroke-width="5"/>
  <!-- shell -->
  <path d="M372 860 V280 A140 140 0 0 1 652 280 V860 Z" fill="url(#shell)" stroke="#2A1B0E" stroke-width="10"/>
  {hl}
  {bands}{rivets}
  <!-- gauge -->
  <circle cx="512" cy="450" r="70" fill="url(#band)" stroke="#2A1B0E" stroke-width="8"/>
  <circle cx="512" cy="450" r="50" fill="#E9D8B4" stroke="#2A1B0E" stroke-width="4"/>
  <path d="M478 466 A38 38 0 0 1 546 466" fill="none" stroke="#3B2A1A" stroke-width="5"/>
  <line x1="512" y1="450" x2="540" y2="424" stroke="#8B2E1F" stroke-width="9" stroke-linecap="round"/>
  <circle cx="512" cy="450" r="9" fill="#3B2A1A"/>
  <!-- skirt + base plate -->
  <path d="M384 860 L352 912 H672 L640 860 Z" fill="url(#band)" stroke="#2A1B0E" stroke-width="8" stroke-linejoin="round"/>
  <rect x="306" y="904" width="412" height="30" rx="10" fill="#7A4A22" stroke="#2A1B0E" stroke-width="8"/>
</g>'''


DEFS = f'''
<defs>
  <radialGradient id="bg" cx="50%" cy="35%" r="75%">
    <stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOT}"/>
  </radialGradient>
  <linearGradient id="shell" x1="0" x2="1" y1="0" y2="0">
    <stop offset="0" stop-color="#6E3A16"/><stop offset="0.28" stop-color="#E0A85A"/>
    <stop offset="0.5" stop-color="#C47A3A"/><stop offset="1" stop-color="#5A2E12"/>
  </linearGradient>
  <linearGradient id="band" x1="0" x2="1" y1="0" y2="0">
    <stop offset="0" stop-color="#8A6420"/><stop offset="0.3" stop-color="#F2CF6E"/>
    <stop offset="0.6" stop-color="#C89B3C"/><stop offset="1" stop-color="#6E4E18"/>
  </linearGradient>
  <linearGradient id="pipe" x1="0" x2="0" y1="0" y2="1">
    <stop offset="0" stop-color="#E9B46A"/><stop offset="1" stop-color="#8A4E20"/>
  </linearGradient>
  <radialGradient id="rivet" cx="35%" cy="35%" r="70%">
    <stop offset="0" stop-color="#FFF0C0"/><stop offset="1" stop-color="#5A3E12"/>
  </radialGradient>
</defs>'''


def svg(background, scale, small=False):
    """background: 'full' (square, no alpha), 'rounded' (inset tile), 'squircle' (macOS), None."""
    gear = '' if small else f'<path d="{gear_path(512, 520, 400, 352, 14)}" fill="none" stroke="#C89B3C" stroke-opacity="0.14" stroke-width="22" stroke-linejoin="round"/>'
    if background == 'full':
        bg = f'<rect width="1024" height="1024" fill="url(#bg)"/>{gear}'
    elif background == 'rounded':
        bg = f'<rect x="16" y="16" width="992" height="992" rx="200" fill="url(#bg)" stroke="#C89B3C" stroke-width="12"/>{gear}'
    elif background == 'squircle':  # Apple macOS grid: 824 tile, 100 inset
        bg = f'<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)" stroke="#C89B3C" stroke-width="10"/>'
        bg += f'<g transform="translate(512 512) scale(0.8) translate(-512 -512)">{gear}</g>'
    else:
        bg = ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{DEFS}{bg}{art(scale, small)}</svg>'


def render(svg_text, size, alpha=True):
    if callable(svg_text):
        svg_text = svg_text(size <= 48)
    png = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=size, output_height=size)
    im = Image.open(io.BytesIO(png)).convert('RGBA')
    if not alpha:
        flat = Image.new('RGB', im.size, BG_BOT)
        flat.paste(im, mask=im.split()[3])
        return flat
    return im


def save(im, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=True)


def main():
    # Each variant is a function of `small`: tiny sizes drop the gear and rivets.
    full = lambda small: svg('full', 0.92, small)
    rounded = lambda small: svg('rounded', 0.86 if small else 0.82, small)
    squircle = lambda small: svg('squircle', 0.66, small)
    fg = lambda small: svg(None, 0.56, small)
    with open(OUT_SVG, 'w') as f:
        f.write(rounded(False))

    # iOS: full-bleed square, no alpha (iOS applies its own mask).
    ios = os.path.join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')
    for img in json.load(open(os.path.join(ios, 'Contents.json')))['images']:
        pt = float(img['size'].split('x')[0])
        px = round(pt * int(img['scale'][0]))
        save(render(full, px, alpha=False), ios, img['filename'])

    # macOS: Apple's inset tile.
    mac = os.path.join(ROOT, 'macos/Runner/Assets.xcassets/AppIcon.appiconset')
    for img in json.load(open(os.path.join(mac, 'Contents.json')))['images']:
        pt = float(img['size'].split('x')[0])
        px = round(pt * int(img['scale'][0]))
        save(render(squircle, px), mac, img['filename'])

    # Android: legacy launcher + adaptive foreground (108dp, 72dp safe zone).
    res = 'android/app/src/main/res'
    for d, legacy, adaptive in (('mdpi', 48, 108), ('hdpi', 72, 162), ('xhdpi', 96, 216),
                                ('xxhdpi', 144, 324), ('xxxhdpi', 192, 432)):
        save(render(rounded, legacy), res, f'mipmap-{d}', 'ic_launcher.png')
        save(render(fg, adaptive), res, f'mipmap-{d}', 'ic_launcher_foreground.png')

    # Web.
    save(render(rounded, 32), 'web/favicon.png')
    save(render(rounded, 192), 'web/icons/Icon-192.png')
    save(render(rounded, 512), 'web/icons/Icon-512.png')
    maskable = lambda small: svg('full', 0.62, small)  # maskable safe zone is the central 80% circle
    save(render(maskable, 192, alpha=False), 'web/icons/Icon-maskable-192.png')
    save(render(maskable, 512, alpha=False), 'web/icons/Icon-maskable-512.png')

    # Windows .ico (multi-size).
    ico = [render(rounded, n) for n in (256, 128, 64, 48, 32, 24, 16)]
    ico[0].save(os.path.join(ROOT, 'windows/runner/resources/app_icon.ico'),
                sizes=[im.size for im in ico], append_images=ico[1:])

    # Linux: bundled PNG the runner loads as the window icon.
    save(render(rounded, 256), 'linux/runner/resources/app_icon.png')


if __name__ == '__main__':
    main()
