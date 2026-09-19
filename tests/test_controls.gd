extends TestCase

func test_centred_pointer_aims_along_the_nose() -> void:
	var aim := PlayerController.aim_from_offset(Basis.IDENTITY, Vector2.ZERO)
	check(aim.angle_to(Vector3.FORWARD) < 1e-5, "a centred pointer aims straight ahead")

func test_pointer_right_aims_right() -> void:
	var aim := PlayerController.aim_from_offset(Basis.IDENTITY, Vector2(1.0, 0.0))
	check(aim.x > 0.0, "moving the pointer right aims right")

func test_pointer_down_aims_down() -> void:
	var aim := PlayerController.aim_from_offset(Basis.IDENTITY, Vector2(0.0, 1.0))
	check(aim.y < 0.0, "screen Y grows downward, so a low pointer aims the nose down")

func test_aim_is_clamped_to_the_cone() -> void:
	var cone := deg_to_rad(Config.AIM_CONE_DEG)
	var straight := PlayerController.aim_from_offset(Basis.IDENTITY, Vector2(1.0, 0.0))
	check_approx(straight.angle_to(Vector3.FORWARD), cone, 1e-4,
		"a fully deflected pointer aims exactly at the cone edge")
	var diagonal := PlayerController.aim_from_offset(Basis.IDENTITY, Vector2(3.0, 3.0))
	check(diagonal.angle_to(Vector3.FORWARD) <= cone + 1e-3,
		"an over-deflected diagonal is still inside the cone")

func test_aim_follows_the_aircraft_orientation() -> void:
	var turned := Basis(Vector3.UP, PI * 0.5)
	var aim := PlayerController.aim_from_offset(turned, Vector2.ZERO)
	check(aim.angle_to(-turned.z) < 1e-5, "a centred pointer aims along the aircraft's own nose")

func test_aim_does_not_depend_on_bank() -> void:
	var level := Basis.IDENTITY
	var banked := Basis(Vector3.FORWARD, deg_to_rad(75.0))
	var offset := Vector2(0.5, 0.0)
	check(PlayerController.aim_from_offset(level, offset).angle_to(
		PlayerController.aim_from_offset(banked, offset)) < 1e-4,
		"a banked aircraft must aim where a level one does, or every turn becomes a dive")

func test_a_held_turn_holds_altitude() -> void:
	var fm := FlightModel.new()
	fm.throttle = Config.START_THROTTLE
	fm.speed = lerpf(Config.MIN_SPEED, Config.MAX_SPEED, Config.START_THROTTLE)
	fm.position = Vector3(0.0, 600.0, 0.0)
	var cmd := InputCommand.new()
	var lowest := fm.position.y
	for i in 1800:  # thirty seconds of a held right turn
		cmd.aim_dir = PlayerController.aim_from_offset(fm.basis, Vector2(0.5, 0.0))
		fm.step(cmd, 1.0 / 60.0)
		lowest = minf(lowest, fm.position.y)
	check(lowest > 400.0, "a sustained held turn must not descend into the ground")
	check(absf(fm.basis.determinant() - 1.0) < 1e-4, "a sustained held turn stays well-conditioned")

func test_small_pointer_movements_are_ignored() -> void:
	check_approx(PlayerController.apply_deadzone(Vector2(Config.AIM_DEADZONE * 0.5, 0.0)).length(),
		0.0, 1e-6, "a pointer inside the deadzone commands nothing")

func test_deadzone_ramps_then_saturates() -> void:
	var just_out := PlayerController.apply_deadzone(Vector2(Config.AIM_DEADZONE + 0.02, 0.0))
	check(just_out.length() > 0.0 and just_out.length() < 0.1,
		"just outside the deadzone gives a small command, not a jump to full")
	check_approx(PlayerController.apply_deadzone(Vector2(5.0, 0.0)).length(), 1.0, 1e-6,
		"far outside the deadzone saturates at full deflection")
