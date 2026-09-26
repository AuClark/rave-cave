"""Tube base enclosure: tripod mount + tube socket + vertical ESP32 pod.

Layout (Z up, origin at the centre of the bottom face = tripod axis):

- Tube socket on the tripod axis at the top (tube OD 26 mm).
- Captive 1/4"-20 hex nut in the floor under the tube, dropped in through the
  socket bore before the tube goes in. Stud hole through the bottom face.
- ESP32 board stands vertically in a pod off to +X, USB-C facing down through
  the floor, outside the tripod's 30 mm mating face.
- Wire window between the socket chamber and the pod.
- Push-fit lid closes the pod and pins the board's top edge.

Two board profiles: the 38-pin ESP32 dev board (testing) and the Waveshare
ESP32-C3-Zero (production). Every dimension is a named parameter; board sizes
are best guesses until measured -- check them before printing.

    ~/.venvs/cad/bin/python cad/tube_base/tube_base.py
"""
from dataclasses import dataclass
from pathlib import Path

from build123d import (Align, Axis, Box, Circle, Cylinder, Location, Pos,
                       Rectangle, RegularPolygon, Rot, Solid, export_step,
                       export_stl, extrude, fillet, make_hull)

OUT = Path(__file__).parent / "out"


@dataclass
class Board:
    name: str
    pcb_l: float         # vertical length (Z), USB end down
    pcb_w: float         # width (Y)
    pcb_t: float         # PCB thickness
    back: float          # tallest thing below the PCB: pins, header plastic, solder (toward the tube)
    front: float         # tallest thing above the PCB: module, USB-C, solder (away from the tube)
    usb_h: float = 3.26  # USB-C receptacle height above the PCB face
    usb_y: float = 0.0   # USB centre offset along the board width


# Measure these before printing. Defaults are typical for each board.
DEVKIT = Board("esp32_devkit38", pcb_l=52.0, pcb_w=28.5, pcb_t=1.6, back=9.0, front=4.5)
C3ZERO = Board("esp32_c3_zero", pcb_l=23.5, pcb_w=18.0, pcb_t=1.0, back=2.5, front=3.5)

# Fit and print
CLR = 0.4             # board-to-pod clearance per side
WALL = 2.4            # outer walls (6 perimeters at 0.4)
FLOOR = 2.4           # pod floor
LID_CLR = 0.15        # lid plug clearance per side
LID_PLATE = 2.0
LID_PLUG = 3.0        # depth the lid plug drops into the pod

# Tube
TUBE_OD = 26.0
TUBE_FIT = 0.4        # diametral clearance; drop to 0.2 for a tight press fit
SOCKET_DEPTH = 30.0
SOCKET_WALL = 2.4
SET_SCREW = True      # radial M3 self-tapping screw to lock the tube
SET_SCREW_D = 2.6

# Tripod
NUT_AF = 11.11 + 0.35  # 1/4"-20 hex nut across flats (7/16") + clearance
NUT_T = 5.56 + 0.4     # nut thickness (7/32") + clearance
UNDER_NUT = 2.0        # floor under the nut; tripod studs only stick up ~5-6 mm
STUD_HOLE = 6.8
TRIPOD_FACE_D = 30.0   # keep the bottom face clear inside this circle
CHAMBER_D = 20.0       # passage under the socket (nut drops through it)

# USB-C plug overmold passing through the floor
PLUG_W = 13.0          # along the board width
PLUG_H = 7.5           # across the board


def layout(b: Board) -> dict:
    bore_r = (TUBE_OD + TUBE_FIT) / 2
    x_in0 = bore_r + 1.6                      # pod inner face nearest the tube
    x_back = x_in0 + CLR                      # tip of the board's back-side pins
    x_pcb0 = x_back + b.back                  # PCB back face
    x_pcb1 = x_pcb0 + b.pcb_t                 # PCB front face
    x_usb = x_pcb1 + b.usb_h / 2              # USB-C centre
    # Push the pod out if the USB plug would land on the tripod face.
    need = TRIPOD_FACE_D / 2 + 0.5 + PLUG_H / 2
    if x_usb < need:
        shift = need - x_usb
        x_in0, x_back, x_pcb0, x_pcb1, x_usb = (v + shift for v in (x_in0, x_back, x_pcb0, x_pcb1, x_usb))
    x_in1 = x_pcb1 + b.front + CLR
    x_out = x_in1 + WALL
    hy_in = b.pcb_w / 2 + CLR
    hy_out = hy_in + WALL
    z_nut_top = UNDER_NUT + NUT_T
    board_top = FLOOR + b.pcb_l
    z_top = max(board_top + LID_PLUG + 0.8, z_nut_top + 6.0 + SOCKET_DEPTH)
    return dict(bore_r=bore_r, r_col=bore_r + SOCKET_WALL, x_in0=x_in0, x_in1=x_in1,
                x_out=x_out, x_pcb0=x_pcb0, x_pcb1=x_pcb1, x_usb=x_usb, hy_in=hy_in,
                hy_out=hy_out, z_nut_top=z_nut_top, board_top=board_top, z_top=z_top,
                z_sock=z_top - SOCKET_DEPTH)


def box(x0, x1, y0, y1, z0, z1):
    return Pos((x0 + x1) / 2, (y0 + y1) / 2, z0) * Box(
        x1 - x0, y1 - y0, z1 - z0, align=(Align.CENTER, Align.CENTER, Align.MIN))


