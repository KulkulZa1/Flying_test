class_name WaveDirector
extends RefCounted

static func wave_size(wave: int) -> int:
	return mini(1 + int(floor(float(wave) / 2.0)), Config.MAX_WAVE_SIZE)

static func jitter_for(wave: int) -> float:
	var t := clampf(float(wave - 1) / float(maxi(Config.JITTER_RAMP_WAVES - 1, 1)), 0.0, 1.0)
	return lerpf(Config.AIM_JITTER_START_DEG, Config.AIM_JITTER_END_DEG, t)

## Ringed around the player, and pulled back toward the world centre if that ring
## would place a fighter outside the map.
static func spawn_point(around: Vector3, index: int, total: int) -> Vector3:
	var angle := TAU * float(index) / float(maxi(total, 1))
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * Config.SPAWN_RADIUS
	var point := Vector3(around.x, Config.SPAWN_ALTITUDE, around.z) + offset
	var flat := Vector2(point.x, point.z)
	var limit := Config.WORLD_SIZE * 0.5 - 200.0
	if flat.length() > limit:
		flat = flat.normalized() * limit
		point = Vector3(flat.x, Config.SPAWN_ALTITUDE, flat.y)
	return point
