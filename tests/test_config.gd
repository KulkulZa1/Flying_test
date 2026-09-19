extends TestCase

func test_speed_band_is_ordered() -> void:
	check(Config.MIN_SPEED < Config.MAX_SPEED, "MIN_SPEED must be below MAX_SPEED")
	check(Config.STALL_SPEED >= Config.MIN_SPEED, "STALL_SPEED must be at or above MIN_SPEED")
	check(Config.STALL_SPEED < Config.MAX_SPEED, "STALL_SPEED must be below MAX_SPEED")

func test_turn_scales_are_fractions() -> void:
	check(Config.MIN_TURN_SCALE > 0.0 and Config.MIN_TURN_SCALE <= 1.0,
		"MIN_TURN_SCALE must be in (0, 1]")
	check(Config.HIGH_SPEED_TURN_FLOOR > 0.0 and Config.HIGH_SPEED_TURN_FLOOR <= 1.0,
		"HIGH_SPEED_TURN_FLOOR must be in (0, 1]")

func test_input_command_defaults_are_finite_and_neutral() -> void:
	var cmd := InputCommand.new()
	check(cmd.aim_dir.is_finite(), "default aim_dir must be finite")
	check_approx(cmd.aim_dir.length(), 1.0, 1e-5, "default aim_dir must be unit length")
	check_approx(cmd.throttle_delta, 0.0, 1e-9, "default throttle_delta must be neutral")
	check_approx(cmd.roll, 0.0, 1e-9, "default roll must be neutral")
	check(not cmd.fire, "default fire must be false")
