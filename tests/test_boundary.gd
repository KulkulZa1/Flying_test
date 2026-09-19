extends TestCase

func test_inside_the_boundary_aim_is_untouched() -> void:
	var aim := Vector3(0.0, 0.0, -1.0)
	var result := Boundary.constrain(aim, Vector3.ZERO)
	check_approx(result.angle_to(aim), 0.0, 1e-6, "aim is unchanged at the world centre")

func test_outside_the_boundary_aim_bends_inward() -> void:
	var outward := Vector3(1.0, 0.0, 0.0)
	var far_east := Vector3(Config.WORLD_SIZE * 0.5, 500.0, 0.0)
	var result := Boundary.constrain(outward, far_east)
	check(result.x < outward.x, "aim bends back toward the centre when far out")

func test_the_bend_grows_with_distance() -> void:
	var outward := Vector3(1.0, 0.0, 0.0)
	var near := Boundary.constrain(outward, Vector3(Config.BOUNDARY_SOFT_START + 100.0, 500.0, 0.0))
	var far := Boundary.constrain(outward, Vector3(Config.WORLD_SIZE * 0.5, 500.0, 0.0))
	check(far.x < near.x, "the further out you are, the harder you are turned back")

func test_constrain_always_returns_a_usable_vector() -> void:
	var far := Vector3(Config.WORLD_SIZE, 500.0, Config.WORLD_SIZE)
	var result := Boundary.constrain(Vector3(1.0, 0.0, 1.0).normalized(), far)
	check(result.is_finite(), "result is finite")
	check(result.length_squared() > 1e-6, "result is not degenerate")

func test_the_turn_back_is_gradual_not_a_snap() -> void:
	var outward := Vector3(1.0, 0.0, 0.0)
	var just_past := Boundary.constrain(outward, Vector3(Config.BOUNDARY_SOFT_START + 50.0, 500.0, 0.0))
	var angle := rad_to_deg(just_past.angle_to(outward))
	check(angle > 1.0, "just past the boundary there is already some correction")
	check(angle < 90.0, "just past the boundary the correction is a bend, not a reversal")
