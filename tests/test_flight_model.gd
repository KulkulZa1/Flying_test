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

func test_turn_rate_peaks_at_best_turn_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	check_approx(fm.turn_rate(), Config.MAX_TURN_RATE, 1e-6,
		"full authority at BEST_TURN_SPEED")

func test_turn_rate_falls_off_when_slow_but_never_to_zero() -> void:
	var fm := FlightModel.new()
	fm.speed = 1.0
	check(fm.turn_rate() < Config.MAX_TURN_RATE, "slow flight is mushy")
	check_approx(fm.turn_rate(), Config.MAX_TURN_RATE * Config.MIN_TURN_SCALE, 1e-6,
		"authority floors at MIN_TURN_SCALE")

func test_turn_rate_falls_off_when_fast() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.MAX_SPEED
	check(fm.turn_rate() < Config.MAX_TURN_RATE, "high speed stiffens the turn")
	check(fm.turn_rate() >= Config.MAX_TURN_RATE * Config.HIGH_SPEED_TURN_FLOOR - 1e-6,
		"authority floors at HIGH_SPEED_TURN_FLOOR")

func test_steering_never_exceeds_turn_rate() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var before := fm.forward()
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.RIGHT
	fm.apply_steering(cmd, 0.1)
	check(before.angle_to(fm.forward()) <= fm.turn_rate() * 0.1 + 1e-5,
		"one step turns at most turn_rate * dt")

func test_steering_converges_on_aim() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3(1.0, 0.0, -1.0).normalized()
	for i in 200:
		fm.apply_steering(cmd, 1.0 / 60.0)
	check(fm.forward().angle_to(cmd.aim_dir) < 0.01, "the nose reaches the aim direction")

func test_steering_ignores_degenerate_aim() -> void:
	var fm := FlightModel.new()
	var before := fm.forward()
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.ZERO
	fm.apply_steering(cmd, 0.1)
	check_approx(before.angle_to(fm.forward()), 0.0, 1e-9, "a zero aim vector is ignored")
	cmd.aim_dir = Vector3(NAN, 0.0, 0.0)
	fm.apply_steering(cmd, 0.1)
	check(fm.forward().is_finite(), "a non-finite aim vector must not corrupt the basis")

func test_level_flight_has_no_bank() -> void:
	var fm := FlightModel.new()
	check_approx(fm.bank_angle(), 0.0, 1e-6, "an identity basis is wings level")

func test_right_turn_banks_right() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.RIGHT
	for i in 30:
		fm.apply_steering(cmd, 1.0 / 60.0)
		fm.apply_bank(cmd, 1.0 / 60.0)
	check(fm.bank_angle() > 0.1, "a sustained right turn banks right")

func test_left_turn_banks_left() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.LEFT
	for i in 30:
		fm.apply_steering(cmd, 1.0 / 60.0)
		fm.apply_bank(cmd, 1.0 / 60.0)
	check(fm.bank_angle() < -0.1, "a sustained left turn banks left")

func test_bank_is_clamped() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.RIGHT
	var peak := 0.0
	for i in 600:
		fm.apply_steering(cmd, 1.0 / 60.0)
		fm.apply_bank(cmd, 1.0 / 60.0)
		peak = maxf(peak, absf(fm.bank_angle()))
	check(peak > 0.5, "the turn must actually bank substantially, or this test proves nothing")
	check(peak <= Config.MAX_BANK + 0.05, "bank never exceeds MAX_BANK")

func test_manual_roll_rolls() -> void:
	var fm := FlightModel.new()
	var cmd := InputCommand.new()
	cmd.roll = 1.0
	fm.apply_bank(cmd, 0.1)
	check(fm.bank_angle() > 0.0, "positive roll input banks right")

func test_stall_drops_the_nose() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.STALL_SPEED * 0.5
	fm.apply_stall_sag(0.5)
	check(fm.forward().y < -0.01, "below stall speed the nose pitches down")

