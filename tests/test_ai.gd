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
	# Start from ATTACK: a pilot constructed in PURSUE would pass this test with
	# its whole state machine deleted.
	pilot.state = AIPilot.State.ATTACK
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
	check(cmd.aim_dir.dot(prey.model.position - hunter.model.position) < 0.0,
		"and turns away from the target rather than holding its heading")
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
	# Below the hunter, so pursuit aim would point down: only a real climb passes.
	var prey := _craft_at(Vector3(0.0, 20.0, -2000.0))
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.REPOSITION, "an AI below its floor repositions")
	check(cmd.aim_dir.y > 0.0, "and aims upward")
	hunter.free()
	prey.free()

func test_ai_aim_does_not_depend_on_its_own_bank() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	# Deliberately off the boresight: a prey dead ahead lies on the roll axis, so
	# a body-frame aim would be numerically identical to a world-frame one and the
	# test would pass with the bug present.
	var prey := _craft_at(Vector3(300.0, 750.0, -800.0))
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

func test_jitter_actually_perturbs_the_aim() -> void:
	var prey := _craft_at(Vector3(250.0, 700.0, -900.0))
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var clean := AIPilot.new()
	clean.jitter_degrees = 0.0
	clean.target = prey
	var jittery := AIPilot.new()
	jittery.jitter_degrees = Config.AIM_JITTER_START_DEG
	jittery.target = prey
	var widest := 0.0
	for i in 600:  # ten seconds, well past any zero crossing
		var a := clean.command(hunter, 1.0 / 60.0).aim_dir
		var b := jittery.command(hunter, 1.0 / 60.0).aim_dir
		widest = maxf(widest, rad_to_deg(a.angle_to(b)))
	check(widest > Config.AIM_JITTER_END_DEG,
		"jitter must measurably perturb aim, or enemies are perfect marksmen")
	hunter.free()
	prey.free()

func test_the_ai_leads_a_crossing_target() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 700.0, 0.0))
	var prey := _craft_at(Vector3(0.0, 700.0, -500.0))
	prey.model.basis = Basis(Vector3.UP, -PI * 0.5)  # prey crossing to the right
	prey.model.speed = Config.MAX_SPEED
	pilot.target = prey
	var aim := pilot.command(hunter, 1.0 / 60.0).aim_dir
	var straight := (prey.model.position - hunter.model.position).normalized()
	check(aim.angle_to(straight) > deg_to_rad(2.0),
		"the AI must aim ahead of a crossing target, not straight at it")
	hunter.free()
	prey.free()

func test_pilots_do_not_jitter_in_lockstep() -> void:
	var prey := _craft_at(Vector3(250.0, 700.0, -900.0))
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var a := AIPilot.new()
	var b := AIPilot.new()
	a.target = prey
	b.target = prey
	var widest := 0.0
	for i in 600:
		var aim_a := a.command(hunter, 1.0 / 60.0).aim_dir
		var aim_b := b.command(hunter, 1.0 / 60.0).aim_dir
		widest = maxf(widest, rad_to_deg(aim_a.angle_to(aim_b)))
	check(widest > 1.0,
		"two pilots must not share an aim error, or a whole wave shoots as one gun")
	hunter.free()
	prey.free()

func test_ai_breaks_after_overshooting() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	# Off-axis on purpose, and far enough out that MIN_SEPARATION cannot be what
	# triggers the break - only the pass can.
	var prey := _craft_at(Vector3(40.0, 600.0, -200.0))
	pilot.target = prey
	pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state != AIPilot.State.BREAK, "precondition: a target ahead is not broken from")
	prey.model.position = Vector3(40.0, 600.0, 200.0)  # the hunter has flown past it
	check(prey.model.position.distance_to(hunter.model.position) > Config.MIN_SEPARATION,
		"precondition: outside MIN_SEPARATION, so only the pass can cause a break")
	pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.BREAK, "sliding past the target triggers a break")
	hunter.free()
	prey.free()

func test_a_target_first_seen_behind_is_not_a_pass() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 600.0, 0.0))
	var prey := _craft_at(Vector3(40.0, 600.0, 300.0))  # behind from the start, in range
	pilot.target = prey
	pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.PURSUE,
		"a target that was never ahead has not been overshot, so the AI turns to pursue")
	hunter.free()
	prey.free()

func test_the_ai_re_engages_after_breaking() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 800.0, 400.0))
	var prey := _craft_at(Vector3(35.0, 800.0, -400.0))
	pilot.target = prey
	hunter.controller = pilot
	var broke := false
	var attacked_after_breaking := false
	for i in 3600:  # one minute
		hunter.tick(1.0 / 60.0)
		if pilot.state == AIPilot.State.BREAK:
			broke = true
		elif broke and pilot.state == AIPilot.State.ATTACK:
			attacked_after_breaking = true
	check(broke, "precondition: the fight produces at least one break")
	check(attacked_after_breaking,
		"after breaking off the AI comes back to attack, rather than breaking forever")
	hunter.free()
	prey.free()

func test_a_slow_ai_repositions() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 900.0, 0.0))  # well above the altitude floor
	hunter.model.speed = Config.REPOSITION_SPEED * 0.5
	var prey := _craft_at(Vector3(40.0, 900.0, -1500.0))
	pilot.target = prey
	pilot.command(hunter, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.REPOSITION, "an AI that has bled its speed repositions")
	hunter.free()
	prey.free()

func test_recovery_uses_full_throttle() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 900.0, 0.0))
	hunter.model.speed = Config.REPOSITION_SPEED * 0.5
	# Above AI_THROTTLE, so ordinary cruise would command the throttle DOWN:
	# only recovery can explain a command to push it up.
	hunter.model.throttle = 0.95
	var prey := _craft_at(Vector3(40.0, 900.0, -1500.0))
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(cmd.throttle_delta > 0.0, "recovering from low speed pushes the throttle to full")
	hunter.free()
	prey.free()

func test_a_slow_but_high_ai_dives_rather_than_climbs() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 900.0, 0.0))
	hunter.model.speed = Config.REPOSITION_SPEED * 0.5
	# Above the hunter, so pursuit - or a climb - would aim up. Only the
	# energy-recovery dive aims down.
	var prey := _craft_at(Vector3(40.0, 1600.0, -1000.0))
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(cmd.aim_dir.y < 0.0, "a slow aircraft trades a little height for speed instead of climbing")
	hunter.free()
	prey.free()

func test_low_takes_priority_over_slow() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _craft_at(Vector3(0.0, 50.0, 0.0))  # below the floor AND slow
	hunter.model.speed = Config.REPOSITION_SPEED * 0.5
	var prey := _craft_at(Vector3(0.0, 20.0, -2000.0))  # below, so pursuit would aim down
	pilot.target = prey
	var cmd := pilot.command(hunter, 1.0 / 60.0)
	check(cmd.aim_dir.y > 0.0, "near the ground, climbing comes before regaining speed")
	hunter.free()
	prey.free()
