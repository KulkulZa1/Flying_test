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
