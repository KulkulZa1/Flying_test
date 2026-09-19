class_name Bullets
extends Node3D

var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _ages: Array[float] = []
var _owners: Array = []

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
			hits.append(struck)
		if struck != null or _ages[index] >= Config.BULLET_LIFETIME:
			_remove(index)
		index -= 1
	return hits

func _remove(index: int) -> void:
	_positions.remove_at(index)
	_velocities.remove_at(index)
	_ages.remove_at(index)
	_owners.remove_at(index)
