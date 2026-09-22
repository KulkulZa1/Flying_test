extends TestCase

## The radius is passed in rather than read from Config: it is a fraction of
## viewport height now, so there is no single correct value to assert against.
const RADIUS := 200.0

func test_stick_at_its_origin_is_neutral() -> void:
	var aim := TouchControls.stick_aim(Vector2(100.0, 200.0), Vector2(100.0, 200.0), RADIUS)
	check_approx(aim.length(), 0.0, 1e-6, "a touch that has not moved commands nothing")

func test_full_radius_drag_gives_full_deflection() -> void:
	var origin := Vector2(100.0, 200.0)
	var aim := TouchControls.stick_aim(origin, origin + Vector2(RADIUS, 0.0), RADIUS)
	check_approx(aim.x, 1.0, 1e-6, "a full-radius drag right gives full right deflection")
	check_approx(aim.y, 0.0, 1e-6, "a purely horizontal drag has no vertical component")

func test_stick_saturates_beyond_its_radius() -> void:
	var aim := TouchControls.stick_aim(Vector2.ZERO, Vector2(RADIUS * 10.0, 0.0), RADIUS)
	check_approx(aim.length(), 1.0, 1e-6, "dragging past the ring cannot exceed full deflection")

func test_a_degenerate_radius_cannot_divide_by_zero() -> void:
	var aim := TouchControls.stick_aim(Vector2.ZERO, Vector2(50.0, 0.0), 0.0)
	check(aim.is_finite(), "a zero radius yields a finite command rather than infinity")
	check_approx(aim.length(), 1.0, 1e-6, "and saturates rather than exploding")

func test_the_stick_scales_with_the_viewport() -> void:
	var small := TouchControls.new()
	small.fit_to(Vector2(960.0, 540.0))
	var large := TouchControls.new()
	large.fit_to(Vector2(2400.0, 1080.0))
	check(large.stick_radius() > small.stick_radius(),
		"a taller viewport gets a larger stick, so it reads the same on any screen")
	check_approx(large.stick_radius() / large.size.y, small.stick_radius() / small.size.y, 1e-4,
		"and it stays the same fraction of screen height")
	small.free()
	large.free()

func test_the_stick_has_a_floor_on_tiny_viewports() -> void:
	var tiny := TouchControls.new()
	tiny.fit_to(Vector2(200.0, 120.0))
	check(tiny.stick_radius() >= Config.TOUCH_STICK_MIN_RADIUS,
		"a very short viewport still gets a usable stick rather than a few pixels")
	tiny.free()
