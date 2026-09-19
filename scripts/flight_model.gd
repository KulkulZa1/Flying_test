class_name FlightModel
extends RefCounted

var position := Vector3.ZERO
var basis := Basis.IDENTITY
var speed := Config.MIN_SPEED
var throttle := Config.START_THROTTLE

## Yaw component of the last steering step, rad/s. Read by apply_bank.
var last_yaw_rate := 0.0

func forward() -> Vector3:
	return -basis.z

func apply_throttle(cmd: InputCommand, dt: float) -> void:
	throttle = clampf(throttle + cmd.throttle_delta * Config.THROTTLE_RATE * dt, 0.0, 1.0)

func apply_engine_lag(dt: float) -> void:
	var target := lerpf(Config.MIN_SPEED, Config.MAX_SPEED, throttle)
	speed += (target - speed) * (1.0 - exp(-Config.ENGINE_RESPONSE * dt))

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
		return  # exactly reversed: no unique rotation axis
	axis = axis.normalized()
	var applied := minf(angle, turn_rate() * dt)
	basis = (Basis(axis, applied) * basis).orthonormalized()
	last_yaw_rate = axis.y * applied / dt

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
	var target := clampf(-last_yaw_rate * Config.AUTO_BANK_GAIN,
		-Config.MAX_BANK, Config.MAX_BANK)
	var cap := Config.MANUAL_ROLL_RATE * dt
	var correction := clampf((target - bank_angle()) * (1.0 - exp(-Config.BANK_RESPONSE * dt)),
		-cap, cap)
	var delta := cmd.roll * Config.MANUAL_ROLL_RATE * dt + correction
	if absf(delta) < 1e-9:
		return
	basis = (Basis(forward(), delta) * basis).orthonormalized()

func apply_stall_sag(dt: float) -> void:
	if speed >= Config.STALL_SPEED:
		return
	var severity := 1.0 - speed / Config.STALL_SPEED
	var fwd := forward()
	var level_right := fwd.cross(Vector3.UP)
	if level_right.length_squared() < 1e-6:
		return
	level_right = level_right.normalized()
	# Negative rotation about the level-right axis pitches the nose down.
	basis = (Basis(level_right, -Config.SAG_RATE * severity * dt) * basis).orthonormalized()

func step(cmd: InputCommand, dt: float) -> void:
	apply_throttle(cmd, dt)
	apply_engine_lag(dt)
	apply_gravity(dt)
	apply_steering(cmd, dt)
	apply_bank(cmd, dt)
	apply_stall_sag(dt)
	position += forward() * speed * dt
