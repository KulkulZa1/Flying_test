extends TestCase

## A controller that always aims straight out along +X, ignoring the world.
class OutwardController extends RefCounted:
	func command(_aircraft, _dt) -> InputCommand:
		var cmd := InputCommand.new()
		cmd.aim_dir = Vector3(1.0, 0.0, 0.0)
		return cmd

func test_every_controller_is_held_inside_the_world() -> void:
	var aircraft := Aircraft.new()
	aircraft.controller = OutwardController.new()
	aircraft.model.position = Vector3(Config.BOUNDARY_SOFT_START + 200.0, 600.0, 0.0)
	aircraft.model.basis = Basis(Vector3.UP, -PI * 0.5)  # nose already pointing +X
	var furthest := 0.0
	for i in 3600:  # one minute
		aircraft.tick(1.0 / 60.0)
		furthest = maxf(furthest, Vector2(aircraft.model.position.x, aircraft.model.position.z).length())
	check(furthest < Config.WORLD_SIZE * 0.5,
		"a controller that never looks at the world is still held inside it")
	aircraft.free()
