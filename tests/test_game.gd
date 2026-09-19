extends TestCase

func test_spawn_clears_the_ground_beneath_it() -> void:
	var terrain := Terrain.new()
	var point := Game.spawn_point(terrain)
	var ground := terrain.height_at(point.x, point.z)
	check(point.y >= ground + Config.START_CLEARANCE - 1e-3,
		"the spawn always has START_CLEARANCE of air beneath it")
	check(point.y >= Config.START_ALTITUDE - 1e-3,
		"the spawn is never lower than START_ALTITUDE")
	terrain.free()

func test_spawn_is_out_over_low_ground() -> void:
	var terrain := Terrain.new()
	var point := Game.spawn_point(terrain)
	check(absf(point.z) > Config.WORLD_SIZE * 0.3,
		"the spawn sits well out from the island centre")
	check(terrain.height_at(point.x, point.z) < Config.TERRAIN_MAX_HEIGHT * 0.3,
		"the spawn is over low ground, not a hillside")
	check(absf(point.z) < Config.BOUNDARY_SOFT_START,
		"the spawn is inside the world boundary, not sitting on it")
	terrain.free()
