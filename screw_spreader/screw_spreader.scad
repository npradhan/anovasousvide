// =====================================================================
//  Screw-driven spreader / clamp  (left + right hand lead screw)
//  Target printer: Prusa Core One  (build volume 250 x 220 x 270 mm)
//
//  Turning the 3/8" square drive moves both carriages toward or away
//  from each other: the drive half of the rod has a RIGHT-hand thread,
//  the other half a LEFT-hand thread.
//
//  The rod is 272 mm (10.7") long overall, with 250 mm of threaded
//  length. It is printed as two halves (standing up for clean threads)
//  joined by a glued hex peg/socket in the middle.
//
//  Each carriage houses a ball bearing (1-1/8" OD x 1/2" ID x 5/16" wide,
//  e.g. R8-2RS) in a press-fit pocket on one side. The bearing axis is
//  perpendicular to the rod and passes through the rod's center line.
//  A 1/2" pin (not modelled) through the bearing connects the carriage to
//  the side member. The pinned side members stop the carriages from
//  spinning with the rod.
//
//  Parts (set PART below, or use -D PART="..." on the command line):
//    "assembly"   - everything in place (viewing only)
//    "rod_rh"     - drive half, right-hand thread, hex socket, 3/8" square drive  x1
//    "rod_lh"     - far half, left-hand thread, hex peg                          x1
//    "carriage_rh"- carriage with right-hand nut thread                          x1
//    "carriage_lh"- carriage with left-hand nut thread                           x1
//    "crank"      - crank handle with 3/8" square socket                         x1
//    "knob"       - crank knob, spins on an M5 x 40 bolt                         x1
//
//  Bought parts:
//    2x  ball bearing 1-1/8" OD x 1/2" ID x 5/16" wide (R8)
//    2x  1/2" pins (your side members)
//    1x  M5 x 40 bolt + nylock nut (crank knob)
//    Epoxy for the hex joint (it holds the two rod halves together)
//
//  Print notes: PETG or PLA, 0.2 mm layers, 4 perimeters, 40 % infill.
//    rod halves: stand vertically, square drive / peg pointing up, brim.
//    carriages:  as exported (thread axis vertical), no supports; the
//                bearing pocket has a teardrop top so it prints cleanly.
//    crank / knob: as exported, no supports.
// =====================================================================

PART = "assembly";

// Rendering detail. 'fine' for STL export; the assembly preview uses less.
FINE        = (PART != "assembly");
SEG         = FINE ? 96 : 48;    // points around the thread profile
SLICE_DEG   = FINE ? 4  : 10;    // degrees of twist per extrusion slice
$fn         = FINE ? 96 : 48;

// ---------------- thread ----------------
D      = 22;      // major diameter of lead screw
P      = 6;       // pitch (6 mm travel per turn per carriage, 12 mm closing speed)
H      = 2.0;     // thread depth (90 deg included angle -> printable without support)
CREST  = 1.0;     // axial width of crest flat
ROOT   = P - CREST - 2*H;   // axial width of root flat (= 1.0)
CLR    = 0.35;    // radial clearance of the nut thread (tune for your printer)

// ---------------- rod layout (per half, measured from the center joint) --------
T_LEN    = 125;   // threaded length per half
SHANK_D  = 16;    // plain shank between thread and drive flange
SHANK    = 5;
FL_D     = 26;    // drive-end flange
FL_T     = 3;
SQ       = 9.525; // 3/8" square drive
SQ_LEN   = 14;
HEX_AF   = 10;    // center coupling hex across flats
HEX_LEN  = 18;
HEX_CLR  = 0.3;

// ---------------- bearing ----------------
B_OD      = 1.125 * 25.4;   // 28.575
B_ID      = 0.5   * 25.4;   // 12.7
B_W       = 5/16  * 25.4;   // 7.9375
B_FIT     = 0.15;   // diametral press-fit allowance on the pocket (tune for your printer)
B_PROUD   = 0.5;    // bearing face stands this far out of the carriage
B_RELIEF  = 20;     // clearance behind the inner race (race must not rub the floor)

// ---------------- carriage ----------------
CAR_T     = 42;     // length along the rod
CAR_W     = 40;     // width perpendicular to rod and bearing axis
CAR_BACK  = 20;     // radius of the round back of the carriage
FLOOR_Y   = -(D/2 + CLR + 3.5);       // bearing seat (pocket floor), 3.5 mm from the thread
FACE_Y    = FLOOR_Y - (B_W - B_PROUD); // bearing-side face of the carriage

// =====================================================================
//  Thread primitives
// =====================================================================

