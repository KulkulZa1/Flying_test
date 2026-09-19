class_name Bullets
extends Node3D

var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _ages: Array[float] = []
var _owners: Array = []

## Comfortably above the steady-state round count: five shooters at FIRE_RATE
## over BULLET_LIFETIME is about 150.
const MAX_VISIBLE := 256

var _streaks: MultiMeshInstance3D = null

func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 9.0)  # a streak drawn along its own travel
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.86, 0.38)
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_VISIBLE
	multimesh.visible_instance_count = 0
	_streaks = MultiMeshInstance3D.new()
	_streaks.multimesh = multimesh
	# Rounds are tracked in world space, so the streaks must not inherit this
	# node's transform.
	_streaks.top_level = true
	add_child(_streaks)

## Orientation for a streak travelling in the given direction, with its long
## axis (-Z) along the travel. Exposed so it can be tested; the up reference is
## swapped near vertical, where the usual one degenerates.
static func streak_basis(direction: Vector3) -> Basis:
	if not direction.is_finite() or direction.length_squared() < 1e-8:
		return Basis.IDENTITY
	var forward := direction.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(forward, up)

## Null outside a scene tree, which is how every unit test runs.
func _refresh_streaks() -> void:
	if _streaks == null:
		return
	var multimesh := _streaks.multimesh
	var shown := mini(_positions.size(), MAX_VISIBLE)
	multimesh.visible_instance_count = shown
	for i in shown:
		multimesh.set_instance_transform(i,
			Transform3D(streak_basis(_velocities[i]), _positions[i]))

func count() -> int:
	return _positions.size()

func position_of(index: int) -> Vector3:
	return _positions[index]

func spawn(at: Vector3, direction: Vector3, shooter) -> void:
	if not direction.is_finite() or direction.length_squared() < 1e-8:
		return
	_positions.append(at)
	_velocities.append(direction.normalized() * Config.BULLET_SPEED)
	_ages.append(0.0)
	_owners.append(shooter)

## Advances every live round and returns the targets hit this tick. Each round is
## swept from its old position to its new one, so a round that crosses a target
## entirely within one tick still registers. Iterates backwards so removals do
## not disturb indices still to be visited.
## Each hit reports both the target and the craft that fired, so the caller can
## tell a kill from a collision between two enemies.
func step(dt: float, targets: Array) -> Array:
	var hits := []
	var index := _positions.size() - 1
	while index >= 0:
		var from: Vector3 = _positions[index]
		var to: Vector3 = from + _velocities[index] * dt
		_positions[index] = to
		_ages[index] += dt
		var struck = null
		for target in targets:
			if target == _owners[index]:
				continue
			if Ballistics.segment_hits_sphere(from, to, target.combat_position(), Config.HIT_RADIUS):
				struck = target
				break
		if struck != null:
			hits.append({"target": struck, "shooter": _owners[index], "at": to})
		if struck != null or _ages[index] >= Config.BULLET_LIFETIME:
			_remove(index)
		index -= 1
	_refresh_streaks()
	return hits

func _remove(index: int) -> void:
	_positions.remove_at(index)
	_velocities.remove_at(index)
	_ages.remove_at(index)
	_owners.remove_at(index)
