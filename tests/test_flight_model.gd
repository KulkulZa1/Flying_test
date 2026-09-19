extends TestCase

func test_throttle_rises_at_configured_rate() -> void:
	var fm := FlightModel.new()
	fm.throttle = 0.0
	var cmd := InputCommand.new()
	cmd.throttle_delta = 1.0
	fm.apply_throttle(cmd, 0.5)
	check_approx(fm.throttle, Config.THROTTLE_RATE * 0.5, 1e-6,
		"throttle rises by THROTTLE_RATE * dt")

func test_throttle_clamps_to_unit_range() -> void:
	var fm := FlightModel.new()
	var cmd := InputCommand.new()
	cmd.throttle_delta = 1.0
	for i in 100:
		fm.apply_throttle(cmd, 0.1)
	check_approx(fm.throttle, 1.0, 1e-6, "throttle clamps at 1.0")
	cmd.throttle_delta = -1.0
	for i in 100:
		fm.apply_throttle(cmd, 0.1)
	check_approx(fm.throttle, 0.0, 1e-6, "throttle clamps at 0.0")

func test_speed_approaches_full_throttle_target() -> void:
	var fm := FlightModel.new()
	fm.throttle = 1.0
	fm.speed = Config.MIN_SPEED
	for i in 200:
		fm.apply_engine_lag(0.05)
	check(fm.speed > Config.MAX_SPEED - 1.0, "10s at full throttle reaches near MAX_SPEED")
	check(fm.speed <= Config.MAX_SPEED + 1e-6, "speed never exceeds MAX_SPEED")

func test_engine_lag_is_framerate_independent() -> void:
	var fast := FlightModel.new()
	var slow := FlightModel.new()
	for fm in [fast, slow]:
		fm.throttle = 1.0
		fm.speed = Config.MIN_SPEED
	for i in 120:
		fast.apply_engine_lag(1.0 / 120.0)
	for i in 45:
		slow.apply_engine_lag(1.0 / 45.0)
	check_approx(fast.speed, slow.speed, 0.01,
		"one second of spool-up must not depend on timestep")
