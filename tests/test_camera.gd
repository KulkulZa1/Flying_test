extends TestCase

func test_fov_widens_with_speed() -> void:
	check_approx(ChaseCamera.fov_for_speed(Config.MIN_SPEED), Config.CAM_FOV_MIN, 1e-4,
		"minimum speed gives the narrow field of view")
	check_approx(ChaseCamera.fov_for_speed(Config.MAX_SPEED), Config.CAM_FOV_MAX, 1e-4,
		"maximum speed gives the wide field of view")
	check(ChaseCamera.fov_for_speed(Config.MIN_SPEED - 100.0) >= Config.CAM_FOV_MIN - 1e-4,
		"field of view clamps below the speed band")
	check(ChaseCamera.fov_for_speed(Config.MAX_SPEED + 100.0) <= Config.CAM_FOV_MAX + 1e-4,
		"field of view clamps above the speed band")

func test_camera_sits_behind_and_above() -> void:
	var placed := ChaseCamera.desired_position(Transform3D.IDENTITY)
	check(placed.z > 0.0, "the camera sits behind the nose, which points at -Z")
	check(placed.y > 0.0, "the camera sits above the aircraft")

func test_camera_follows_the_aircraft_banking() -> void:
	var rolled := Transform3D(Basis(Vector3.FORWARD, 1.0), Vector3.ZERO)
	var placed := ChaseCamera.desired_position(rolled)
	check(placed.is_finite(), "a banked aircraft still yields a finite camera position")
	check(absf(placed.length() - ChaseCamera.desired_position(Transform3D.IDENTITY).length()) < 1e-3,
		"banking moves the camera around the aircraft, not away from it")
