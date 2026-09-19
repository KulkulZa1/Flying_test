class_name WaveDirector
extends RefCounted

static func wave_size(wave: int) -> int:
	return mini(1 + int(floor(float(wave) / 2.0)), Config.MAX_WAVE_SIZE)

static func jitter_for(wave: int) -> float:
	var t := clampf(float(wave - 1) / float(maxi(Config.JITTER_RAMP_WAVES - 1, 1)), 0.0, 1.0)
	return lerpf(Config.AIM_JITTER_START_DEG, Config.AIM_JITTER_END_DEG, t)

## Ringed around the player. When part of the ring would fall outside the world,
## the angle is rotated rather than the radius shortened: shortening dropped
## enemies 100 m from a player near the boundary, inside MIN_SEPARATION.
static func spawn_point(around: Vector3, index: int, total: int) -> Vector3:
	var player_flat := Vector2(around.x, around.z)
	var base := TAU * float(index) / float(maxi(total, 1))
	var limit := Config.WORLD_SIZE * 0.5 - 200.0
	for attempt in 12:
		var angle := base + float(attempt) * (TAU / 12.0)
		var candidate := player_flat + Vector2(cos(angle), sin(angle)) * Config.SPAWN_RADIUS
		if candidate.length() <= limit:
			return Vector3(candidate.x, Config.SPAWN_ALTITUDE, candidate.y)
	# Every direction leaves the world: fall back to clamping the radius.
	var clamped := (player_flat + Vector2(cos(base), sin(base)) * Config.SPAWN_RADIUS)
	clamped = clamped.normalized() * limit
	return Vector3(clamped.x, Config.SPAWN_ALTITUDE, clamped.y)
