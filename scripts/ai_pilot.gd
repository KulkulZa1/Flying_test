class_name AIPilot
extends RefCounted

enum State { PURSUE, ATTACK, BREAK, REPOSITION }

var target: Aircraft = null
var state := State.PURSUE
var state_timer := 0.0
var jitter_degrees := Config.AIM_JITTER_START_DEG

var _jitter_phase := randf() * TAU
var _jitter_rate := randf_range(0.7, 1.3)
var _target_was_ahead := false

## Aim is a direction to a point in the world. There is deliberately no body
## frame here: expressing aim relative to the aircraft's own basis is exactly
## what made the player's controls dive in Phase 1.
##
## The pilot decides WHETHER to shoot; the aircraft's own Weapon decides WHEN a
## round actually leaves the barrel, so the AI cannot out-shoot the player.
func command(aircraft: Aircraft, dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	if target == null or not is_instance_valid(target) or not target.is_alive():
		cmd.throttle_delta = _cruise_throttle(aircraft)
		cmd.aim_dir = aircraft.model.forward()
		return cmd
	var to_target := target.model.position - aircraft.model.position
	_update_state(aircraft, to_target, dt)
	# Recovery is the one state that wants every bit of thrust: that is how a
	# slow aircraft gets its energy back.
	cmd.throttle_delta = 1.0 if state == State.REPOSITION else _cruise_throttle(aircraft)
	match state:
		State.REPOSITION:
			cmd.aim_dir = _recover(aircraft)
		State.BREAK:
			cmd.aim_dir = _break_away(aircraft, to_target)
		_:
			cmd.aim_dir = _aim_at_lead(aircraft, dt)
			cmd.fire = state == State.ATTACK
	return cmd

func _cruise_throttle(aircraft: Aircraft) -> float:
	return 1.0 if aircraft.model.throttle < Config.AI_THROTTLE else -1.0

func _update_state(aircraft: Aircraft, to_target: Vector3, dt: float) -> void:
	state_timer = maxf(state_timer - dt, 0.0)
	# Refreshed every tick whatever the state, so the pass detector never acts on
	# a stale observation when a break or a recovery ends.
	var passed := _just_passed(aircraft, to_target)
	if _needs_recovery(aircraft):
		state = State.REPOSITION
		return
	if state == State.BREAK:
		if state_timer > 0.0:
			return
		state = State.PURSUE
	var distance := to_target.length()
	if distance < Config.MIN_SEPARATION or passed:
		state = State.BREAK
		state_timer = Config.BREAK_TIME
		return
	if distance <= Config.ATTACK_RANGE and _is_lined_up(aircraft):
		state = State.ATTACK
	else:
		state = State.PURSUE

## Spec 12: break off "on overshoot or inside MIN_SEPARATION". An overshoot is
## the moment the target slides from ahead to behind while still close.
## Edge-triggered deliberately: a level test ("the target is behind") fires again
## the instant a break ends, since breaking away is exactly what puts the target
## behind, so one overshoot is counted as several. It does not loop forever - the
## break carries the AI out past ATTACK_RANGE, where the check stops firing - but
## measured, it raised the share of a fight spent breaking from 34% to 42%.
## Starts false so that a target first seen behind does not count as a pass.
func _just_passed(aircraft: Aircraft, to_target: Vector3) -> bool:
	var ahead := aircraft.model.forward().dot(to_target) > 0.0
	var passed := _target_was_ahead and not ahead and to_target.length() <= Config.ATTACK_RANGE
	_target_was_ahead = ahead
	return passed

## Spec 12: reposition regains altitude AND speed.
func _needs_recovery(aircraft: Aircraft) -> bool:
	return (aircraft.model.position.y < Config.REPOSITION_ALTITUDE
		or aircraft.model.speed < Config.REPOSITION_SPEED)

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

## Low takes priority over slow: the ground is the nearer threat, and at full
## throttle the engine recovers speed quickly even in a climb. Slow but high
## trades a little height for speed with a shallow dive instead of climbing,
## which would bleed the very energy it is trying to recover.
func _recover(aircraft: Aircraft) -> Vector3:
	var forward := aircraft.model.forward()
	var level := Vector3(forward.x, 0.0, forward.z)
	if level.length_squared() < 1e-6:
		level = Vector3.FORWARD
	level = level.normalized()
	if aircraft.model.position.y < Config.REPOSITION_ALTITUDE:
		return (level + Vector3.UP * 0.8).normalized()
	return (level + Vector3.DOWN * 0.15).normalized()
