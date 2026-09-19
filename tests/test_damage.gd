extends TestCase

class TriggerHeld extends RefCounted:
	func command(aircraft, _dt) -> InputCommand:
		var cmd := InputCommand.new()
		cmd.aim_dir = aircraft.model.forward()
		cmd.fire = true
		return cmd

func test_damage_reduces_health() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.ENEMY_HP
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	aircraft.take_damage(Config.BULLET_DAMAGE)
	check_approx(aircraft.hp, Config.ENEMY_HP - Config.BULLET_DAMAGE, 1e-6,
		"a hit removes BULLET_DAMAGE health")
	check(aircraft.is_alive(), "one hit does not kill an enemy")
	aircraft.free()

func test_enough_damage_kills() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.ENEMY_HP
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	for i in int(ceil(Config.ENEMY_HP / Config.BULLET_DAMAGE)):
		aircraft.take_damage(Config.BULLET_DAMAGE)
	check(not aircraft.is_alive(), "enough hits kill")
	check(aircraft.hp <= 0.0, "health does not go back up")
	aircraft.free()

func test_reset_restores_full_health() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.PLAYER_HP
	aircraft.take_damage(Config.PLAYER_HP)
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	check_approx(aircraft.hp, Config.PLAYER_HP, 1e-6, "respawning restores full health")
	check(aircraft.is_alive(), "and the aircraft is alive again")
	aircraft.free()

func test_death_fires_once_however_many_rounds_land() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.ENEMY_HP
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	var deaths := [0]
	aircraft.died.connect(func(): deaths[0] += 1)
	for i in 20:
		aircraft.take_damage(Config.BULLET_DAMAGE)
	check(deaths[0] == 1, "death fires exactly once")
	aircraft.free()

func test_a_held_trigger_produces_rounds_at_the_configured_rate() -> void:
	var aircraft := Aircraft.new()
	aircraft.controller = TriggerHeld.new()
	aircraft.reset(Vector3(0.0, 2000.0, 0.0))
	var rounds := 0
	for i in 600:
		aircraft.tick(1.0 / 60.0)
		if aircraft.fired:
			rounds += 1
	check_approx(float(rounds), Config.FIRE_RATE * 10.0, 2.0,
		"an aircraft with the trigger held produces about FIRE_RATE rounds a second")
	aircraft.free()

func test_the_muzzle_sits_ahead_of_the_nose() -> void:
	var aircraft := Aircraft.new()
	aircraft.reset(Vector3.ZERO)
	check_approx(aircraft.muzzle().distance_to(aircraft.model.position), Config.MUZZLE_FORWARD,
		1e-4, "the muzzle sits MUZZLE_FORWARD ahead of the model origin")
	check(aircraft.muzzle().z < 0.0, "and ahead of the nose, which points at -Z")
	aircraft.free()

func test_combat_position_tracks_the_model_not_the_node() -> void:
	var aircraft := Aircraft.new()
	aircraft.reset(Vector3(120.0, 700.0, -50.0))
	check(aircraft.combat_position().is_equal_approx(Vector3(120.0, 700.0, -50.0)),
		"combat position follows the model even outside a scene tree")
	aircraft.free()
