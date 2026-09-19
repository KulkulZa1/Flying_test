class_name PlayerController
extends Node

## Pointer offset is -1..1 from screen centre. Both rotations are negated:
## a rightward pointer must turn right, which is a negative rotation about up;
## and screen Y grows downward, so a low pointer must pitch the nose down,
## which is a negative rotation about the aircraft's right axis.
static func aim_from_offset(basis: Basis, offset: Vector2) -> Vector3:
	var cone := deg_to_rad(Config.AIM_CONE_DEG)
	var clamped := offset.limit_length(1.0)
	var aim := -basis.z
	aim = aim.rotated(basis.y, -clamped.x * cone)
	aim = aim.rotated(basis.x, -clamped.y * cone)
	return aim

func command(aircraft: Aircraft, _dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.aim_dir = aim_from_offset(aircraft.model.basis, _pointer_offset(aircraft))
	var throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	cmd.throttle_delta = throttle
	var roll := 0.0
	if Input.is_key_pressed(KEY_D):
		roll += 1.0
	if Input.is_key_pressed(KEY_A):
		roll -= 1.0
	cmd.roll = roll
	cmd.fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	return cmd

func _pointer_offset(aircraft: Aircraft) -> Vector2:
	var viewport := aircraft.get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var size := viewport.get_visible_rect().size
	if size.y < 1.0:
		return Vector2.ZERO
	return ((viewport.get_mouse_position() - size * 0.5) / (size.y * 0.5)).limit_length(1.0)