// radius of the thread surface as a function of axial position u (0..P)
function thread_r(u, rmaj) =
    let(u = u - floor(u/P)*P,
        rmin = rmaj - H)
    u < ROOT/2                    ? rmin :
    u < ROOT/2 + H                ? rmin + (u - ROOT/2) :
    u < ROOT/2 + H + CREST        ? rmaj :
    u < ROOT/2 + 2*H + CREST      ? rmaj - (u - ROOT/2 - H - CREST) :
                                    rmin;

// cross-section of a single-start thread; twisting it while extruding
// gives an exact helical thread.
module thread_section(rmaj) {
    polygon([for (i = [0:SEG-1])
        let(a = 360*i/SEG, r = thread_r(P*i/SEG, rmaj))
        [r*cos(a), r*sin(a)]]);
}

// threaded cylinder along +Z, hand = 1 (right) or -1 (left)
module thread(len, rmaj, hand = 1) {
    turns = len / P;
    linear_extrude(height = len,
                   twist  = -hand * 360 * turns,      // OpenSCAD: +twist = left hand
                   slices = ceil(360 * turns / SLICE_DEG),
                   convexity = 10)
        thread_section(rmaj);
}

// =====================================================================
//  Rod halves  (built along +Z from the center joint at z = 0)
// =====================================================================

// threaded section with small chamfers at both ends
module rod_body(hand) {
    intersection() {
        thread(T_LEN, D/2, hand);
        union() {
            cylinder(h = 1.5, d1 = D - 2*H, d2 = D);
            translate([0,0,1.5]) cylinder(h = T_LEN - 3, d = D + 1);
            translate([0,0,T_LEN - 1.5]) cylinder(h = 1.5, d1 = D, d2 = D - 2*H);
        }
    }
    // solid core so the thread and chamfers stay one body
    cylinder(h = T_LEN, d = D - 2*H + 0.01);
}

module rod_rh() {   // drive half
    difference() {
        union() {
            rod_body(1);
            translate([0,0,T_LEN - 0.01]) cylinder(h = SHANK + 0.01, d = SHANK_D);
            translate([0,0,T_LEN + SHANK - 0.01]) cylinder(h = FL_T, d = FL_D);
            // square drive with a lead-in chamfer
            translate([0,0,T_LEN + SHANK + FL_T - 0.01])
                hull() {
                    linear_extrude(SQ_LEN - 1) square(SQ, center = true);
                    linear_extrude(SQ_LEN) square(SQ - 2, center = true);
                }
        }
        // hex socket for the coupling
        translate([0,0,-0.01])
            cylinder(h = HEX_LEN + 0.6, d = (HEX_AF + HEX_CLR) / cos(30), $fn = 6);
        translate([0,0,-0.01])
            cylinder(h = 1, d1 = (HEX_AF + HEX_CLR) / cos(30) + 1, d2 = (HEX_AF + HEX_CLR) / cos(30), $fn = 6);
    }
}

module rod_lh() {   // far half
    rod_body(-1);
    // hex peg with chamfered tip
    translate([0,0,-HEX_LEN + 0.01])
        intersection() {
            cylinder(h = HEX_LEN, d = HEX_AF / cos(30), $fn = 6);
            cylinder(h = HEX_LEN, d1 = HEX_AF/cos(30) - 2, d2 = HEX_AF/cos(30) - 2 + 2*HEX_LEN, $fn = 6);
        }
}

// =====================================================================
//  Carriage  (modelled with the rod axis along +Z, z = 0..CAR_T;
//  bearing axis along -Y, through the rod axis at z = CAR_T/2)
// =====================================================================

// circle with a flat-topped 45 deg peak (+Y in 2D) so a horizontal
// hole prints without support
module teardrop(d, top = 2) {
    r = d/2;
    intersection() {
        union() {
            circle(d = d);
            rotate(45) square(r);
        }
        translate([-d, -d]) square([2*d, d + r + top]);
    }
}

// pocket shapes, extruded along -Y from y = y0 for length len
module along_minus_y(y0, len) {
    translate([0, y0, CAR_T/2]) rotate([90, 0, 0]) linear_extrude(len) children();
}

