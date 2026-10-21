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
//  Each carriage has two screw ears to the sides of the rod (90 deg from
//  it). The screws go in perpendicular to the rod, through a flat mounting
//  face. Whatever the carriages are screwed to stops them from spinning.
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
//    4x  M4 or #8 screws to mount the carriages (head <= 8 mm dia)
//    1x  M5 x 40 bolt + nylock nut (crank knob)
//    Epoxy for the hex joint (it holds the two rod halves together)
//
//  Print notes: PETG or PLA, 0.2 mm layers, 4 perimeters, 40 % infill.
//    rod halves: stand vertically, square drive / peg pointing up, brim.
//    carriages:  as exported (thread axis vertical), no supports.
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

// ---------------- carriage ----------------
CAR_T     = 26;     // length along the rod
HUB_D     = 38;     // round body around the nut thread
EAR_SPAN  = 92;     // overall width across both ears
EAR_T     = 14;     // ear thickness (screw length through it)
EAR_HOLE  = 34;     // screw hole distance from rod axis
SCREW_D   = 4.5;    // clearance hole: M4 / #8
HEAD_D    = 8.5;    // counterbore for the screw head
FACE_Y    = -HUB_D/2;  // flat mounting face, tangent to the hub

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
//  ears along X, flat mounting face at y = FACE_Y, screws along Y)
// =====================================================================

module carriage(hand) {
    difference() {
        linear_extrude(CAR_T) hull() {
            circle(d = HUB_D);
            for (s = [-1, 1])
                translate([s*(EAR_SPAN/2 - 7), FACE_Y + 7]) circle(r = 7);
            translate([-EAR_SPAN/2 + 7, FACE_Y]) square([EAR_SPAN - 14, 1]);
        }
        // trim the ears to EAR_T thick (keeps the hub full height)
        for (m = [0, 1]) mirror([m, 0, 0])
            translate([HUB_D/2 - 2, FACE_Y + EAR_T, -1]) cube([EAR_SPAN, 50, CAR_T + 2]);
        // internal thread
        translate([0,0,-0.01]) thread(CAR_T + 0.02, D/2 + CLR, hand);
        // entry chamfers
        for (z = [0, CAR_T]) translate([0,0,z])
            cylinder(h = 3, d1 = D + 2*CLR + 2, d2 = D - 2*H, center = true);
        // screw holes, perpendicular to the rod, counterbored from the top
        for (s = [-1, 1]) translate([s*EAR_HOLE, 0, CAR_T/2]) {
            translate([0, FACE_Y - 1, 0]) rotate([-90,0,0]) cylinder(h = 60, d = SCREW_D, $fn = 32);
            translate([0, FACE_Y + EAR_T - 4, 0]) rotate([-90,0,0]) cylinder(h = 60, d = HEAD_D, $fn = 32);
        }
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

SPREAD = 70;    // carriage centers at +/- SPREAD  (13 = closed ... 112 = fully open)

module assembly() {
    // rod: drive half (RH) on the -X side, square drive pointing -X
    color("SteelBlue")      rotate([0,-90,0]) rod_rh();
    color("CornflowerBlue") rotate([0, 90,0]) rod_lh();

    // carriages: mounting face down (-Z), ears to the sides (+/-Y)
    color("Tomato") translate([-SPREAD - CAR_T/2, 0, 0])
        rotate([90, 0, 90]) carriage(1);
    color("Tomato") translate([ SPREAD - CAR_T/2, 0, 0])
        rotate([90, 0, 90]) carriage(-1);

    // screws in the carriage ears
    color("DimGray") for (x = [-SPREAD, SPREAD], s = [-1, 1])
        translate([x, s*EAR_HOLE, FACE_Y + EAR_T - 4]) {
            cylinder(h = 3.5, d = 8);
            translate([0,0,-16]) cylinder(h = 16, d = 4);
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
