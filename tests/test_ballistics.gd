extends TestCase

func test_a_segment_through_a_sphere_hits() -> void:
	check(Ballistics.segment_hits_sphere(
		Vector3(-10.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), Vector3.ZERO, 5.0),
		"a segment through the centre hits")

func test_a_segment_beside_a_sphere_misses() -> void:
	check(not Ballistics.segment_hits_sphere(
		Vector3(-10.0, 20.0, 0.0), Vector3(10.0, 20.0, 0.0), Vector3.ZERO, 5.0),
		"a segment passing well clear misses")

func test_a_segment_stopping_short_misses() -> void:
	check(not Ballistics.segment_hits_sphere(
		Vector3(-10.0, 0.0, 0.0), Vector3(-8.0, 0.0, 0.0), Vector3.ZERO, 5.0),
		"a segment that stops before the sphere misses")

func test_a_fast_round_cannot_tunnel() -> void:
	# A round that steps from one side of a target to the other within a single
	# tick: neither endpoint is inside, so only a swept test can catch it.
	var a := Vector3(0.0, 0.0, -7.0)
	var b := Vector3(0.0, 0.0, 7.0)
	check(a.distance_to(Vector3.ZERO) > Config.HIT_RADIUS,
		"the round starts outside the target")
	check(b.distance_to(Vector3.ZERO) > Config.HIT_RADIUS,
		"and ends outside it")
	check(Ballistics.segment_hits_sphere(a, b, Vector3.ZERO, Config.HIT_RADIUS),
		"yet the sweep still registers the hit")

func test_lead_point_is_ahead_of_a_crossing_target() -> void:
	var lead := Ballistics.lead_point(Vector3.ZERO, Vector3(0.0, 0.0, -600.0),
		Vector3(100.0, 0.0, 0.0), Config.BULLET_SPEED)
	check(lead.x > 50.0, "the lead point sits ahead of a target crossing to the right")

func test_lead_point_on_a_stationary_target_is_the_target() -> void:
	var target := Vector3(0.0, 0.0, -400.0)
	var lead := Ballistics.lead_point(Vector3.ZERO, target, Vector3.ZERO, Config.BULLET_SPEED)
	check(lead.distance_to(target) < 1e-3, "a stationary target needs no lead")

func test_lead_point_is_finite_for_an_unreachable_target() -> void:
	# Fleeing faster than the round travels: there is no intercept.
	var lead := Ballistics.lead_point(Vector3.ZERO, Vector3(0.0, 0.0, -400.0),
		Vector3(0.0, 0.0, -Config.BULLET_SPEED * 2.0), Config.BULLET_SPEED)
	check(lead.is_finite(), "an unreachable target still yields a finite aim point")
