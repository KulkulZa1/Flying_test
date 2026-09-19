class_name Aircraft
extends Node3D

signal crashed

var model := FlightModel.new()
## Any object with: command(aircraft: Aircraft, dt: float) -> InputCommand.
## Phase 2's AI pilot plugs in here unchanged.
var controller: Object = null
var terrain: Terrain = null

func _physics_process(delta: float) -> void:
	tick(delta)

## Extracted from _physics_process so a full control-to-model cycle can be tested
## without a scene tree. Phase 1 shipped a game that was unflyable while every
## pure-function test passed; this is the shape of test that caught it.
func tick(delta: float) -> void:
	if controller == null:
		return
	var cmd: InputCommand = controller.command(self, delta)
	# Applied here rather than in a controller so every pilot inherits it. An AI
	# that forgot to call it would simply fly off the map.
	cmd.aim_dir = Boundary.constrain(cmd.aim_dir, model.position)
	model.step(cmd, delta)
	sync_transform()
	if is_below_ground():
		crashed.emit()

## The only place the node's transform is written. Guarded because reset() runs
## before the aircraft enters the tree, and global_transform hard-fails there.
func sync_transform() -> void:
	if not is_inside_tree():
		return
	global_position = model.position
	global_transform.basis = model.basis

## Extracted from _physics_process so it can be tested without a scene tree.
func is_below_ground() -> bool:
	if terrain == null:
		return false
	var ground := terrain.height_at(model.position.x, model.position.z)
	return model.position.y < ground + Config.GROUND_CLEARANCE

func reset(start_position: Vector3) -> void:
	model = FlightModel.new()
	model.position = start_position
	sync_transform()
