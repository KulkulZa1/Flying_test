extends TestCase

func test_horizon_is_centred_in_level_flight() -> void:
	check_approx(HUD.horizon_offset(0.0, 720.0), 0.0, 1e-6,
		"level flight draws the horizon through screen centre")
	check_approx(HUD.horizon_direction(0.0).y, 0.0, 1e-6,
		"wings level draws a flat horizon")

func test_horizon_drops_when_the_nose_rises() -> void:
	check(HUD.horizon_offset(0.4, 720.0) > 0.0,
		"nose up puts the horizon below centre, and screen Y grows downward")
	check(HUD.horizon_offset(-0.4, 720.0) < 0.0,
		"nose down puts the horizon above centre")

func test_horizon_offset_scales_with_pitch_and_screen() -> void:
	var shallow := HUD.horizon_offset(0.2, 720.0)
	var steep := HUD.horizon_offset(0.4, 720.0)
	check(steep > shallow, "a steeper climb pushes the horizon further down")
	check(HUD.horizon_offset(0.4, 1440.0) > steep, "a taller viewport scales the offset up")

func test_horizon_tilts_opposite_the_bank() -> void:
	var right := HUD.horizon_direction(0.4)
	check(right.y < 0.0, "a right bank lifts the right end of the horizon on screen")
	var left := HUD.horizon_direction(-0.4)
	check(left.y > 0.0, "a left bank drops the right end of the horizon on screen")
	check_approx(right.length(), 1.0, 1e-6, "the horizon direction is a unit vector")
