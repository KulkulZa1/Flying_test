extends TestCase

func test_stick_at_its_origin_is_neutral() -> void:
	var aim := TouchControls.stick_aim(Vector2(100.0, 200.0), Vector2(100.0, 200.0))
	check_approx(aim.length(), 0.0, 1e-6, "a touch that has not moved commands nothing")

func test_full_radius_drag_gives_full_deflection() -> void:
	var origin := Vector2(100.0, 200.0)
	var aim := TouchControls.stick_aim(origin, origin + Vector2(Config.TOUCH_STICK_RADIUS, 0.0))
	check_approx(aim.x, 1.0, 1e-6, "a full-radius drag right gives full right deflection")
	check_approx(aim.y, 0.0, 1e-6, "a purely horizontal drag has no vertical component")

func test_stick_saturates_beyond_its_radius() -> void:
	var aim := TouchControls.stick_aim(Vector2.ZERO, Vector2(Config.TOUCH_STICK_RADIUS * 10.0, 0.0))
	check_approx(aim.length(), 1.0, 1e-6, "dragging past the ring cannot exceed full deflection")
