"""Render preview PNGs of the tube base with VTK (pyvista), off screen.

Four views per board: exterior, underside with tripod face + USB plug,
half section with the board envelope / tube / plug, and the lid.

    ~/.venvs/cad/bin/python fixtures/tubes/enclosure/render.py
"""
import numpy as np
import pyvista as pv

from build123d import Pos, Rot
import tube_base as tb

pv.OFF_SCREEN = True
COL = dict(body="#b0bec5", lid="#ffb74d", board="#2e7d32", stack="#a5d6a7",
           tube="#64b5f6", tripod="#37474f", plug="#ff7043")


def mesh(part, tol=0.05):
    verts, faces = part.tessellate(tol, 0.2)
    v = np.array([(p.X, p.Y, p.Z) for p in verts])
    f = np.hstack([np.full((len(faces), 1), 3), np.array(faces)]).ravel()
    return pv.PolyData(v, f).compute_normals(split_vertices=True, feature_angle=35)


def add(p, part, colour, opacity=1.0):
    p.add_mesh(mesh(part), color=colour, opacity=opacity, smooth_shading=True,
               specular=0.25, show_edges=False)


def render(board):
    bd, ld = tb.build(board)
    L = tb.layout(board)
    g = tb.ghosts(board)
    lid_in_place = Pos(0, 0, L["z_top"]) * (Rot(180, 0, 0) * ld)
    half = tb.box(-40, 80, 0, 40, -30, 140)   # removes the +Y half

    p = pv.Plotter(off_screen=True, shape=(1, 4), window_size=(2000, 560), border=False)
    p.set_background("white")

    p.subplot(0, 0)
    add(p, bd, COL["body"])
    add(p, Pos(0, 0, 8) * lid_in_place, COL["lid"])
    add(p, g["tube"], COL["tube"], 0.35)
    p.add_text("Exterior (lid lifted 8 mm)", font_size=10, color="black")
    p.camera_position = [(-110, -140, 120), (12, 0, 30), (0, 0, 1)]

    p.subplot(0, 1)
    add(p, bd, COL["body"])
    add(p, g["tripod"], COL["tripod"], 0.55)
    add(p, g["plug"], COL["plug"])
    p.add_text("Underside: 30 mm tripod face + USB-C plug", font_size=10, color="black")
    p.camera_position = [(-90, -120, -110), (12, 0, 5), (0, 0, 1)]

    p.subplot(0, 2)
    add(p, bd - half, COL["body"])
    add(p, lid_in_place - half, COL["lid"])
    add(p, g["stack"] - half, COL["stack"], 0.8)
    add(p, g["board"] - half, COL["board"])
    add(p, g["plug"] - half, COL["plug"])
    add(p, g["tube"] - half, COL["tube"], 0.6)
    p.add_text("Half section: nut pocket, chamber, window, board", font_size=10, color="black")
    p.camera_position = [(10, 190, 35), (10, 0, 30), (0, 0, 1)]

    p.subplot(0, 3)
    add(p, ld, COL["lid"])
    p.add_text("Lid (print flange-down)", font_size=10, color="black")
    p.camera_position = [(L["x_out"] / 2 + 40, 55, 45), (L["x_out"] / 2 + 8, 0, 2), (0, 0, 1)]

    out = tb.OUT / f"{board.name}_preview.png"
    p.screenshot(str(out))
    p.close()
    print("wrote", out)


if __name__ == "__main__":
    for b in (tb.DEVKIT, tb.C3ZERO):
        render(b)
