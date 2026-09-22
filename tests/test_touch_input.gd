extends TestCase

## Drives the real handler with synthesised events. Control.size is settable
## outside a scene tree, so a realistic phone viewport can be simulated.
const SCREEN := Vector2(2400.0, 1080.0)

func _controls() -> TouchControls:
	var controls := TouchControls.new()
	controls.size = SCREEN
	return controls

func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	return event

func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	return event

func test_letting_go_of_the_throttle_does_not_stop_you_firing() -> void:
	var controls := _controls()
	controls._input(_touch(0, controls.fire_centre(), true))
	controls._input(_touch(1, controls.throttle_rect().get_center() + Vector2(0.0, -40.0), true))
	check(controls.fire and controls.throttle_delta > 0.0, "both are held")
	controls._input(_touch(1, Vector2.ZERO, false))
	check(controls.fire, "releasing the throttle leaves the trigger down")
	check(controls.throttle_delta == 0.0, "and only the throttle is released")
	controls.free()

func test_letting_go_of_fire_does_not_zero_the_throttle() -> void:
	var controls := _controls()
	controls._input(_touch(0, controls.throttle_rect().get_center() + Vector2(0.0, -40.0), true))
	controls._input(_touch(1, controls.fire_centre(), true))
	controls._input(_touch(1, Vector2.ZERO, false))
	check(controls.throttle_delta > 0.0, "releasing the trigger leaves the throttle set")
	check(not controls.fire, "and only the trigger is released")
	controls.free()

func test_a_stray_touch_does_not_clear_held_controls() -> void:
	var controls := _controls()
	controls._input(_touch(0, Vector2(300.0, 500.0), true))            # stick
	controls._input(_touch(1, controls.fire_centre(), true))
	controls._input(_touch(2, Vector2(200.0, 900.0), true))            # a palm, left half
	controls._input(_touch(2, Vector2(200.0, 900.0), false))
	check(controls.fire, "a stray finger lifting does not stop you firing")
	check(controls._stick_touch == 0, "and does not steal the stick")
	controls.free()

func test_the_throttle_behaves_as_a_slider() -> void:
	var controls := _controls()
	var rect := controls.throttle_rect()
	controls._input(_touch(0, rect.get_center() + Vector2(0.0, 40.0), true))
	check(controls.throttle_delta < 0.0, "pressing low commands throttle down")
	controls._input(_drag(0, rect.get_center() + Vector2(0.0, -40.0)))
	check(controls.throttle_delta > 0.0, "dragging up commands throttle up without lifting")
	controls.free()

func test_a_press_outside_the_drawn_controls_does_nothing() -> void:
	var controls := _controls()
	controls._input(_touch(0, Vector2(SCREEN.x * 0.55, SCREEN.y * 0.5), true))
	check(controls.throttle_delta == 0.0 and not controls.fire,
		"the right half is not one big throttle: only the drawn controls are live")
	controls.free()

func test_all_three_controls_work_at_once() -> void:
	var controls := _controls()
	controls._input(_touch(0, Vector2(300.0, 500.0), true))
	controls._input(_drag(0, Vector2(300.0 + Config.TOUCH_STICK_RADIUS, 500.0)))
	controls._input(_touch(1, controls.throttle_rect().get_center() + Vector2(0.0, -40.0), true))
	controls._input(_touch(2, controls.fire_centre(), true))
	check(controls.aim.x > 0.9 and controls.throttle_delta > 0.0 and controls.fire,
		"stick, throttle and trigger are usable simultaneously")
	controls.free()

func test_focus_loss_releases_everything() -> void:
	var controls := _controls()
	controls._input(_touch(0, Vector2(300.0, 500.0), true))
	controls._input(_touch(1, controls.fire_centre(), true))
	controls.release_all()
	check(controls.aim == Vector2.ZERO and not controls.fire and controls.throttle_delta == 0.0,
		"backgrounding does not leave a stuck stick and a stuck trigger")
	controls.free()

func test_the_fire_zone_matches_the_drawn_button() -> void:
	var controls := _controls()
	var just_outside := controls.fire_centre() + Vector2(controls.fire_radius() + 12.0, 0.0)
	controls._input(_touch(0, just_outside, true))
	check(not controls.fire, "a press outside the drawn circle does not fire")
	controls.free()

## Every other test in this file assigns size by hand, which is precisely how a
## zero-size overlay shipped: created in code rather than loaded from a scene, it
## kept its default zero rect, so every hit zone collapsed to a point, nothing
## was drawn, and `at.x < size.x * 0.5` could never be true. Adding it to a real
## tree is the only way to catch that.
## The bug this guards against — an overlay built in code keeping a zero rect,
## which collapses every hit zone to a point and makes the game uncontrollable —
## is NOT reachable from this harness. Inside SceneTree._initialize() a node
## added to root is not yet in the tree, so _ready() never runs and
## get_viewport_rect() errors. It was found by rendering a frame and seeing the
## controls missing, and the wiring is verified the same way. This pins only the
## arithmetic that the wiring feeds.
func test_fitting_to_an_extent_fills_it() -> void:
	var controls := TouchControls.new()
	controls.fit_to(Vector2(2400.0, 1080.0))
	check(controls.size.is_equal_approx(Vector2(2400.0, 1080.0)),
		"fitting adopts the given extent rather than staying at zero")
	check(controls.position.is_zero_approx(), "and sits at the origin")
	check(controls.fire_radius() > 0.0 and controls.throttle_rect().size.x > 0.0,
		"so the hit zones are non-degenerate")
	controls.free()
