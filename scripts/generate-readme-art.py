#!/usr/bin/env python3
"""Render the website's typography as self-contained, GitHub-safe SVG paths.

Requires fontTools. Uses the committed, unmodified OFL fonts; no system fonts,
external resources, embedded HTML, or scripts are needed to display the artwork.
"""
from pathlib import Path
from xml.sax.saxutils import escape

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs/images/readme"
FONT = TTFont(ASSETS / "fonts/BarlowCondensed-ExtraLight.ttf")
LIGHT = TTFont(ASSETS / "fonts/BarlowCondensed-Light.ttf")
BLUE, PAPER, INK = "#0808f2", "#f4f4f0", "#15116d"


def lettering(text, x, baseline, size, font=FONT, color=PAPER, spacing=0):
    """Keep the original glyph outlines; convert font coordinates to SVG."""
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    parts = [f'<g fill="{color}" aria-label="{escape(text)}">']
    for character in text:
        name = cmap[ord(character)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(pen)
        parts.append(f'<path transform="translate({x:.3f} {baseline}) scale({scale} {-scale})" d="{pen.getCommands()}"/>')
        x += glyphs[name].width * scale + spacing
    parts.append("</g>")
    return "\n".join(parts)


def write_svg(path, width, height, title, body):
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title">\n'
        f'<title id="title">{escape(title)}</title>\n{body}\n</svg>\n'
    )


def banner():
    # Same 160 × 64 flat-top silhouette and eye placement as the app icon's
    # native renderer (scripts/generate-aisland-appicon.swift).
    eyes = []
    for x in [47, 65]:
        pen = SVGPathPen(None)
        # Outline the capsule directly to avoid renderer-dependent nested
        # rotation behavior. This is the app icon's original -8° SVG tilt.
        rotated = TransformPen(pen, (.990268, -.139173, .139173, .990268, x, 32))
        rotated.moveTo((0, -9.2))
        rotated.curveTo((2.375, -9.2), (4.3, -7.275), (4.3, -4.9))
        rotated.lineTo((4.3, 4.9))
        rotated.curveTo((4.3, 7.275), (2.375, 9.2), (0, 9.2))
        rotated.curveTo((-2.375, 9.2), (-4.3, 7.275), (-4.3, 4.9))
        rotated.lineTo((-4.3, -4.9))
        rotated.curveTo((-4.3, -7.275), (-2.375, -9.2), (0, -9.2))
        rotated.closePath()
        eyes.append(f'<path d="{pen.getCommands()}" fill="#f1ead9"/>')
    mark = f'''<g transform="translate(1120 177) scale(2.4)">
      <path d="M0 0H160V32A32 32 0 0 1 128 64H32A32 32 0 0 1 0 32Z" fill="#0d0d0f"/>
      {''.join(eyes)}
      <circle cx="116" cy="32" r="6" fill="#3674f5"/>
    </g>'''
    body = f'''<rect width="1600" height="500" fill="{BLUE}"/>
    <path d="M80 86H1520" stroke="{PAPER}" stroke-opacity=".24"/>
    <g fill="none" stroke="{PAPER}" stroke-width="1.2" stroke-opacity=".15">
      <path d="M970 150H1010Q1060 150 1060 200V245H1120"/>
      <path d="M970 400H1020Q1090 400 1090 330V255H1120"/>
      <path d="M1490 129V150Q1490 177 1462 177"/>
    </g>
    {lettering('AISLAND', 80, 60, 37, LIGHT, spacing=2)}
    {lettering('NATIVE MACOS / LOCAL FIRST / OPEN SOURCE', 1020, 58, 25, LIGHT, spacing=.5)}
    {lettering('ALL AGENTS.', 74, 258, 182, spacing=-1.1)}
    {lettering('ONE ISLAND.', 74, 426, 182, spacing=-1.1)}
    {mark}
    {lettering('LESS SWITCHING.', 1120, 389, 35, LIGHT)}
    {lettering('MORE BUILDING.', 1120, 433, 35, LIGHT)}'''
    write_svg(ROOT / "docs/images/readme-banner.svg", 1600, 500,
              "AIsland — All agents. One island. Native macOS, local first, open source.", body)


def divider():
    body = f'''<rect width="1600" height="180" fill="{PAPER}"/>
    <path d="M64 38H1536" stroke="{INK}" stroke-opacity=".18"/>
    {lettering('IN SYNC WITH YOU.', 64, 133, 76, color=INK)}
    {lettering('OBSERVE / DECIDE / RETURN', 1190, 127, 26, LIGHT, INK)}'''
    write_svg(ASSETS / "workflow.svg", 1600, 180,
              "In sync with you. Observe, decide, return.", body)


if __name__ == "__main__":
    banner()
    divider()
    print("Rendered README banner and workflow divider with outlined Barlow Condensed.")
