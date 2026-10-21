// =====================================================================
//  Screw-driven spreader / clamp  (left + right hand lead screw)
//  Target printer: Prusa Core One  (build volume 250 x 220 x 270 mm)
//
//  Turning the 3/8" square drive moves both carriages toward or away
//  from each other: the drive half of the rod has a RIGHT-hand thread,
//  the other half a LEFT-hand thread.
//
//  The rod is 297 mm long (11.7") overall, with 250 mm of threaded
//  length. It is printed as two halves (each ~160 mm tall, printed
//  standing up for clean threads) joined by a hex peg/socket in the middle.
//
//  Parts (set PART below, or use -D PART="..." on the command line):
//    "assembly"   - everything in place (viewing only)
//    "rod_rh"     - drive half, right-hand thread, hex socket, 3/8" square drive  x1
//    "rod_lh"     - far half, left-hand thread, hex peg                          x1
//    "carriage_rh"- carriage with right-hand nut thread                          x1
//    "carriage_lh"- carriage with left-hand nut thread                           x1
//    "end_block"  - end plate: rod bearing + 2 guide rods                        x2
//    "end_collar" - retaining collar for the far end (M4 x 12 screw)            x1
//    "crank"      - crank handle with 3/8" square socket                         x1
//    "knob"       - crank knob, spins on an M5 x 40 bolt                         x1
//
//  Bought parts:
//    2x  8 mm steel or aluminum rod, 279 mm long (guide rods; keep carriages from spinning)
//    1x  M4 x 12 screw + washer (end collar)
//    1x  M5 x 40 bolt + nylock nut (crank knob)
//    Epoxy or CA glue for the hex joint (optional; the joint is also
//    held together axially by the end blocks)
//
//  Print notes: PETG or PLA, 0.2 mm layers, 4 perimeters, 40 % infill.
//    rod halves: stand vertically, square drive / peg pointing up, brim.
//    carriages:  thread axis vertical (flat face down) - no supports.
//    end blocks / crank / knob: flat, no supports.
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
J_D      = 14;    // journal (bearing) diameter
J_LEN    = 15;    // journal length
FL_D     = 26;    // drive-end flange
FL_T     = 3;
SQ       = 9.525; // 3/8" square drive
SQ_LEN   = 14;
HEX_AF   = 10;    // center coupling hex across flats
HEX_LEN  = 18;
HEX_CLR  = 0.3;

// ---------------- frame ----------------
GUIDE_D   = 8;      // guide rod diameter
GUIDE_Y   = 30;     // guide rod offset from screw axis
BLK_T     = 14;     // end block thickness (along the rod)
BLK_W     = 84;
BLK_H     = 44;
BEAR_CLR  = 0.5;    // diametral clearance of the printed plain bearing

// ---------------- carriage ----------------
CAR_T     = 26;     // along the rod
CAR_W     = 84;
CAR_H     = 44;
JAW_H     = 70;     // jaw height above the screw axis
JAW_W     = 44;
JAW_T     = 14;

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

module rod_body(hand) {
    // threaded section with small chamfer at the center end
    intersection() {
        thread(T_LEN, D/2, hand);
        union() {
            cylinder(h = 1.5, d1 = D - 2*H, d2 = D);
            translate([0,0,1.5]) cylinder(h = T_LEN, d = D + 1);
        }
    }
    // journal
    translate([0,0,T_LEN - 0.01]) cylinder(h = J_LEN + 0.01, d = J_D);
    // fillet between thread and journal
    translate([0,0,T_LEN - 0.01]) cylinder(h = 1.5, d1 = D - 2*H, d2 = J_D);
}

