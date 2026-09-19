extends TestCase

## Stands in for an Aircraft. Exposes combat_position() for the same reason the
## real one does: a node's .position is stale outside a scene tree.
class Dummy extends RefCounted:
	var where := Vector3.ZERO
	func _init(at: Vector3) -> void:
		where = at
	func combat_position() -> Vector3:
		return where

func test_a_round_travels_at_bullet_speed() -> void:
	var bullets := Bullets.new()
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	bullets.step(1.0, [])
	check_approx(bullets.position_of(0).length(), Config.BULLET_SPEED, 1.0,
		"a round covers BULLET_SPEED metres in one second")
	bullets.free()

func test_a_round_expires() -> void:
	var bullets := Bullets.new()
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	bullets.step(Config.BULLET_LIFETIME + 0.1, [])
	check(bullets.count() == 0, "a round is gone once its lifetime elapses")
	bullets.free()

func test_a_round_hits_a_target_in_its_path() -> void:
	var bullets := Bullets.new()
	var target := Dummy.new(Vector3(0.0, 0.0, -100.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	var hits := bullets.step(0.5, [target])
	check(hits.size() == 1, "a round passing through a target reports one hit")
	check(hits[0]["target"] == target, "and reports which target it hit")
	check(bullets.count() == 0, "and is consumed")
	bullets.free()

func test_a_round_cannot_hit_its_own_shooter() -> void:
	var bullets := Bullets.new()
	var shooter := Dummy.new(Vector3(0.0, 0.0, -20.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, shooter)
	var hits := bullets.step(0.5, [shooter])
	check(hits.is_empty(), "a round passes through the aircraft that fired it")
	bullets.free()

func test_a_round_cannot_tunnel_past_a_target() -> void:
	var bullets := Bullets.new()
	var target := Dummy.new(Vector3(0.0, 0.0, -300.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	# One full second steps the round 600 m, straight past a 6 m target.
	var hits := bullets.step(1.0, [target])
	check(hits.size() == 1, "a round that overshoots within one tick still registers a hit")
	bullets.free()

func test_a_degenerate_direction_spawns_nothing() -> void:
	var bullets := Bullets.new()
	bullets.spawn(Vector3.ZERO, Vector3.ZERO, null)
	bullets.spawn(Vector3.ZERO, Vector3(NAN, 0.0, 0.0), null)
	check(bullets.count() == 0, "a zero or non-finite direction produces no round")
	bullets.free()

func test_a_hit_reports_who_fired_it() -> void:
	var bullets := Bullets.new()
	var shooter := Dummy.new(Vector3(0.0, 0.0, 500.0))
	var target := Dummy.new(Vector3(0.0, 0.0, -100.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, shooter)
	var hits := bullets.step(0.5, [target])
	check(hits.size() == 1 and hits[0]["shooter"] == shooter,
		"a hit names the craft that fired, so a kill can be told from a crossfire")
	bullets.free()

func test_rounds_do_not_accumulate_without_bound() -> void:
	var bullets := Bullets.new()
	for i in 1800:  # thirty seconds of continuous fire
		bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
		bullets.step(1.0 / 60.0, [])
	check(bullets.count() <= int(Config.BULLET_LIFETIME * 60.0) + 2,
		"live rounds stay bounded, so a long fight cannot leak")
	bullets.free()