module carriage(hand) {
    difference() {
        linear_extrude(CAR_T) hull() {
            circle(r = CAR_BACK);
            translate([-CAR_W/2, FACE_Y]) square([CAR_W, 1]);
        }
        // internal thread
        translate([0,0,-0.01]) thread(CAR_T + 0.02, D/2 + CLR, hand);
        // entry chamfers
        for (z = [0, CAR_T]) translate([0,0,z])
            cylinder(h = 3, d1 = D + 2*CLR + 2, d2 = D - 2*H, center = true);
        // bearing pocket (teardrop top for printing; the bearing seats on the round part)
        along_minus_y(FLOOR_Y, B_W + 1) teardrop(B_OD + B_FIT, 2);
        // lead-in chamfer on the pocket mouth
        along_minus_y(FACE_Y + 0.8, 1) teardrop(B_OD + B_FIT + 1.6, 2);
        // relief behind the inner race / pin end
        along_minus_y(FLOOR_Y + 1.2, 1.3) teardrop(B_RELIEF, 2);
    }
}

module bearing() {
    rotate([90, 0, 0]) difference() {
        cylinder(h = B_W, d = B_OD);
        translate([0, 0, -1]) cylinder(h = B_W + 2, d = B_ID);
        for (z = [0, B_W]) translate([0, 0, z])     // seal / race detail
            difference() { cylinder(h = 0.6, d = B_OD - 3, center = true); cylinder(h = 1, d = B_ID + 4, center = true); }
    }
}

// =====================================================================
//  Handle
// =====================================================================

CRANK_R = 85;   // crank radius

module crank() {
    hub_d = 32; hub_h = 24; arm_t = 12;
    difference() {
        union() {
            cylinder(h = hub_h, d = hub_d);
            hull() {
                cylinder(h = arm_t, d = 26);
                translate([CRANK_R, 0, 0]) cylinder(h = arm_t, d = 22);
            }
        }
        // 3/8" square socket, open at the top (hub face), with lead-in
        translate([0,0,hub_h - SQ_LEN - 1])
            linear_extrude(SQ_LEN + 2) square(SQ + 0.4, center = true);
        translate([0,0,hub_h - 1.5])
            linear_extrude(1.6, scale = 1.2) square(SQ + 0.4, center = true);
        // M5 bolt for the knob; nylock nut sits in a trap on the hub side
        translate([CRANK_R, 0, -1]) cylinder(h = arm_t + 2, d = 5.4, $fn = 24);
        translate([CRANK_R, 0, arm_t - 4.5]) cylinder(h = 4.6, d = 9.4, $fn = 6);
    }
}

KNOB_L = 26;
module knob() {
    difference() {
        rotate_extrude($fn = 64) polygon([
            [3.2, 0], [10, 0], [12, 4], [12, KNOB_L - 6], [10.5, KNOB_L], [3.2, KNOB_L]]);
        translate([0,0,-1]) cylinder(h = KNOB_L + 2, d = 5.8, $fn = 24);
        translate([0,0,KNOB_L - 4]) cylinder(h = 5, d = 9.5, $fn = 32);   // bolt head
    }
}

// =====================================================================
//  Assembly  (rod axis along X, center joint at x = 0)
// =====================================================================

SPREAD = 70;    // carriage centers at +/- SPREAD  (21 = closed ... 104 = fully open)

module assembly() {
    // rod: drive half (RH) on the -X side, square drive pointing -X
    color("SteelBlue")      rotate([0,-90,0]) rod_rh();
    color("CornflowerBlue") rotate([0, 90,0]) rod_lh();

    // carriages: bearing on the -Y side, bearing axis through the rod axis
    for (side = [-1, 1]) translate([side*SPREAD - CAR_T/2, 0, 0]) rotate([0, 90, 0]) {
        color("Tomato") carriage(side < 0 ? 1 : -1);
        color("Silver") translate([0, FLOOR_Y, CAR_T/2]) bearing();
        // bearing axis (for reference) - ends at the rod center line
        %translate([0, 0, CAR_T/2]) rotate([90, 0, 0]) cylinder(h = 45, d = 1);
    }

    // handle on the square drive
    drive_tip = -(T_LEN + SHANK + FL_T + SQ_LEN);
    color("SeaGreen") translate([drive_tip - (24 - SQ_LEN - 1) - 0.5, 0, 0])
        rotate([0, 90, 0]) rotate([0,0,90]) crank_with_knob();
}

module crank_with_knob() {
    crank();
    translate([CRANK_R, 0, -KNOB_L - 0.5]) color("ForestGreen") knob();
}

// =====================================================================
if      (PART == "assembly")    assembly();
else if (PART == "rod_rh")      rod_rh();
else if (PART == "rod_lh")      rotate([180,0,0]) translate([0,0,-T_LEN]) rod_lh();
else if (PART == "carriage_rh") carriage(1);
else if (PART == "carriage_lh") carriage(-1);
else if (PART == "crank")       crank();
else if (PART == "knob")        knob();
