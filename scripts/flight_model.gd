class_name FlightModel
extends RefCounted

var position := Vector3.ZERO
var basis := Basis.IDENTITY
var speed := lerpf(Config.MIN_SPEED, Config.MAX_SPEED, Config.START_THROTTLE)
var throttle := Config.START_THROTTLE

## Yaw component of the last steering step, rad/s. Read by apply_bank.
var last_yaw_rate := 0.0

func forward() -> Vector3:
	return -basis.z

func apply_throttle(cmd: InputCommand, dt: float) -> void:
	if not is_finite(cmd.throttle_delta):
		return
	throttle = clampf(throttle + cmd.throttle_delta * Config.THROTTLE_RATE * dt, 0.0, 1.0)

func apply_engine_lag(dt: float) -> void:
	var target := lerpf(Config.MIN_SPEED, Config.MAX_SPEED, throttle)
	speed += (target - speed) * (1.0 - exp(-Config.ENGINE_RESPONSE * dt))

## Pitch-to-energy coupling, not a force: it changes speed only. The plane always flies exactly along its nose.
func apply_gravity(dt: float) -> void:
	speed = maxf(speed - Config.GRAVITY * forward().y * dt, 0.0)

func turn_rate() -> float:
	var ratio := speed / Config.BEST_TURN_SPEED
	var scale: float
	if ratio <= 1.0:
		scale = clampf(ratio, Config.MIN_TURN_SCALE, 1.0)
	else:
		scale = clampf(1.0 / ratio, Config.HIGH_SPEED_TURN_FLOOR, 1.0)
	return Config.MAX_TURN_RATE * scale

func apply_steering(cmd: InputCommand, dt: float) -> void:
	last_yaw_rate = 0.0
	var aim := cmd.aim_dir
	if not aim.is_finite() or aim.length_squared() < 1e-8:
		return
	aim = aim.normalized()
	var fwd := forward()
	var angle := fwd.angle_to(aim)
	if angle < 1e-5:
		return
	var axis := fwd.cross(aim)
	if axis.length_squared() < 1e-12:
		# Exactly reversed: there is no unique rotation axis, but any perpendicular
		# one turns us around. Returning here instead let an aircraft fly straight
		# out of the world forever, because the world boundary hands back an aim
		# that is exactly antiparallel to a radial heading.
		axis = fwd.cross(Vector3.UP)
		if axis.length_squared() < 1e-12:
			axis = Vector3.RIGHT  # nose is vertical too; any horizontal axis will do
	axis = axis.normalized()
	var applied := minf(angle, turn_rate() * dt)
	basis = (Basis(axis, applied) * basis).orthonormalized()
	## World-vertical component of this step's rotation: negative for a right turn.
	last_yaw_rate = axis.y * applied / dt

## Positive is a right bank. Zero when wings are level with the horizon.
func bank_angle() -> float:
	var fwd := forward()
	var level_right := fwd.cross(Vector3.UP)
	if level_right.length_squared() < 1e-6:
		return 0.0  # pointing straight up or down: bank is undefined
	level_right = level_right.normalized()
	var level_up := level_right.cross(fwd).normalized()
	var up := basis.y
	return atan2(up.dot(level_right), up.dot(level_up))

func apply_bank(cmd: InputCommand, dt: float) -> void:
	## Negated because a right turn yields a negative yaw rate and a positive rotation about forward banks right.
	var target := clampf(-last_yaw_rate * Config.AUTO_BANK_GAIN,
		-Config.MAX_BANK, Config.MAX_BANK)
	# Manual roll folds into the target rather than being added separately: the
	# ODE bank' = roll*MANUAL_ROLL_RATE + BANK_RESPONSE*(target - bank) is an
	# exponential approach to target + roll*MANUAL_ROLL_RATE/BANK_RESPONSE, so
	# discretising it this way is exact at any timestep.
	var effective := target + cmd.roll * Config.MANUAL_ROLL_RATE / Config.BANK_RESPONSE
	# The servo levels the wings, which is only meaningful while the aircraft is
	# nearer upright than inverted. Through the top of a loop it is legitimately
	# inverted and bank_angle() reads near 180 degrees; acting on that rolls hard
	# to undo an attitude the player asked for, which turned every loop into a
	# stable knife-edge. Keying the gate on bank rather than on pitch means the
	# gate and the error it guards are the same measurement, so they cannot drift
	# onto different timescales.
	var authority := clampf(
		(Config.BANK_SERVO_LIMIT - absf(bank_angle())) / Config.BANK_SERVO_FADE, 0.0, 1.0)
	var cap := Config.MANUAL_ROLL_RATE * dt
	var delta := clampf((effective - bank_angle()) * (1.0 - exp(-Config.BANK_RESPONSE * dt)),
		-cap, cap) * authority
	if not is_finite(delta) or absf(delta) < 1e-9:
		return
	basis = (Basis(forward(), delta) * basis).orthonormalized()

func apply_stall_sag(dt: float) -> void:
	if speed >= Config.STALL_SPEED:
		return
	var severity := 1.0 - speed / Config.STALL_SPEED
	var fwd := forward()
	var level_right := fwd.cross(Vector3.UP)
	if level_right.length_squared() < 1e-6:
		level_right = basis.x
	level_right = level_right.normalized()
	# Negative rotation about the level-right axis pitches the nose down.
	basis = (Basis(level_right, -Config.SAG_RATE * severity * dt) * basis).orthonormalized()

func step(cmd: InputCommand, dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	apply_throttle(cmd, dt)
	apply_engine_lag(dt)
	apply_gravity(dt)
	apply_steering(cmd, dt)
	apply_bank(cmd, dt)
	apply_stall_sag(dt)
	position += forward() * speed * dt
