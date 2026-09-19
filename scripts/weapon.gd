class_name Weapon
extends RefCounted

var _cooldown := 0.0

## Returns true on the ticks a round leaves the barrel. The cooldown carries its
## remainder forward rather than resetting to a full interval, so the rate does
## not drift with timestep and tapping cannot beat holding.
func try_fire(dt: float, wants_fire: bool) -> bool:
	# Floor at a single interval, not a whole second: a deeper floor banks
	# cooldown while the trigger is held but blocked, and dumps it as a
	# 60-rounds-per-second burst the moment firing is allowed again.
	_cooldown = maxf(_cooldown - dt, -1.0 / Config.FIRE_RATE)
	if not wants_fire or _cooldown > 0.0:
		return false
	_cooldown += 1.0 / Config.FIRE_RATE
	return true
