pub const HELP =
	\\RegulaWM - an extensible Wayland compositor with sane defaults
	\\
	\\CLI flags:
	\\    -h, --help                 print this message and quit
	\\    -s, --startup <cmd ...>    run the following args as an initial command
	\\    -v, --version              print version and quit
;

pub const VERSION = "0.0.0";

// TODO TEMPORARY before making a proper config framework
pub const config = struct {
	// TODO CONSIDER REWRITE

	/// Default background color formatted as 0xRRGGBBAA
	pub const rootcolor = 0x22_22_22_ff;

	pub const urgentcolor = 0xff_00_00_ff;
};
