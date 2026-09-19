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
