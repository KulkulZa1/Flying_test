extends TestCase

## The shape of test this project keeps needing: real components composed, run
## long enough for emergent behaviour, rather than each checked alone.

func _craft(at: Vector3, hp: float) -> Aircraft:
	var aircraft := Aircraft.new()
	aircraft.max_hp = hp
	aircraft.reset(at)
	return aircraft

func _fight(prey_controller, seconds: float) -> Dictionary:
	var hunter := _craft(Vector3(0.0, 800.0, 900.0), Config.ENEMY_HP)
	var prey := _craft(Vector3(0.0, 800.0, 0.0), Config.PLAYER_HP)
	prey.controller = prey_controller
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	pilot.target = prey
	hunter.controller = pilot
	var bullets := Bullets.new()
	var dt := 1.0 / 60.0
	var ticks := 0
	for i in int(seconds * 60.0):
		ticks = i
		hunter.tick(dt)
		if prey.controller != null:
			prey.tick(dt)
		if hunter.fired:
			bullets.spawn(hunter.muzzle(), hunter.model.forward(), hunter)
		for hit in bullets.step(dt, [prey, hunter]):
			hit["target"].take_damage(Config.BULLET_DAMAGE)
		if not prey.is_alive():
			break
	var result := {
		"killed": not prey.is_alive(),
		"ticks": ticks,
		"live_rounds": bullets.count(),
		"determinant": hunter.model.basis.determinant(),
		"hunter_altitude": hunter.model.position.y,
	}
	hunter.free()
	prey.free()
	bullets.free()
	return result

class Stationary extends RefCounted:
	func command(aircraft, _dt) -> InputCommand:
		var cmd := InputCommand.new()
		cmd.aim_dir = aircraft.model.forward()
		return cmd

func test_an_ai_kills_a_target_flying_straight() -> void:
	var result := _fight(Stationary.new(), 90.0)
	check(result["killed"], "an AI with perfect aim eventually kills a target flying straight")

func test_a_fight_stays_well_conditioned() -> void:
	var result := _fight(Stationary.new(), 90.0)
	check(absf(result["determinant"] - 1.0) < 1e-4, "the hunter's basis stays orthonormal")
	check(result["hunter_altitude"] > 0.0, "and the hunter never flies into the ground")

func test_live_rounds_stay_bounded_through_a_fight() -> void:
	var result := _fight(Stationary.new(), 90.0)
	check(result["live_rounds"] <= int(Config.FIRE_RATE * Config.BULLET_LIFETIME) + 5,
		"live rounds stay near FIRE_RATE * BULLET_LIFETIME, so a long fight cannot leak")
