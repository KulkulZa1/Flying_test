extends TestCase

func test_holding_fire_produces_the_configured_rate() -> void:
	var weapon := Weapon.new()
	var rounds := 0
	for i in 600:  # ten seconds
		if weapon.try_fire(1.0 / 60.0, true):
			rounds += 1
	check_approx(float(rounds), Config.FIRE_RATE * 10.0, 2.0,
		"ten seconds of held fire produces about FIRE_RATE * 10 rounds")

func test_not_holding_fire_produces_nothing() -> void:
	var weapon := Weapon.new()
	var rounds := 0
	for i in 600:
		if weapon.try_fire(1.0 / 60.0, false):
			rounds += 1
	check(rounds == 0, "a weapon that is not asked to fire produces nothing")

func test_rate_does_not_depend_on_timestep() -> void:
	var fast := Weapon.new()
	var slow := Weapon.new()
	var fast_rounds := 0
	var slow_rounds := 0
	for i in 1200:
		if fast.try_fire(1.0 / 120.0, true):
			fast_rounds += 1
	for i in 400:
		if slow.try_fire(1.0 / 40.0, true):
			slow_rounds += 1
	check(absf(fast_rounds - slow_rounds) <= 2,
		"ten seconds of fire gives the same round count at 120 Hz and 40 Hz")

func test_tapping_fire_cannot_beat_the_rate_limit() -> void:
	var weapon := Weapon.new()
	var rounds := 0
	for i in 600:
		# Alternating the trigger every tick must not out-shoot holding it.
		if weapon.try_fire(1.0 / 60.0, i % 2 == 0):
			rounds += 1
	check(rounds <= int(Config.FIRE_RATE * 10.0) + 2,
		"tapping the trigger cannot exceed the configured rate")

func test_a_pause_does_not_bank_a_burst() -> void:
	var weapon := Weapon.new()
	for i in 120:  # two seconds with the trigger blocked
		weapon.try_fire(1.0 / 60.0, false)
	var rounds := 0
	for i in 60:  # then one second of held fire
		if weapon.try_fire(1.0 / 60.0, true):
			rounds += 1
	check(rounds <= int(Config.FIRE_RATE) + 2,
		"an idle period must not bank rounds into the next burst")
