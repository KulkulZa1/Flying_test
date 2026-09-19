class_name PlayerController
extends Node

var touch: TouchControls = null

## Yaw about WORLD up, pitch about the aircraft's OWN right axis.
##
## Yaw must be world-referenced: rotating about basis.y couples aim to bank, so
## once the servo rolls the aircraft 75 degrees a held turn becomes a dive.
##
## Pitch must be body-referenced: forward.cross(UP) flips sign the instant the
## nose crosses vertical, which reverses the pitch command at the top of a loop
## and pins the nose there. basis.x is continuous all the way round.
static func aim_from_offset(basis: Basis, offset: Vector2) -> Vector3:
	var cone := deg_to_rad(Config.AIM_CONE_DEG)
	var clamped := apply_deadzone(offset)
	var aim := (-basis.z).rotated(Vector3.UP, -clamped.x * cone)
	return aim.rotated(basis.x, -clamped.y * cone)

## Spec section 9 specifies a screen-centre deadzone; it was never implemented.
## Without it a single pixel of cursor offset commands 6.5 degrees per second, so
## the aircraft can never be flown straight.
static func apply_deadzone(raw: Vector2) -> Vector2:
	var length := raw.length()
	if length <= Config.AIM_DEADZONE:
		return Vector2.ZERO
	var ramped := (length - Config.AIM_DEADZONE) / (1.0 - Config.AIM_DEADZONE)
	return raw.normalized() * minf(ramped, 1.0)

func command(aircraft: Aircraft, _dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	if touch != null:
		cmd.aim_dir = aim_from_offset(aircraft.model.basis, touch.aim)
		cmd.throttle_delta = touch.throttle_delta
		cmd.roll = touch.aim.x * 0.5   # the stick banks as it steers
		cmd.fire = touch.fire
		return cmd
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
	return (viewport.get_mouse_position() - size * 0.5) / (size.y * 0.5)
