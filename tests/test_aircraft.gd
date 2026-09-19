extends TestCase

## Aircraft and Terrain extend Node3D and are not reference-counted, so every
## test frees what it creates.

func test_aircraft_detects_ground() -> void:
	var terrain := Terrain.new()
	var aircraft := Aircraft.new()
	aircraft.terrain = terrain
	# height_at(0, 0) is 450 m for this seed.
	aircraft.model.position = Vector3(0.0, 1000.0, 0.0)
	check(not aircraft.is_below_ground(), "well above the island is clear")
	aircraft.model.position = Vector3(0.0, 10.0, 0.0)
	check(aircraft.is_below_ground(), "below the terrain at the origin is a crash")
	aircraft.free()
	terrain.free()

func test_ground_clearance_is_respected() -> void:
	var terrain := Terrain.new()
	var aircraft := Aircraft.new()
	aircraft.terrain = terrain
	var ground := terrain.height_at(0.0, 0.0)
	aircraft.model.position = Vector3(0.0, ground + Config.GROUND_CLEARANCE + 1.0, 0.0)
	check(not aircraft.is_below_ground(), "just above the clearance margin is still flying")
	aircraft.model.position = Vector3(0.0, ground + Config.GROUND_CLEARANCE - 1.0, 0.0)
	check(aircraft.is_below_ground(), "inside the clearance margin counts as a crash")
	aircraft.free()
	terrain.free()

func test_aircraft_without_terrain_never_crashes() -> void:
	var aircraft := Aircraft.new()
	aircraft.model.position = Vector3(0.0, -5000.0, 0.0)
	check(not aircraft.is_below_ground(), "no terrain assigned means no ground to hit")
	aircraft.free()

func test_reset_restores_a_clean_model() -> void:
	var aircraft := Aircraft.new()
	aircraft.model.speed = 5.0
	aircraft.model.basis = Basis(Vector3.RIGHT, 1.0)
	aircraft.reset(Vector3(10.0, 900.0, -20.0))
	check(aircraft.model.position.is_equal_approx(Vector3(10.0, 900.0, -20.0)),
		"reset places the model at the requested point")
	check(aircraft.model.basis.is_equal_approx(Basis.IDENTITY), "reset levels the aircraft")
	check(aircraft.model.speed > Config.STALL_SPEED, "reset does not respawn in a stall")
	aircraft.free()
