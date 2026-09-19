class_name ChaseCamera
extends Camera3D

var target: Aircraft = null

## basis.z is the aircraft's backward axis, so adding it places the camera behind.
static func desired_position(t: Transform3D) -> Vector3:
	return t.origin + t.basis.z * Config.CAM_DIST + t.basis.y * Config.CAM_HEIGHT

static func fov_for_speed(speed: float) -> float:
	var t := clampf((speed - Config.MIN_SPEED) / (Config.MAX_SPEED - Config.MIN_SPEED), 0.0, 1.0)
	return lerpf(Config.CAM_FOV_MIN, Config.CAM_FOV_MAX, t)

func _process(delta: float) -> void:
	if target == null:
		return
	var t := target.global_transform
	# Same exponential form as the flight model, so the camera does not judder
	# at a different framerate.
	global_position = global_position.lerp(desired_position(t), 1.0 - exp(-delta / Config.CAM_LAG))
	look_at(t.origin - t.basis.z * Config.CAM_LOOK_AHEAD, t.basis.y)
	fov = fov_for_speed(target.model.speed)

## Used on respawn so the camera does not sail across the map to catch up.
func snap_to_target() -> void:
	if target == null:
		return
	var t := target.global_transform
	global_position = desired_position(t)
	look_at(t.origin - t.basis.z * Config.CAM_LOOK_AHEAD, t.basis.y)
