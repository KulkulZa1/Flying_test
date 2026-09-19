class_name Boundary
extends RefCounted

## Rotates aim toward the world centre once past the soft boundary, in proportion
## to how far out you are. Deliberately a rotation and not a lerp: lerping between
## opposed directions collapses to the zero vector at the midpoint, which turns a
## gradual bend into a 180 degree snap.
static func constrain(aim: Vector3, position: Vector3) -> Vector3:
	var distance := Vector2(position.x, position.z).length()
	if distance <= Config.BOUNDARY_SOFT_START:
		return aim
	var span := maxf(Config.WORLD_SIZE * 0.5 - Config.BOUNDARY_SOFT_START, 1.0)
	var strength := clampf(
		(distance - Config.BOUNDARY_SOFT_START) / span * Config.BOUNDARY_STRENGTH, 0.0, 1.0)
	var inward := Vector3(-position.x, 0.0, -position.z)
	if inward.length_squared() < 1e-6:
		return aim
	inward = inward.normalized()
	var unit := aim.normalized()
	if not unit.is_finite():
		return inward
	var angle := unit.angle_to(inward)
	if angle < 1e-5:
		return aim
	var axis := unit.cross(inward)
	if axis.length_squared() < 1e-12:
		axis = Vector3.UP  # aimed exactly outward: no unique axis, so turn about world up
	else:
		axis = axis.normalized()
	return unit.rotated(axis, angle * strength)
