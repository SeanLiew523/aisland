"""Project mathematical surfaces into reusable, theme-aware wire geometry.

No product UI is drawn here. All native demonstration pixels remain recorded.
"""
from math import cos, sin, pi
from pathlib import Path


def project(point):
    x, y, z = point
    yaw, pitch = -.32, .66
    x, z = x * cos(yaw) + z * sin(yaw), -x * sin(yaw) + z * cos(yaw)
    y, z = y * cos(pitch) - z * sin(pitch), y * sin(pitch) + z * cos(pitch)
    distance = 680 / (680 + z)
    return 250 + x * distance, 250 + y * distance


def path(points, klass="geometry-wire"):
    points = [project(p) for p in points]
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in points)
    return f'<path class="{klass}" d="{d}"/>'


def torus(u, v):
    return ((151 + 49 * cos(v)) * cos(u), (151 + 49 * cos(v)) * sin(u), 49 * sin(v))


def saddle(u, v):
    return u * 160, v * 160, 90 * (u * u - v * v)


def ribbon(u, v):
    angle = u * pi * 1.4
    return u * 190, sin(angle) * 58 + v * cos(angle) * 66, cos(angle) * 58 + v * sin(angle) * 66


def lattice(u, v):
    return 172 * sin(v) * cos(u), 172 * sin(v) * sin(u), 172 * cos(v)


def surface(name, fn, ulo, uhi, vlo, vhi, nu=25, nv=15):
    result = [f'<symbol id="{name}" viewBox="0 0 500 500"><g fill="none" stroke="currentColor" stroke-linecap="round">']
    for i in range(nu):
        u = ulo + (uhi - ulo) * i / (nu - 1)
        result.append(path([fn(u, vlo + (vhi - vlo) * j / 64) for j in range(65)]))
    for j in range(nv):
        v = vlo + (vhi - vlo) * j / (nv - 1)
        result.append(path([fn(ulo + (uhi - ulo) * i / 80, v) for i in range(81)]))
    # A few thicker moving traces and registration nodes communicate depth
    # without continuously recomputing hundreds of vertices in JavaScript.
    for k in range(3):
        v = vlo + (vhi - vlo) * (.22 + k * .25)
        result.append(path([fn(ulo + (uhi - ulo) * i / 80, v) for i in range(81)], "geometry-trace"))
        x, y = project(fn(ulo + (uhi - ulo) * (.2 + .23 * k), v))
        result.append(f'<circle class="geometry-node" cx="{x:.1f}" cy="{y:.1f}" r="2.8" fill="currentColor"/>')
    result.append('</g></symbol>')
    return "".join(result)


assets = Path(__file__).resolve().parents[1] / "dist" / "assets"
svg = '<svg xmlns="http://www.w3.org/2000/svg">' + "".join([
    surface("torus", torus, 0, 2 * pi, 0, 2 * pi, 25, 13),
    surface("saddle", saddle, -1, 1, -1, 1, 23, 19),
    surface("ribbon", ribbon, -1, 1, -1, 1, 27, 13),
    surface("lattice", lattice, 0, 2 * pi, .06, pi - .06, 23, 16),
]) + '</svg>\n'
(assets / "chapter-geometry.svg").write_text(svg)
print(f"Generated {len(svg):,} bytes of mathematical geometry")
