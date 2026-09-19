extends TestCase

func test_wave_size_grows_and_caps() -> void:
	check(WaveDirector.wave_size(1) == 1, "the first wave is a single fighter")
	check(WaveDirector.wave_size(3) == 2, "waves grow every second wave")
	check(WaveDirector.wave_size(100) == Config.MAX_WAVE_SIZE, "and cap at MAX_WAVE_SIZE")

func test_wave_size_never_shrinks() -> void:
	var failure := ""
	var previous := 0
	for wave in range(1, 40):
		var size := WaveDirector.wave_size(wave)
		if size < previous:
			failure = "wave %d shrank from %d to %d" % [wave, previous, size]
		previous = size
	check(failure == "", "wave size is monotonic: " + failure)

func test_jitter_tightens_with_waves() -> void:
	check_approx(WaveDirector.jitter_for(1), Config.AIM_JITTER_START_DEG, 1e-4,
		"the first wave shoots at the loosest jitter")
	check_approx(WaveDirector.jitter_for(Config.JITTER_RAMP_WAVES), Config.AIM_JITTER_END_DEG, 1e-4,
		"the ramp ends at AIM_JITTER_END_DEG")
	check_approx(WaveDirector.jitter_for(50), Config.AIM_JITTER_END_DEG, 1e-4,
		"and stays there afterwards")
	check(WaveDirector.jitter_for(3) < WaveDirector.jitter_for(2),
		"jitter tightens monotonically")

func test_spawn_points_ring_the_player_at_altitude() -> void:
	# Deliberately off-origin and asymmetric: a player at (0,0) would let a sign
	# error in the ring maths pass unnoticed.
	var centre := Vector3(137.0, 615.0, -284.0)
	var radius_failure := ""
	var altitude_failure := ""
	for i in 6:
		var point := WaveDirector.spawn_point(centre, i, 6)
		var flat := Vector2(point.x - centre.x, point.z - centre.z).length()
		if absf(flat - Config.SPAWN_RADIUS) > 1.0:
			radius_failure = "spawn %d at %.1f m from the player" % [i, flat]
		if absf(point.y - Config.SPAWN_ALTITUDE) > 1e-4:
			altitude_failure = "spawn %d at %.1f m altitude" % [i, point.y]
	check(radius_failure == "", "every spawn rings the player: " + radius_failure)
	check(altitude_failure == "", "every spawn is at altitude: " + altitude_failure)

func test_spawn_points_are_spread_out() -> void:
	var first := WaveDirector.spawn_point(Vector3.ZERO, 0, 4)
	var second := WaveDirector.spawn_point(Vector3.ZERO, 1, 4)
	check(first.distance_to(second) > Config.SPAWN_RADIUS * 0.5,
		"consecutive spawns are not stacked on top of each other")

func test_spawn_points_stay_inside_the_world() -> void:
	var edge := Vector3(Config.BOUNDARY_SOFT_START, 600.0, 0.0)
	var failure := ""
	for i in 6:
		var point := WaveDirector.spawn_point(edge, i, 6)
		var from_centre := Vector2(point.x, point.z).length()
		if from_centre >= Config.WORLD_SIZE * 0.5:
			failure = "spawn %d landed %.1f m from the world centre" % [i, from_centre]
	check(failure == "", "spawns near the boundary stay inside the world: " + failure)

func test_a_single_enemy_still_gets_a_valid_spawn() -> void:
	var point := WaveDirector.spawn_point(Vector3(0.0, 600.0, 0.0), 0, 1)
	check(point.is_finite(), "a one-enemy wave produces a finite spawn point")
	check_approx(Vector2(point.x, point.z).length(), Config.SPAWN_RADIUS, 1.0,
		"and still rings the player")

func test_no_spawn_lands_in_the_players_lap() -> void:
	var failure := ""
	for distance in [0.0, 1200.0, 2400.0, 3200.0, 3600.0, 3800.0]:
		var centre := Vector3(distance, 600.0, 0.0)
		for i in 6:
			var point := WaveDirector.spawn_point(centre, i, 6)
			var gap := Vector2(point.x - centre.x, point.z - centre.z).length()
			if gap < Config.MIN_SEPARATION * 2.0:
				failure = "at %.0f m out, spawn %d landed %.0f m away" % [distance, i, gap]
	check(failure == "", "no spawn lands on top of the player: " + failure)