module rod_rh() {   // drive half
    difference() {
        union() {
            rod_body(1);
            translate([0,0,T_LEN + J_LEN - 0.01]) cylinder(h = FL_T, d = FL_D);
            // square drive with a lead-in chamfer
            translate([0,0,T_LEN + J_LEN + FL_T - 0.01])
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
    difference() {
        rod_body(-1);
        // pilot hole for the M4 collar screw (self-tapping)
        translate([0,0,T_LEN + J_LEN - 16]) cylinder(h = 17, d = 3.4, $fn = 24);
    }
    // hex peg with chamfered tip
    translate([0,0,-HEX_LEN + 0.01])
        intersection() {
            cylinder(h = HEX_LEN, d = HEX_AF / cos(30), $fn = 6);
            cylinder(h = HEX_LEN, d1 = HEX_AF/cos(30) - 2, d2 = HEX_AF/cos(30) - 2 + 2*HEX_LEN, $fn = 6);
        }
}

module end_collar() {
    difference() {
        cylinder(h = 4, d = FL_D);
        translate([0,0,-1]) cylinder(h = 6, d = 4.5, $fn = 24);
        translate([0,0,2]) cylinder(h = 3, d = 8.5, $fn = 32);   // screw head counterbore
    }
}

// =====================================================================
//  Frame + carriages   (modelled with the rod axis along +Z, z = 0..thick)
// =====================================================================

module rounded_rect(w, h, r) {
    offset(r) offset(-r) square([w, h], center = true);
}

module end_block() {
    difference() {
        linear_extrude(BLK_T) rounded_rect(BLK_W, BLK_H, 6);
        // plain bearing for the journal, chamfered both sides
        translate([0,0,-1]) cylinder(h = BLK_T + 2, d = J_D + BEAR_CLR);
        for (z = [0, BLK_T]) translate([0,0,z]) cylinder(h = 2, d = J_D + BEAR_CLR + 3, center = true);
        // guide rods: snug, glue or press in
        for (s = [-1, 1]) translate([s*GUIDE_Y, 0, -1])
            cylinder(h = BLK_T + 2, d = GUIDE_D + 0.15, $fn = 48);
        // mounting holes (M4)
        for (s = [-1, 1]) translate([s*(BLK_W/2 - 7), BLK_H/2 - 8, -1])
            cylinder(h = BLK_T + 2, d = 4.4, $fn = 24);
    }
}

module carriage(hand) {
    difference() {
        union() {
            linear_extrude(CAR_T) rounded_rect(CAR_W, CAR_H, 6);
            // jaw plate (flush with one face of the carriage)
            translate([-JAW_W/2, 0, 0]) cube([JAW_W, JAW_H, JAW_T]);
            // gusset tying the jaw into the body
            hull() {
                translate([-JAW_W/2, CAR_H/2 - 1, 0]) cube([JAW_W, 1, CAR_T]);
                translate([-JAW_W/2, CAR_H/2 + 14, 0]) cube([JAW_W, 1, JAW_T]);
            }
        }
        // internal thread
        translate([0,0,-0.01]) thread(CAR_T + 0.02, D/2 + CLR, hand);
        // entry chamfers
        for (z = [0, CAR_T]) translate([0,0,z])
            cylinder(h = 3, d1 = D + 2*CLR + 2, d2 = D - 2*H, center = true);
        // guide rod bushings (sliding fit)
        for (s = [-1, 1]) translate([s*GUIDE_Y, 0, -1])
            cylinder(h = CAR_T + 2, d = GUIDE_D + 0.6, $fn = 48);
        // recess for a rubber / felt pad on the jaw face
        translate([-(JAW_W - 8)/2, CAR_H/2 + 16, -0.01]) cube([JAW_W - 8, JAW_H - CAR_H/2 - 20, 1.2]);
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

SPREAD = 80;    // carriage centers at +/- SPREAD  (13 = closed ... 112 = fully open)

module along_x(x) { translate([x,0,0]) rotate([0,90,0]) children(); }

module assembly() {
    blk_in = T_LEN + 0.5;                 // inner face of each end block

    // rod: drive half (RH) on the -X side, square drive pointing -X
    color("SteelBlue")   translate([0,0,0]) rotate([0,-90,0]) rod_rh();
    color("CornflowerBlue") rotate([0, 90,0]) rod_lh();
    color("DimGray") along_x(T_LEN + J_LEN) end_collar();

    // end blocks
    color("Orange") along_x(-blk_in - BLK_T) end_block();
    color("Orange") along_x( blk_in)         end_block();

    // guide rods
    g_len = 2*(blk_in + BLK_T);
    color("Silver") for (s = [-1, 1])
        translate([-g_len/2, s*GUIDE_Y, 0]) rotate([0,90,0]) rotate([0,0,0])
            cylinder(h = g_len, d = GUIDE_D);

    // carriages, jaws facing up (+Z), jaw plates on the outer faces
    color("Tomato") translate([-SPREAD - CAR_T/2, 0, 0])
        rotate([90, 0, 90]) carriage(1);
    color("Tomato") translate([ SPREAD - CAR_T/2, 0, 0])
        rotate([0, 0, 180]) translate([-CAR_T, 0, 0]) rotate([90, 0, 90]) carriage(-1);

    // handle on the square drive
    drive_tip = -(T_LEN + J_LEN + FL_T + SQ_LEN);
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
else if (PART == "rod_lh")      rotate([180,0,0]) translate([0,0,-(T_LEN + J_LEN)]) rod_lh();
else if (PART == "carriage_rh") carriage(1);
else if (PART == "carriage_lh") carriage(-1);
else if (PART == "end_block")   end_block();
else if (PART == "end_collar")  end_collar();
else if (PART == "crank")       crank();
else if (PART == "knob")        knob();
