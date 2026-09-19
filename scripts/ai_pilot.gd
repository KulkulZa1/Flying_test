class_name AIPilot
extends RefCounted

enum State { PURSUE, ATTACK, BREAK, REPOSITION }

var target: Aircraft = null
var state := State.PURSUE
var state_timer := 0.0
var jitter_degrees := Config.AIM_JITTER_START_DEG

var _jitter_phase := randf() * TAU
var _jitter_rate := randf_range(0.7, 1.3)

## Aim is a direction to a point in the world. There is deliberately no body
## frame here: expressing aim relative to the aircraft's own basis is exactly
## what made the player's controls dive in Phase 1.
##
## The pilot decides WHETHER to shoot; the aircraft's own Weapon decides WHEN a
## round actually leaves the barrel, so the AI cannot out-shoot the player.
func command(aircraft: Aircraft, dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.throttle_delta = 1.0 if aircraft.model.throttle < Config.AI_THROTTLE else -1.0
	if target == null or not is_instance_valid(target) or not target.is_alive():
		cmd.aim_dir = aircraft.model.forward()
		return cmd
	var to_target := target.model.position - aircraft.model.position
	_update_state(aircraft, to_target.length(), dt)
	match state:
		State.REPOSITION:
			cmd.aim_dir = _climb_away(aircraft)
		State.BREAK:
			cmd.aim_dir = _break_away(aircraft, to_target)
		_:
			cmd.aim_dir = _aim_at_lead(aircraft, dt)
			cmd.fire = state == State.ATTACK
	return cmd

func _update_state(aircraft: Aircraft, distance: float, dt: float) -> void:
	state_timer = maxf(state_timer - dt, 0.0)
	if aircraft.model.position.y < Config.REPOSITION_ALTITUDE:
		state = State.REPOSITION
		return
	if state == State.BREAK:
		if state_timer > 0.0:
			return
		state = State.PURSUE
	if distance < Config.MIN_SEPARATION:
		state = State.BREAK
		state_timer = Config.BREAK_TIME
		return
	if distance <= Config.ATTACK_RANGE and _is_lined_up(aircraft):
		state = State.ATTACK
	else:
		state = State.PURSUE

func _is_lined_up(aircraft: Aircraft) -> bool:
	var to_target := target.model.position - aircraft.model.position
	if to_target.length_squared() < 1e-6:
		return false
	return aircraft.model.forward().angle_to(to_target.normalized()) <= deg_to_rad(Config.ATTACK_CONE_DEG)

func _aim_at_lead(aircraft: Aircraft, dt: float) -> Vector3:
	var target_velocity := target.model.forward() * target.model.speed
	var lead := Ballistics.lead_point(aircraft.model.position, target.model.position,
		target_velocity, Config.BULLET_SPEED)
	var aim := lead - aircraft.model.position
	if not aim.is_finite() or aim.length_squared() < 1e-6:
		return aircraft.model.forward()
	return _apply_jitter(aim.normalized(), dt)

## A slow wander rather than per-tick noise: random jitter every frame averages
## out to perfect aim over a burst, which is not what a beatable enemy looks like.
func _apply_jitter(aim: Vector3, dt: float) -> Vector3:
	if jitter_degrees <= 0.0:
		return aim
	_jitter_phase += dt
	var axis := aim.cross(Vector3.UP)
	if axis.length_squared() < 1e-6:
		axis = Vector3.RIGHT
	axis = axis.normalized().rotated(aim, _jitter_phase * 1.7)
	return aim.rotated(axis, deg_to_rad(jitter_degrees) * sin(_jitter_phase * _jitter_rate))

func _break_away(aircraft: Aircraft, to_target: Vector3) -> Vector3:
	var away := -to_target
	away.y = absf(away.y) + 0.4 * away.length()
	if away.length_squared() < 1e-6:
		return aircraft.model.forward()
	return away.normalized()

func _climb_away(aircraft: Aircraft) -> Vector3:
	var forward := aircraft.model.forward()
	var climb := Vector3(forward.x, 0.0, forward.z)
	if climb.length_squared() < 1e-6:
		climb = Vector3.FORWARD
	return (climb.normalized() + Vector3.UP * 0.8).normalized()
