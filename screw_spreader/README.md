# Screw spreader / clamp (OpenSCAD)

A lead screw with a right-hand thread on one half and a left-hand thread on the
other. Turning the 3/8" square drive moves the two carriages toward or away
from each other. Everything fits a Prusa Core One (250 x 220 x 270 mm).

![assembly](assembly_drive_side.png)
![assembly](assembly.png)

## Specs
| | |
|---|---|
| Rod length | 297 mm (11.7") overall, 250 mm threaded |
| Thread | 22 mm major dia, 6 mm pitch, 90° included angle (prints without support) |
| Travel | 6 mm per turn per carriage (12 mm/turn closing or opening) |
| Jaw span (outer faces) | about 52 mm to 251 mm |
| Drive | 3/8" square: fits the printed crank or any 3/8" ratchet or T-handle |

## Parts
Export with `openscad -o part.stl -D 'PART="rod_rh"' screw_spreader.scad`.

| PART | Qty | Print orientation |
|---|---|---|
| `rod_rh` (drive half, RH thread, hex socket) | 1 | standing up, square drive on top, brim |
| `rod_lh` (far half, LH thread, hex peg) | 1 | standing up, peg on top, brim |
| `carriage_rh` | 1 | flat as exported (thread axis vertical) |
| `carriage_lh` | 1 | flat as exported |
| `end_block` | 2 | flat |
| `end_collar` | 1 | flat |
| `crank` | 1 | flat |
| `knob` | 1 | upright |

Bought parts: 2x 8 mm rod, 279 mm long (guide rods), 1x M4x12 screw and washer,
1x M5x40 bolt and nylock nut, epoxy (optional) for the center hex joint.

## Assembly
1. Glue the hex peg of `rod_lh` into the socket of `rod_rh` (optional; the end
   blocks also hold the halves together lengthwise).
2. Thread `carriage_rh` onto the RH half and `carriage_lh` onto the LH half,
   with the jaws facing outward and the carriages the same distance from center.
3. Slide both end blocks onto the journals and push the guide rods through the
   end blocks and carriages.
4. Screw the end collar onto the far end (M4, self-tapping into the 3.4 mm pilot).
5. Put the crank on the square drive.

Tune `CLR` (nut clearance, default 0.35 mm radial) if the carriages are too
tight or too loose on your printer.
