extends TestCase

## Terrain extends Node3D, which is not reference-counted. Every test frees its
## instances, otherwise Godot prints "ObjectDB instances leaked at exit" and a
## passing run looks broken.

func test_height_is_within_bounds_everywhere() -> void:
	var terrain := Terrain.new()
	var half := Config.WORLD_SIZE * 0.5
	var failure := ""
	for i in 20:
		for j in 20:
			var x := -half + (i + 0.5) * Config.WORLD_SIZE / 20.0
			var z := -half + (j + 0.5) * Config.WORLD_SIZE / 20.0
			var h := terrain.height_at(x, z)
			if h < 0.0 or h > Config.TERRAIN_MAX_HEIGHT:
				failure = "height %.2f at (%.0f, %.0f)" % [h, x, z]
	check(failure == "", "every sampled height is inside [0, TERRAIN_MAX_HEIGHT]: " + failure)
	terrain.free()

func test_terrain_has_relief() -> void:
	var terrain := Terrain.new()
	var half := Config.WORLD_SIZE * 0.5
	var highest := 0.0
	for i in 40:
		for j in 40:
			var x := -half + (i + 0.5) * Config.WORLD_SIZE / 40.0
			var z := -half + (j + 0.5) * Config.WORLD_SIZE / 40.0
			highest = maxf(highest, terrain.height_at(x, z))
	check(highest > Config.TERRAIN_MAX_HEIGHT * 0.25,
		"the island must have real mountains, or the bounds test proves nothing")
	terrain.free()

func test_world_edge_is_at_sea_level() -> void:
	var terrain := Terrain.new()
	var half := Config.WORLD_SIZE * 0.5
	check_approx(terrain.height_at(half, 0.0), 0.0, 1e-6, "the east edge is sea")
	check_approx(terrain.height_at(0.0, -half), 0.0, 1e-6, "the north edge is sea")
	terrain.free()

func test_height_is_deterministic_for_a_seed() -> void:
	var a := Terrain.new()
	var b := Terrain.new()
	check_approx(a.height_at(120.0, -340.0), b.height_at(120.0, -340.0), 1e-6,
		"the same seed gives the same terrain")
	a.free()
	b.free()

func test_land_mesh_is_built() -> void:
	var terrain := Terrain.new()
	var instance := terrain.build_land()
	var mesh: ArrayMesh = instance.mesh
	check(mesh != null and mesh.get_surface_count() == 1, "the land mesh has exactly one surface")
	var cells := int(Config.WORLD_SIZE / Config.TERRAIN_RES)
	check(mesh.surface_get_array_len(0) == cells * cells * 6,
		"the land mesh has two triangles per grid cell")
	instance.free()
	terrain.free()

func test_drawn_surface_matches_the_collision_field() -> void:
	var terrain := Terrain.new()
	var half := Config.WORLD_SIZE * 0.5
	var step := Config.TERRAIN_RES
	var worst := 0.0
	for i in 60:
		for j in 60:
			var x := -half + (i + 0.5) * step
			var z := -half + (j + 0.5) * step
			# What the mesh draws at a cell centre is the average of its corners.
			var drawn := (terrain.height_at(x - step * 0.5, z - step * 0.5)
				+ terrain.height_at(x + step * 0.5, z - step * 0.5)
				+ terrain.height_at(x + step * 0.5, z + step * 0.5)
				+ terrain.height_at(x - step * 0.5, z + step * 0.5)) * 0.25
			worst = maxf(worst, absf(drawn - terrain.height_at(x, z)))
	check(worst < Config.GROUND_CLEARANCE * 3.0,
		"the drawn surface must not diverge from the collision field by more than the clearance margin allows")
	terrain.free()
