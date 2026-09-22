extends TestCase

## Marker geometry is deliberately checked with the viewer BANKED. A level viewer
## makes the view basis the identity, so a marker computed in the wrong frame
## would look identical to one computed correctly - the same trap that let an AI
## aim test pass with the Phase 1 dive bug present.

func test_an_enemy_ahead_is_not_behind() -> void:
	check(not HUD.is_behind(Basis.IDENTITY, Vector3(0.0, 0.0, -500.0)),
		"a target down the nose is not behind")

func test_an_enemy_astern_is_behind() -> void:
	check(HUD.is_behind(Basis.IDENTITY, Vector3(0.0, 0.0, 500.0)),
		"a target astern is behind")

func test_a_marker_points_right_for_an_enemy_to_starboard() -> void:
	var direction := HUD.marker_direction(Basis.IDENTITY, Vector3(500.0, 0.0, -100.0))
	check(direction.x > 0.9, "an enemy to starboard puts the marker to the right")
	check_approx(direction.length(), 1.0, 1e-5, "and the marker direction is a unit vector")

func test_a_marker_points_up_for_an_enemy_above() -> void:
	var direction := HUD.marker_direction(Basis.IDENTITY, Vector3(0.0, 500.0, -100.0))
	check(direction.y < -0.9, "an enemy above puts the marker up, and screen Y grows downward")

func test_markers_follow_the_pilot_frame_not_the_world() -> void:
	# Rolled 90 degrees right: an enemy that is world-above is now to the pilot's
	# left, so the marker must swing accordingly.
	var rolled := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	var direction := HUD.marker_direction(rolled, Vector3(0.0, 500.0, -100.0))
	check(absf(direction.x) > 0.9,
		"with the aircraft rolled, a world-above enemy marks to one side")

func test_the_death_banner_shows_then_expires() -> void:
	var hud := HUD.new()
	hud.show_death(4321)
	check(hud.banner_seconds > 0.0, "a death raises the banner")
	check(hud.banner_score == 4321, "carrying the score the run ended on")
	hud.advance_banner(Config.DEATH_BANNER_SECONDS + 0.1)
	check(hud.banner_seconds <= 0.0, "and it expires by itself rather than sticking")
	hud.free()

func test_the_banner_does_not_go_negative() -> void:
	var hud := HUD.new()
	hud.show_death(10)
	hud.advance_banner(1000.0)
	check(hud.banner_seconds == 0.0, "a long frame cannot drive the banner negative")
	hud.free()

## The HUD renders at about a millimetre on a phone when sized in fixed pixels.
## These pin the scaling relationship rather than any particular size.

func _sized(height: float) -> HUD:
	var hud := HUD.new()
	hud.size = Vector2(height * 16.0 / 9.0, height)
	return hud

func test_hud_text_scales_with_the_viewport() -> void:
	var small := _sized(648.0)
	var large := _sized(1080.0)
	check(large._font_size() > small._font_size(),
		"a taller viewport gets larger text, or a phone renders it at a millimetre")
	small.free()
	large.free()

func test_hud_text_stays_legible_on_a_phone() -> void:
	var phone := _sized(1080.0)
	check(phone._font_size() >= 32, "text on a 1080-high screen is at least 32 px")
	check(phone._reticle_radius() >= 20.0, "and the reticle is at least 20 px across the radius")
	phone.free()

func test_hud_elements_have_a_floor_on_tiny_viewports() -> void:
	var tiny := _sized(120.0)
	check(tiny._font_size() >= 14 and tiny._line_width() >= 2.0 and tiny._reticle_radius() >= 10.0,
		"a very small viewport still gets usable minimums rather than sub-pixel elements")
	tiny.free()
