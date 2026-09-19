class_name Aircraft
extends Node3D

signal crashed
signal died

var model := FlightModel.new()
## Any object with: command(aircraft: Aircraft, dt: float) -> InputCommand.
## Phase 2's AI pilot plugs in here unchanged.
var controller: Object = null
var terrain: Terrain = null

var max_hp := Config.PLAYER_HP
var hp := Config.PLAYER_HP
var weapon := Weapon.new()
## True on the ticks this aircraft actually produced a round.
var fired := false

func _physics_process(delta: float) -> void:
	tick(delta)

## Extracted from _physics_process so a full control-to-model cycle can be tested
## without a scene tree. Phase 1 shipped a game that was unflyable while every
## pure-function test passed; this is the shape of test that caught it.
func tick(delta: float) -> void:
	if controller == null:
		return
	var cmd: InputCommand = controller.command(self, delta)
	cmd.aim_dir = Boundary.constrain(cmd.aim_dir, model.position)
	model.step(cmd, delta)
	fired = weapon.try_fire(delta, cmd.fire)
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

func is_alive() -> bool:
	return hp > 0.0

## Guarded so a burst landing several rounds on an already-dead aircraft emits one
## death, not one per round.
func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		died.emit()

## The authoritative position for hit tests. The node's own transform is written
## only by sync_transform(), which does nothing outside a scene tree.
func combat_position() -> Vector3:
	return model.position

func muzzle() -> Vector3:
	return model.position + model.forward() * Config.MUZZLE_FORWARD

func reset(start_position: Vector3) -> void:
	hp = max_hp
	model = FlightModel.new()
	model.position = start_position
	sync_transform()
