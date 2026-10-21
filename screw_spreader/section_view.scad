include <screw_spreader.scad>
PART = "none";
SEG = 48; SLICE_DEG = 6;
// left carriage cut open on the plane containing the rod axis and bearing axis
difference() {
    translate([-SPREAD - CAR_T/2, 0, 0]) rotate([0, 90, 0]) {
        color("Tomato") carriage(1);
        color("Silver") translate([0, FLOOR_Y, CAR_T/2]) bearing();
    }
    translate([-200, -100, 0]) cube([400, 200, 100]);
}
color("SteelBlue") intersection() {
    rotate([0,-90,0]) rod_rh();
    translate([-SPREAD - 45, -50, -50]) cube([90, 100, 100]);
}
// rod axis (black) and bearing axis (red): they cross at the rod center
color("Black") translate([-SPREAD - 60, 0, 0]) rotate([0,90,0]) cylinder(h = 120, d = 1.2);
color("Red")   translate([-SPREAD, 15, 0]) rotate([90,0,0]) cylinder(h = 60, d = 1.2);
