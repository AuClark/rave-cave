# Tube base enclosure

Tripod-mount base for the floor tubes, with the ESP32 standing upright beside the tube. Code: [`fixtures/tubes/enclosure/`](../../fixtures/tubes/enclosure/). Printable STEP/STL files and preview renders are in `out/`.

**Status:** designed, not yet printed. The board dimensions are typical values; measure your board before printing.

- **Top:** socket for the 26 mm OD tube (30 mm deep, 26.4 mm bore). The tube bottoms out on a ledge. Optional M3 self-tapping set screw (2.6 mm hole) on the side away from the pod.
- **Bottom:** captive 1/4"-20 hex nut on the tripod axis, 2 mm floor under it, 6.8 mm stud hole. Nothing else sits inside the 30 mm tripod face.
- **Pod:** the board stands vertically with its USB-C facing down through the floor, clear of the tripod face. A window joins the pod to the chamber under the tube for the three LED wires.
- **Lid:** push-fit plug that closes the pod. A pad and back-side prong hold the board's top edge; nothing touches the module side.

| Variant | Body (X x Y x Z) | Board slot | USB plug edge from tripod axis |
|---|---|---|---|
| `esp32_devkit38` (testing) | 48.7 x 34.1 x 58.2 mm | 15.9 x 29.3 mm | 23.7 mm |
| `esp32_c3_zero` (production) | 40.6 x 31.2 x 44.0 mm | 7.8 x 18.8 mm | 16.6 mm |

## Build

```bash
~/.venvs/cad/bin/python fixtures/tubes/enclosure/tube_base.py   # STEP + STL into out/
~/.venvs/cad/bin/python fixtures/tubes/enclosure/render.py      # also writes out/*_preview.png
```

The venv is Python 3.12 with `build123d` and `pyvista` (`uv venv --python 3.12 ~/.venvs/cad`).

All dimensions are named constants at the top of `tube_base.py`. **Board sizes are typical values, not measurements.** Before printing, check `DEVKIT` (`pcb_l`, `pcb_w`, and especially `back`/`front`, which include pins, header plastic, solder blobs and the soldered wires).

## Print

- Body upright on its bottom face, lid flange-down. No supports needed.
- PETG or PLA, 0.2 mm layers, 4+ walls around the socket and nut.
- Fit parameters: `TUBE_FIT` (0.4 diametral), `CLR` (0.4 per side for the board), `LID_CLR` (0.15), `NUT_AF`/`NUT_T` (+0.35/+0.4).

## Assembly

1. Drop the 1/4"-20 nut down the socket bore into the hex pocket.
2. Feed the LED wires from the tube bottom through the window into the pod, then push the tube into the socket.
3. Slide the board in from the top, USB-C down into the floor cutout. Push the lid on.
4. Optional: an M3 screw through the side hole locks the tube.
