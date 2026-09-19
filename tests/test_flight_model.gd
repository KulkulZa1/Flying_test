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

func test_climbing_bleeds_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(30.0))  # nose up 30 degrees
	fm.apply_gravity(1.0)
	check_approx(fm.speed, 100.0 - Config.GRAVITY * 0.5, 0.01,
		"a 30 degree climb bleeds GRAVITY * sin(30) per second")

func test_diving_gains_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(-30.0))  # nose down 30 degrees
	fm.apply_gravity(1.0)
	check_approx(fm.speed, 100.0 + Config.GRAVITY * 0.5, 0.01,
		"a 30 degree dive gains GRAVITY * sin(30) per second")

func test_level_flight_does_not_change_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.apply_gravity(1.0)
	check_approx(fm.speed, 100.0, 1e-6, "level flight is energy neutral")

func test_speed_never_goes_negative() -> void:
	var fm := FlightModel.new()
	fm.speed = 1.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(90.0))  # straight up
	for i in 100:
		fm.apply_gravity(0.1)
	check(fm.speed >= 0.0, "speed must never go negative")
