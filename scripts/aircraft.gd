class_name Aircraft
extends Node3D

signal crashed

var model := FlightModel.new()
## Any object with: command(aircraft: Aircraft, dt: float) -> InputCommand.
## Phase 2's AI pilot plugs in here unchanged.
var controller: Object = null
var terrain: Terrain = null

func _physics_process(delta: float) -> void:
	if controller == null:
		return
	model.step(controller.command(self, delta), delta)
	global_position = model.position
	global_transform.basis = model.basis
	if is_below_ground():
		crashed.emit()

## Extracted from _physics_process so it can be tested without a scene tree.
func is_below_ground() -> bool:
	if terrain == null:
		return false
	var ground := terrain.height_at(model.position.x, model.position.z)
	return model.position.y < ground + Config.GROUND_CLEARANCE

func reset(start_position: Vector3) -> void:
	model = FlightModel.new()
	model.position = start_position
	global_position = start_position
	global_transform.basis = Basis.IDENTITY