func test_no_sag_above_stall_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.STALL_SPEED + 1.0
	fm.apply_stall_sag(0.5)
	check_approx(fm.forward().y, 0.0, 1e-9, "above stall speed the nose is untouched")

func _fly(dt: float, seconds: float) -> FlightModel:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.throttle = 0.6
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3(0.3, 0.1, -1.0).normalized()
	for i in int(round(seconds / dt)):
		fm.step(cmd, dt)
	return fm

func test_step_moves_the_plane_forward() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	var cmd := InputCommand.new()
	cmd.aim_dir = fm.forward()
	fm.step(cmd, 0.1)
	check(fm.position.z < -9.0, "the plane advances along its nose (-Z)")

func test_trajectory_is_framerate_independent() -> void:
	var fast := _fly(1.0 / 120.0, 3.0)
	var slow := _fly(1.0 / 45.0, 3.0)
	check(fast.forward().angle_to(slow.forward()) < 0.01,
		"final heading must not depend on timestep")
	var path := fast.position.length()
	check(fast.position.distance_to(slow.position) <= 0.02 * path,
		"final position must agree within 2 percent of distance travelled")

func test_stall_recovery_terminates() -> void:
	var fm := FlightModel.new()
	fm.speed = 5.0
	fm.throttle = 1.0
	var cmd := InputCommand.new()
	var recovered := false
	for i in 1200:  # 20 seconds
		cmd.aim_dir = fm.forward()
		fm.step(cmd, 1.0 / 60.0)
		if fm.speed > Config.STALL_SPEED:
			recovered = true
			break
	check(recovered, "a deep stall recovers within 20 seconds")
	check(fm.basis.is_finite(), "the basis stays finite through a stall")

func test_vertical_stall_recovers() -> void:
	var fm := FlightModel.new()
	fm.speed = 5.0
	fm.throttle = 1.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(89.0))  # near-vertical zoom climb
	var cmd := InputCommand.new()
	var recovered := false
	for i in 1800:  # 30 seconds
		cmd.aim_dir = fm.forward()
		fm.step(cmd, 1.0 / 60.0)
		if fm.speed > Config.STALL_SPEED:
			recovered = true
			break
	check(recovered, "a near-vertical zoom climb to near-zero speed recovers")

func test_state_stays_finite_under_long_simulation() -> void:
	var fm := FlightModel.new()
	var cmd := InputCommand.new()
	for i in 3600:  # one minute of hard turning
		cmd.aim_dir = Vector3(sin(i * 0.01), 0.2, -1.0)
		fm.step(cmd, 1.0 / 60.0)
	check(fm.position.is_finite(), "position stays finite")
	check(fm.basis.is_finite(), "basis stays finite")
	check(fm.speed >= 0.0 and fm.speed <= Config.MAX_SPEED + 1.0, "speed stays in band")

func test_idle_throttle_settles_into_a_glide() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.MIN_SPEED
	fm.throttle = 0.0
	var cmd := InputCommand.new()
	for i in 1800:  # 30 seconds
		cmd.aim_dir = fm.forward()
		fm.step(cmd, 1.0 / 60.0)
	check(fm.position.y < 0.0, "idle throttle descends rather than holding altitude")
	check(fm.speed > 0.0 and fm.speed <= Config.MAX_SPEED + 1.0, "glide speed stays in band")
	check(fm.basis.is_finite(), "a long glide does not corrupt the basis")

func test_level_flight_holds_altitude() -> void:
	var fm := FlightModel.new()
	fm.throttle = 0.6
	fm.speed = lerpf(Config.MIN_SPEED, Config.MAX_SPEED, 0.6)
	var cmd := InputCommand.new()
	for i in 600:  # 10 seconds
		cmd.aim_dir = fm.forward()
		fm.step(cmd, 1.0 / 60.0)
	check(absf(fm.position.y) < 1.0, "level flight with neutral input holds altitude")
	check(fm.speed > Config.STALL_SPEED, "cruise throttle stays clear of stall speed")