def cyl(r, z0, z1, x=0.0, y=0.0):
    return Pos(x, y, z0) * Cylinder(r, z1 - z0, align=(Align.CENTER, Align.CENTER, Align.MIN))


def body(b: Board):
    L = layout(b)
    foot = make_hull((Circle(L["r_col"]) + Pos(L["x_out"] / 2, 0) *
                      Rectangle(L["x_out"], 2 * L["hy_out"])).edges())
    part = extrude(foot, L["z_top"])
    try:
        part = fillet(part.edges().filter_by(Axis.Z), 2.0)
    except Exception:
        pass

    # Tube socket, chamber below it, captive nut, stud hole
    part -= cyl(L["bore_r"], L["z_sock"], L["z_top"] + 1)
    part -= cyl(CHAMBER_D / 2, L["z_nut_top"], L["z_sock"] + 0.01)
    part -= Pos(0, 0, UNDER_NUT) * extrude(RegularPolygon(NUT_AF / 2, 6, major_radius=False), NUT_T)
    part -= cyl(STUD_HOLE / 2, -1, UNDER_NUT + 0.01)

    # Board pod (open top, closed by the lid)
    part -= box(L["x_in0"], L["x_in1"], -L["hy_in"], L["hy_in"], FLOOR, L["z_top"] + 1)

    # Wire window from the chamber into the pod, reaching up past the tube's end
    part -= box(CHAMBER_D / 2 - 2, L["x_in0"] + 1, -5, 5, L["z_nut_top"] + 0.5, L["z_sock"] + 6)

    # USB-C plug through the floor
    part -= box(L["x_usb"] - PLUG_H / 2, L["x_usb"] + PLUG_H / 2,
                b.usb_y - PLUG_W / 2, b.usb_y + PLUG_W / 2, -1, FLOOR + 0.01)

    # Radial set screw on the far side from the pod
    if SET_SCREW:
        part -= Pos(-L["bore_r"] - SOCKET_WALL - 1, 0, L["z_sock"] + SOCKET_DEPTH / 2) * \
            Rot(0, 90, 0) * Cylinder(SET_SCREW_D / 2, SOCKET_WALL + 2,
                                     align=(Align.CENTER, Align.CENTER, Align.MIN))
    return part


def lid(b: Board):
    L = layout(b)
    # Flange sits on the pod walls; plug drops into the pod opening.
    flange = box(L["x_in0"] - 1.2, L["x_out"], -L["hy_out"], L["hy_out"], 0, LID_PLATE)
    plug = box(L["x_in0"] + LID_CLR, L["x_in1"] - LID_CLR,
               -L["hy_in"] + LID_CLR, L["hy_in"] - LID_CLR, -LID_PLUG, 0)
    # Pad pressing on the PCB's top edge, plus a prong down the back face.
    # Nothing on the front face, so it can't foul the module/antenna there.
    gap = L["z_top"] - L["board_top"]
    pad = box(L["x_pcb0"] - 1.6, L["x_pcb1"], -5, 5, -gap + 0.2, -LID_PLUG)
    prong = box(L["x_pcb0"] - 1.6, L["x_pcb0"] - 0.2, -5, 5, -gap - 2.5, -LID_PLUG)
    part = flange + plug + pad + prong
    # Print flange-down: flip so Z=0 is the lid top.
    return Rot(180, 0, 0) * part


def ghosts(b: Board):
    """Reference parts for previews only: board, tube stub, tripod face, USB plug."""
    L = layout(b)
    board = box(L["x_pcb0"], L["x_pcb1"], -b.pcb_w / 2, b.pcb_w / 2, FLOOR, L["board_top"])
    stack = box(L["x_pcb0"] - b.back, L["x_pcb1"] + b.front, -b.pcb_w / 2 + 2, b.pcb_w / 2 - 2,
                FLOOR + 3, L["board_top"] - 3)
    tube = cyl(TUBE_OD / 2, L["z_sock"], L["z_top"] + 40) - cyl(TUBE_OD / 2 - 1, L["z_sock"] - 1, L["z_top"] + 41)
    tripod = cyl(TRIPOD_FACE_D / 2, -12, -0.5)
    plug = box(L["x_usb"] - 3.2, L["x_usb"] + 3.2, b.usb_y - 6, b.usb_y + 6, -25, FLOOR - 0.5)
    return dict(board=board, stack=stack, tube=tube, tripod=tripod, plug=plug)


def build(b: Board):
    OUT.mkdir(exist_ok=True)
    L = layout(b)
    bd, ld = body(b), lid(b)
    for name, part in (("body", bd), ("lid", ld)):
        export_step(part, str(OUT / f"{b.name}_{name}.step"))
        export_stl(part, str(OUT / f"{b.name}_{name}.stl"))
    bb = bd.bounding_box()
    print(f"{b.name}: body {bb.size.X:.1f} x {bb.size.Y:.1f} x {bb.size.Z:.1f} mm, "
          f"USB centre {L['x_usb']:.1f} mm from tripod axis "
          f"(plug edge {L['x_usb'] - PLUG_H / 2:.1f}, tripod face edge {TRIPOD_FACE_D / 2:.1f}), "
          f"socket {SOCKET_DEPTH:.0f} deep, board slot {L['x_in1'] - L['x_in0']:.1f} x {2 * L['hy_in']:.1f}")
    return bd, ld


if __name__ == "__main__":
    for board in (DEVKIT, C3ZERO):
        build(board)
