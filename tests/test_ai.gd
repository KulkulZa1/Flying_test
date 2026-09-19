extends TestCase

func _craft_at(where: Vector3) -> Aircraft:
	var aircraft := Aircraft.new()
	aircraft.reset(where)
	return aircraft

func test_ai_pursues_a_distant_target() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var prey := _craft_at(Vector3(0.0, 600.0, -1500.0))
	pilot.target = prey
	pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.PURSUE, "a distant target is pursued")
	hunter.free()
	prey.free()

func test_ai_attacks_when_close_and_lined_up() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var prey := _craft_at(Vector3(0.0, 600.0, -300.0))  # dead ahead, inside range
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.ATTACK, "a target in the cone and in range is attacked")
	check(cmd.fire, "and the trigger is pulled")
	hunter.free()
	prey.free()

func test_ai_holds_fire_when_out_of_the_cone() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var prey := _craft_at(Vector3(300.0, 600.0, 0.0))  # abeam, in range but not ahead
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.PURSUE, "a target off the nose is pursued, not shot at")
	check(not cmd.fire, "and the trigger stays off")
	hunter.free()
	prey.free()

func test_ai_breaks_off_when_too_close() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var prey := _craft_at(Vector3(0.0, 600.0, -Config.MIN_SEPARATION * 0.5))
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.BREAK, "a target inside MIN_SEPARATION triggers a break")
	check(not cmd.fire, "and the AI stops shooting while breaking off")
	hunter.free()
	prey.free()

func test_a_break_ends_by_itself() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var prey := _craft_at(Vector3(0.0, 600.0, -2000.0))
	pilot.target = prey
	pilot.state = AIPilot.State.BREAK
	pilot.state_timer = Config.BREAK_TIME
	for i in int(Config.BREAK_TIME * 60.0) + 10:
		pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state != AIPilot.State.BREAK, "a break times out rather than lasting forever")
	hunter.free()
	prey.free()

func test_ai_climbs_when_low() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 50.0, 0.0))
	var prey := _craft_at(Vector3(0.0, 600.0, -2000.0))
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.REPOSITION, "an AI below its floor repositions")
	check(cmd.aim_dir.y > 0.0, "and aims upward")
	hunter.free()
	prey.free()

func test_ai_aim_does_not_depend_on_its_own_bank() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var prey := _craft_at(Vector3(0.0, 600.0, -800.0))
	pilot.target = prey
	var level := _craft_at(Vector3(0.0, 600.0, 0.0))
	var banked := _craft_at(Vector3(0.0, 600.0, 0.0))
	banked.model.basis = Basis(Vector3.FORWARD, deg_to_rad(75.0))
	var a := pilot.command(level, 1.0 / 60.0).aim_dir
	var b := pilot.command(banked, 1.0 / 60.0).aim_dir
	check(a.angle_to(b) < 1e-3,
		"AI aim must be world-space, or Phase 1's dive bug returns with the enemies")
	level.free()
	banked.free()
	prey.free()

func test_ai_survives_a_missing_target() -> void:
	var pilot := AIPilot.new()
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(cmd.aim_dir.is_finite(), "an AI with no target still produces a usable command")
	check(not cmd.fire, "and does not shoot at nothing")
	hunter.free()

func test_a_dogfight_stays_airborne_and_bounded() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 800.0, 400.0))
	var prey := _craft_at(Vector3(0.0, 800.0, -400.0))
	pilot.target = prey
	hunter.controller = pilot
	var lowest := hunter.model.position.y
	var furthest := 0.0
	for i in 3600:  # one minute of chasing a stationary target
		hunter.tick(1.0 / 60.0)
		lowest = minf(lowest, hunter.model.position.y)
		furthest = maxf(furthest, Vector2(hunter.model.position.x, hunter.model.position.z).length())
	check(lowest > 0.0, "an AI chasing a target for a minute does not fly into the ground")
	check(furthest < Config.WORLD_SIZE * 0.5, "and stays inside the world")
	check(absf(hunter.model.basis.determinant() - 1.0) < 1e-4, "and stays well-conditioned")
	hunter.free()
	prey.free()
