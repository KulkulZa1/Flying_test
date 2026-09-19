# Phase 2: Combat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Escalating waves of AI fighters over the Phase 1 island, guns only, with score, combo and a persisted high score.

**Architecture:** `AIPilot` emits the same `InputCommand` the player does and drives the same `FlightModel`, so enemies obey identical physics. Hit detection is analytic segment-versus-sphere, not the physics engine — the same kinematic philosophy that made Phase 1 testable, and the only way bullets can be proven not to tunnel at closing speed.

**Tech Stack:** Godot 4.7.2, GDScript, the Phase 1 headless harness.

**Spec:** `docs/superpowers/specs/2026-09-19-flying-arcade-dogfighter-design.md`, sections 11–13.

**Branch:** `phase2-combat`, based on `phase1-flight` at `95d72a1`.

---

## What Phase 1 taught, and what this plan does about it

Phase 1 reached 119 green checks with a game that could not be flown. Every check was on a pure
function; the controller fed the model aim in the wrong frame and nothing noticed. Three rules
follow, and they are not optional here:

1. **Every task ships at least one test that drives the real component through the real
   `FlightModel` for a sustained period**, not just its pure helpers. `test_a_held_turn_holds_altitude`
   is the template: it is what finally caught the Phase 1 blocker.
2. **Mutate before trusting.** A task is not done until someone has broken the thing it builds and
   watched a named test fail. Several Phase 1 tests passed with the feature they were named for
   deleted.
3. **Assert properties, not arbitrary numbers.** A bound invented to look reasonable either passes
   vacuously or contradicts the implementation — both happened in Phase 1.

### The aim-frame trap does not recur here, and that is worth knowing

`PlayerController` had to build aim from a 2D screen offset, which is why it needed a frame at all
and why choosing the wrong one was catastrophic. `AIPilot` computes a **world-space direction to a
point in the world**. There is no frame to get wrong. Do not "helpfully" express AI aim relative
to the aircraft's basis.

---

## Conventions

Identical to Phase 1. Restated because they are load-bearing:

```bash
export GODOT="/c/Users/KulkulZa/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
cd /d/toy_project/Flying
bash tests/run.sh; echo "exit=$?"
```

- **Always the wrapper**, never raw `--script`: the harness cannot see engine stderr, and
  `run.sh` fails the run on any `SCRIPT ERROR`.
- `"$GODOT" --headless --path . --import` once after adding any `class_name` script, or the type
  will not resolve. Never commit `.godot/`.
- **`.uid` sidecars need the editor, not `--import`.** `tests/run.sh` and plain `--script` never
  touch `.godot/uid_cache.bin`, so a new test file gets no `.gd.uid` from them. Run
  `"$GODOT" --headless --editor --quit` once; it generates the sidecar, exits 0 and touches
  nothing else. Every task here adds a test file, so this is needed every time.
- TAB indentation. **Never `sed -i`** — it rewrites whole-file line endings on this machine.
- Nodes are not reference-counted: tests `free()` what they create.
- Godot uses **32-bit floats**; use float32 epsilon (~1.19e-7) when reasoning about residuals.
- `--quit-after N` counts main-loop iterations, not physics ticks — roughly 2.6x on this machine.
- Headless has **no pointer**; drive integration runs with a stub controller.
- Only real project files in the project directory. **No Godot process left running.**
- Files under `docs/` belong to the coordinator.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/ballistics.gd` | Pure statics: segment-sphere hit test, lead-intercept point |
| `scripts/weapon.gd` | Fire-rate cooldown. No nodes. |
| `scripts/bullets.gd` | Owns live rounds, advances them, reports hits |
| `scripts/ai_pilot.gd` | Four-state machine emitting `InputCommand` |
| `scripts/wave_director.gd` | Wave size and difficulty curve, spawn placement |
| `scripts/scoring.gd` | Kill score, combo chain, high-score persistence |
| `scripts/debris.gd` | Rigid-body wreckage, self-freeing |
| Modified: `aircraft.gd` | Gains health, damage, death; applies `Boundary` for every controller |
| Modified: `hud.gd` | Health, score, combo, off-screen enemy indicator |
| Modified: `game.gd` | Wires combat in |
| Modified: `config.gd` | Combat, AI, wave, scoring and debris tunables |

---

## Task 1: The boundary belongs to the aircraft, not the player

`Boundary.constrain` is applied inside `PlayerController.command`. Every AI pilot would have to
remember to call it or fly off the map — an obligation the seam does not encode. Move it to the
one place every controller passes through.

**Files:** modify `scripts/aircraft.gd`, `scripts/player_controller.gd`; create `tests/test_boundary_integration.gd`; modify `tests/run_tests.gd`.

- [ ] **Step 1: Write the failing test**

`tests/test_boundary_integration.gd`:
```gdscript
extends TestCase

## A controller that always aims straight out along +X, ignoring the world.
class OutwardController extends RefCounted:
	func command(_aircraft, _dt) -> InputCommand:
		var cmd := InputCommand.new()
		cmd.aim_dir = Vector3(1.0, 0.0, 0.0)
		return cmd

func test_every_controller_is_held_inside_the_world() -> void:
	var aircraft := Aircraft.new()
	aircraft.controller = OutwardController.new()
	aircraft.model.position = Vector3(Config.BOUNDARY_SOFT_START + 200.0, 600.0, 0.0)
	aircraft.model.basis = Basis(Vector3.UP, -PI * 0.5)  # nose already pointing +X
	var furthest := 0.0
	for i in 3600:  # one minute
		aircraft.tick(1.0 / 60.0)
		furthest = maxf(furthest, Vector2(aircraft.model.position.x, aircraft.model.position.z).length())
	check(furthest < Config.WORLD_SIZE * 0.5,
		"a controller that never looks at the world is still held inside it")
	aircraft.free()
```

Add `"res://tests/test_boundary_integration.gd"` to `SUITES`.

- [ ] **Step 2: Run to verify it fails** — `tick` does not exist, `exit=1`.

- [ ] **Step 3: Write the implementation**

In `scripts/aircraft.gd`, replace `_physics_process` with:
```gdscript
func _physics_process(delta: float) -> void:
	tick(delta)

## Extracted from _physics_process so a full control-to-model cycle can be tested
## without a scene tree. Phase 1 shipped a game that was unflyable while every
## pure-function test passed; this is the shape of test that caught it.
func tick(delta: float) -> void:
	if controller == null:
		return
	var cmd: InputCommand = controller.command(self, delta)
	# Applied here rather than in a controller so every pilot inherits it. An AI
	# that forgot to call it would simply fly off the map.
	cmd.aim_dir = Boundary.constrain(cmd.aim_dir, model.position)
	model.step(cmd, delta)
	sync_transform()
	if is_below_ground():
		crashed.emit()
```

In `scripts/player_controller.gd`, remove both `Boundary.constrain(...)` wrappers, leaving:
```gdscript
		cmd.aim_dir = aim_from_offset(aircraft.model.basis, touch.aim)
```
and
```gdscript
	cmd.aim_dir = aim_from_offset(aircraft.model.basis, _pointer_offset(aircraft))
```

- [ ] **Step 4: Run to verify it passes.** Expect `checks: 130  failures: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/aircraft.gd scripts/player_controller.gd tests/ && git commit -m "Apply the world boundary to every controller, not just the player"
```

---

## Task 2: Ballistics — the pure hit maths

Two functions decide whether combat is fair. Both are pure, so both get pinned hard.

**Files:** create `scripts/ballistics.gd`, `tests/test_ballistics.gd`; modify `tests/run_tests.gd`.

- [ ] **Step 1: Write the failing test**

`tests/test_ballistics.gd`:
```gdscript
extends TestCase

func test_a_segment_through_a_sphere_hits() -> void:
	check(Ballistics.segment_hits_sphere(
		Vector3(-10.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), Vector3.ZERO, 5.0),
		"a segment through the centre hits")

func test_a_segment_beside_a_sphere_misses() -> void:
	check(not Ballistics.segment_hits_sphere(
		Vector3(-10.0, 20.0, 0.0), Vector3(10.0, 20.0, 0.0), Vector3.ZERO, 5.0),
		"a segment passing well clear misses")

func test_a_segment_stopping_short_misses() -> void:
	check(not Ballistics.segment_hits_sphere(
		Vector3(-10.0, 0.0, 0.0), Vector3(-8.0, 0.0, 0.0), Vector3.ZERO, 5.0),
		"a segment that stops before the sphere misses")

func test_a_fast_round_cannot_tunnel() -> void:
	# One tick of a 600 m/s round closing on a 180 m/s target is 13 m of travel
	# against a 6 m radius. A point test at each endpoint would miss entirely.
	var a := Vector3(0.0, 0.0, -7.0)
	var b := Vector3(0.0, 0.0, 6.0)
	check(Ballistics.segment_hits_sphere(a, b, Vector3.ZERO, Config.HIT_RADIUS),
		"a round that steps straight past a target in one tick still registers")
	check(not a.distance_to(Vector3.ZERO) < Config.HIT_RADIUS,
		"and neither endpoint is inside the target, so only the sweep can catch it")

func test_lead_point_is_ahead_of_a_crossing_target() -> void:
	var lead := Ballistics.lead_point(Vector3.ZERO, Vector3(0.0, 0.0, -600.0),
		Vector3(100.0, 0.0, 0.0), Config.BULLET_SPEED)
	check(lead.x > 50.0, "the lead point sits ahead of a target crossing to the right")

func test_lead_point_on_a_stationary_target_is_the_target() -> void:
	var target := Vector3(0.0, 0.0, -400.0)
	var lead := Ballistics.lead_point(Vector3.ZERO, target, Vector3.ZERO, Config.BULLET_SPEED)
	check(lead.distance_to(target) < 1e-3, "a stationary target needs no lead")
```

Add `"res://tests/test_ballistics.gd"` to `SUITES`.

- [ ] **Step 2: Run to verify it fails** — `Ballistics` unknown, `exit=1`.

- [ ] **Step 3: Write the implementation**

`scripts/ballistics.gd`:
```gdscript
class_name Ballistics
extends RefCounted

## True when the swept segment a->b passes within radius of centre. Swept rather
## than point-sampled because a 600 m/s round covers 10 m in a single tick against
## a 6 m target: testing only the endpoints would let it pass straight through.
static func segment_hits_sphere(a: Vector3, b: Vector3, centre: Vector3, radius: float) -> bool:
	var travel := b - a
	var length_squared := travel.length_squared()
	if length_squared < 1e-9:
		return a.distance_squared_to(centre) <= radius * radius
	var t := clampf((centre - a).dot(travel) / length_squared, 0.0, 1.0)
	return (a + travel * t).distance_squared_to(centre) <= radius * radius

## Where to aim so a round of the given speed meets a target that keeps its
## current velocity. Solves the quadratic for intercept time; falls back to the
## target's present position when there is no positive solution.
static func lead_point(shooter: Vector3, target: Vector3, target_velocity: Vector3,
		speed: float) -> Vector3:
	var offset := target - shooter
	var a := target_velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(target_velocity)
	var c := offset.length_squared()
	if absf(a) < 1e-6:
		if absf(b) < 1e-6:
			return target
		var linear := -c / b
		return target + target_velocity * maxf(linear, 0.0)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return target
	var root := sqrt(discriminant)
	var t1 := (-b + root) / (2.0 * a)
	var t2 := (-b - root) / (2.0 * a)
	var t := maxf(t1, t2) if minf(t1, t2) < 0.0 else minf(t1, t2)
	if t < 0.0:
		return target
	return target + target_velocity * t
```

- [ ] **Step 4: Run to verify it passes.** Expect `checks: 137  failures: 0` (130 + 7).

- [ ] **Step 5: Commit** — `"Add swept hit detection and lead-intercept maths"`

---

## Task 3: Weapon — fire rate

**Files:** create `scripts/weapon.gd`, `tests/test_weapon.gd`; modify `scripts/config.gd`, `tests/run_tests.gd`.

- [ ] **Step 1: add constants**

In `scripts/config.gd`, at the end:
```gdscript

# --- Combat ---
const BULLET_SPEED := 600.0         # m/s
const FIRE_RATE := 12.0             # rounds per second
const BULLET_DAMAGE := 8.0
const BULLET_LIFETIME := 2.5        # s
const HIT_RADIUS := 6.0             # m, roughly the jet's span
const MUZZLE_FORWARD := 5.0         # m ahead of the model origin
const PLAYER_HP := 100.0
const ENEMY_HP := 30.0
```

- [ ] **Step 2: Write the failing test**

`tests/test_weapon.gd`:
```gdscript
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
```

Add `"res://tests/test_weapon.gd"` to `SUITES`.

- [ ] **Step 3: Run to verify it fails** — `Weapon` unknown, `exit=1`.

- [ ] **Step 4: Write the implementation**

`scripts/weapon.gd`:
```gdscript
class_name Weapon
extends RefCounted

var _cooldown := 0.0

## Returns true on the ticks a round leaves the barrel. The cooldown carries its
## remainder rather than resetting, so the rate does not drift with timestep.
func try_fire(dt: float, wants_fire: bool) -> bool:
	_cooldown = maxf(_cooldown - dt, -1.0)
	if not wants_fire or _cooldown > 0.0:
		return false
	_cooldown += 1.0 / Config.FIRE_RATE
	return true
```

- [ ] **Step 5: Run to verify it passes.** Expect `checks: 140  failures: 0` (137 + 3).

- [ ] **Step 6: Commit** — `"Add a timestep-independent weapon fire rate"`

---

## Task 4: Bullets — live rounds and hits

**Files:** create `scripts/bullets.gd`, `tests/test_bullets.gd`; modify `tests/run_tests.gd`.

- [ ] **Step 1: Write the failing test**

`tests/test_bullets.gd`:
```gdscript
extends TestCase

class Dummy extends RefCounted:
	var position := Vector3.ZERO
	var hits := 0
	func _init(at: Vector3) -> void:
		position = at

func test_a_round_travels_at_bullet_speed() -> void:
	var bullets := Bullets.new()
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	bullets.step(1.0, [])
	check_approx(bullets.position_of(0).length(), Config.BULLET_SPEED, 1.0,
		"a round covers BULLET_SPEED metres in one second")
	bullets.free()

func test_a_round_expires() -> void:
	var bullets := Bullets.new()
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	bullets.step(Config.BULLET_LIFETIME + 0.1, [])
	check(bullets.count() == 0, "a round is gone once its lifetime elapses")
	bullets.free()

func test_a_round_hits_a_target_in_its_path() -> void:
	var bullets := Bullets.new()
	var target := Dummy.new(Vector3(0.0, 0.0, -100.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	var hits := bullets.step(0.5, [target])
	check(hits.size() == 1, "a round passing through a target reports one hit")
	check(hits[0] == target, "and reports which target it hit")
	check(bullets.count() == 0, "and is consumed")
	bullets.free()

func test_a_round_cannot_hit_its_own_shooter() -> void:
	var bullets := Bullets.new()
	var shooter := Dummy.new(Vector3(0.0, 0.0, -20.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, shooter)
	var hits := bullets.step(0.5, [shooter])
	check(hits.is_empty(), "a round passes through the aircraft that fired it")
	bullets.free()

func test_a_round_cannot_tunnel_through_a_closing_target() -> void:
	var bullets := Bullets.new()
	var target := Dummy.new(Vector3(0.0, 0.0, -300.0))
	bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
	# One full second steps the round 600 m, straight past a 6 m target.
	var hits := bullets.step(1.0, [target])
	check(hits.size() == 1, "a round that overshoots within one tick still registers a hit")
	bullets.free()
```

Add `"res://tests/test_bullets.gd"` to `SUITES`.

- [ ] **Step 2: Run to verify it fails** — `Bullets` unknown, `exit=1`.

- [ ] **Step 3: Write the implementation**

`scripts/bullets.gd`:
```gdscript
class_name Bullets
extends Node3D

var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _ages: Array[float] = []
var _owners: Array = []

func count() -> int:
	return _positions.size()

func position_of(index: int) -> Vector3:
	return _positions[index]

func spawn(at: Vector3, direction: Vector3, shooter) -> void:
	if not direction.is_finite() or direction.length_squared() < 1e-8:
		return
	_positions.append(at)
	_velocities.append(direction.normalized() * Config.BULLET_SPEED)
	_ages.append(0.0)
	_owners.append(shooter)

## Advances every live round and returns the targets hit this tick. Each round is
## swept from its old position to its new one, so a round that crosses a target
## entirely within one tick still registers.
func step(dt: float, targets: Array) -> Array:
	var hits := []
	var index := _positions.size() - 1
	while index >= 0:
		var from: Vector3 = _positions[index]
		var to: Vector3 = from + _velocities[index] * dt
		_positions[index] = to
		_ages[index] += dt
		var struck = null
		for target in targets:
			if target == _owners[index]:
				continue
			if Ballistics.segment_hits_sphere(from, to, target.position, Config.HIT_RADIUS):
				struck = target
				break
		if struck != null:
			hits.append(struck)
		if struck != null or _ages[index] >= Config.BULLET_LIFETIME:
			_remove(index)
		index -= 1
	return hits

func _remove(index: int) -> void:
	_positions.remove_at(index)
	_velocities.remove_at(index)
	_ages.remove_at(index)
	_owners.remove_at(index)
```

- [ ] **Step 4: Run to verify it passes.** Expect `checks: 148  failures: 0` (140 + 8).

- [ ] **Step 5: Commit** — `"Add swept bullets that cannot tunnel through a target"`

---

## Task 5: Health, damage, death and armament

**Files:** modify `scripts/aircraft.gd`; create `tests/test_damage.gd`; modify `tests/run_tests.gd`.

- [ ] **Step 1: Write the failing test**

`tests/test_damage.gd`:
```gdscript
extends TestCase

func test_damage_reduces_health() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.ENEMY_HP
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	aircraft.take_damage(Config.BULLET_DAMAGE)
	check_approx(aircraft.hp, Config.ENEMY_HP - Config.BULLET_DAMAGE, 1e-6,
		"a hit removes BULLET_DAMAGE health")
	check(aircraft.is_alive(), "one hit does not kill an enemy")
	aircraft.free()

func test_enough_damage_kills() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.ENEMY_HP
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	var rounds := int(ceil(Config.ENEMY_HP / Config.BULLET_DAMAGE))
	for i in rounds:
		aircraft.take_damage(Config.BULLET_DAMAGE)
	check(not aircraft.is_alive(), "enough hits kill")
	check(aircraft.hp <= 0.0, "health does not go back up")
	aircraft.free()

func test_reset_restores_full_health() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.PLAYER_HP
	aircraft.take_damage(Config.PLAYER_HP)
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	check_approx(aircraft.hp, Config.PLAYER_HP, 1e-6, "respawning restores full health")
	check(aircraft.is_alive(), "and the aircraft is alive again")
	aircraft.free()

func test_damage_after_death_does_not_re_emit() -> void:
	var aircraft := Aircraft.new()
	aircraft.max_hp = Config.ENEMY_HP
	aircraft.reset(Vector3(0.0, 600.0, 0.0))
	var deaths := [0]
	aircraft.died.connect(func(): deaths[0] += 1)
	for i in 20:
		aircraft.take_damage(Config.BULLET_DAMAGE)
	check(deaths[0] == 1, "death fires exactly once however many rounds land")
	aircraft.free()
```

Add `"res://tests/test_damage.gd"` to `SUITES`.

- [ ] **Step 2: Run to verify it fails** — `max_hp` / `take_damage` unknown, `exit=1`.

- [ ] **Step 3: Write the implementation**

In `scripts/aircraft.gd`, add beside the other members:
```gdscript
signal died

var max_hp := Config.PLAYER_HP
var hp := Config.PLAYER_HP
```

and:
```gdscript
func is_alive() -> bool:
	return hp > 0.0

## Guarded so a burst that lands several rounds on an already-dead aircraft
## emits one death, not one per round.
func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		died.emit()
```

In `reset()`, add as the first line:
```gdscript
	hp = max_hp
```

**Arm the aircraft too.** Every aircraft carries its own weapon, and `tick()` records whether a
round left the barrel this tick. Without this, `game.gd` would have to call
`controller.command()` a second time to find out whether the trigger was pulled — running the
whole AI state machine twice per tick and getting a different answer the second time — and enemy
aircraft would have no way to fire at all.

Add beside the other members:
```gdscript
var weapon := Weapon.new()
## True on the ticks this aircraft actually produced a round.
var fired := false
```

and extend `tick()` so it reads:
```gdscript
func tick(delta: float) -> void:
	if controller == null:
		return
	var cmd: InputCommand = controller.command(self, delta)
	cmd.aim_dir = Boundary.constrain(cmd.aim_dir, model.position)
	model.step(cmd, delta)
	fired = weapon.try_fire(delta, cmd.fire)
	sync_transform()
	if is_below_ground():
		crashed.emit()

func muzzle() -> Vector3:
	return model.position + model.forward() * Config.MUZZLE_FORWARD
```

Append to `tests/test_damage.gd`:
```gdscript
class TriggerHeld extends RefCounted:
	func command(aircraft, _dt) -> InputCommand:
		var cmd := InputCommand.new()
		cmd.aim_dir = aircraft.model.forward()
		cmd.fire = true
		return cmd

func test_a_held_trigger_produces_rounds_at_the_configured_rate() -> void:
	var aircraft := Aircraft.new()
	aircraft.controller = TriggerHeld.new()
	aircraft.reset(Vector3(0.0, 2000.0, 0.0))
	var rounds := 0
	for i in 600:
		aircraft.tick(1.0 / 60.0)
		if aircraft.fired:
			rounds += 1
	check_approx(float(rounds), Config.FIRE_RATE * 10.0, 2.0,
		"an aircraft with the trigger held produces about FIRE_RATE rounds a second")
	aircraft.free()

func test_the_muzzle_sits_ahead_of_the_nose() -> void:
	var aircraft := Aircraft.new()
	aircraft.reset(Vector3.ZERO)
	check_approx(aircraft.muzzle().distance_to(aircraft.model.position), Config.MUZZLE_FORWARD,
		1e-4, "the muzzle sits MUZZLE_FORWARD ahead of the model origin")
	check(aircraft.muzzle().z < 0.0, "and ahead of the nose, which points at -Z")
	aircraft.free()
```

- [ ] **Step 4: Run to verify it passes.** Expect `checks: 160  failures: 0` (148 + 12).

- [ ] **Step 5: Commit** — `"Give the aircraft health, damage, death and its own weapon"`

---

## Task 6: The AI pilot

Four states, driving the same `FlightModel` through the same `InputCommand` as the player. Aim is
a **world-space direction to a world point** — there is no body frame involved, which is why the
Phase 1 aim-frame trap cannot recur here.

**Files:** create `scripts/ai_pilot.gd`, `tests/test_ai.gd`; modify `scripts/config.gd`, `tests/run_tests.gd`.

- [ ] **Step 1: add constants**

```gdscript

# --- AI ---
const ATTACK_CONE_DEG := 12.0
const ATTACK_RANGE := 600.0         # m
const MIN_SEPARATION := 120.0       # m, below which the AI breaks off
const BREAK_TIME := 2.5             # s
const REPOSITION_ALTITUDE := 450.0  # m, floor the AI climbs back to
const AI_THROTTLE := 0.85
const AIM_JITTER_START_DEG := 8.0
const AIM_JITTER_END_DEG := 2.0
```

- [ ] **Step 2: Write the failing test**

`tests/test_ai.gd`:
```gdscript
extends TestCase

func _target_at(where: Vector3) -> Aircraft:
	var aircraft := Aircraft.new()
	aircraft.reset(where)
	return aircraft

func test_ai_pursues_a_distant_target() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var self_craft := _target_at(Vector3(0.0, 600.0, 0.0))
	var prey := _target_at(Vector3(0.0, 600.0, -1500.0))
	pilot.target = prey
	pilot.command(self_craft, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.PURSUE, "a distant target is pursued")
	self_craft.free()
	prey.free()

func test_ai_attacks_when_close_and_lined_up() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var self_craft := _target_at(Vector3(0.0, 600.0, 0.0))
	var prey := _target_at(Vector3(0.0, 600.0, -300.0))  # dead ahead, in range
	pilot.target = prey
	var cmd := pilot.command(self_craft, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.ATTACK, "a target in the cone and in range is attacked")
	check(cmd.fire, "and the trigger is pulled")
	self_craft.free()
	prey.free()

func test_ai_breaks_off_when_too_close() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var self_craft := _target_at(Vector3(0.0, 600.0, 0.0))
	var prey := _target_at(Vector3(0.0, 600.0, -Config.MIN_SEPARATION * 0.5))
	pilot.target = prey
	var cmd := pilot.command(self_craft, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.BREAK, "a target inside MIN_SEPARATION triggers a break")
	check(not cmd.fire, "and the AI stops shooting while breaking off")
	self_craft.free()
	prey.free()

func test_a_break_ends_by_itself() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var self_craft := _target_at(Vector3(0.0, 600.0, 0.0))
	var prey := _target_at(Vector3(0.0, 600.0, -2000.0))
	pilot.target = prey
	pilot.state = AIPilot.State.BREAK
	pilot.state_timer = Config.BREAK_TIME
	for i in int(Config.BREAK_TIME * 60.0) + 10:
		pilot.command(self_craft, 1.0 / 60.0)
	check(pilot.state != AIPilot.State.BREAK, "a break times out rather than lasting forever")
	self_craft.free()
	prey.free()

func test_ai_climbs_when_low() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var self_craft := _target_at(Vector3(0.0, 50.0, 0.0))
	var prey := _target_at(Vector3(0.0, 600.0, -2000.0))
	pilot.target = prey
	var cmd := pilot.command(self_craft, 1.0 / 60.0)
	check(pilot.state == AIPilot.State.REPOSITION, "an AI below its floor repositions")
	check(cmd.aim_dir.y > 0.0, "and aims upward")
	self_craft.free()
	prey.free()

func test_ai_aim_is_world_space_not_body_relative() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var prey := _target_at(Vector3(0.0, 600.0, -800.0))
	pilot.target = prey
	var level := _target_at(Vector3(0.0, 600.0, 0.0))
	var banked := _target_at(Vector3(0.0, 600.0, 0.0))
	banked.model.basis = Basis(Vector3.FORWARD, deg_to_rad(75.0))
	var a := pilot.command(level, 1.0 / 60.0).aim_dir
	pilot.state = AIPilot.State.PURSUE
	var b := pilot.command(banked, 1.0 / 60.0).aim_dir
	check(a.angle_to(b) < 1e-3,
		"AI aim must not depend on its own bank, or Phase 1's dive bug returns")
	level.free()
	banked.free()
	prey.free()

func test_a_dogfight_stays_airborne_and_bounded() -> void:
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	var hunter := _target_at(Vector3(0.0, 800.0, 400.0))
	var prey := _target_at(Vector3(0.0, 800.0, -400.0))
	pilot.target = prey
	hunter.controller = pilot
	var lowest := hunter.model.position.y
	var furthest := 0.0
	for i in 3600:  # one minute of chasing a stationary target
		hunter.tick(1.0 / 60.0)
		lowest = minf(lowest, hunter.model.position.y)
		furthest = maxf(furthest, Vector2(hunter.model.position.x, hunter.model.position.z).length())
	check(lowest > 0.0, "an AI chasing a target for a minute does not fly into the ground")
	check(furthest < Config.WORLD_SIZE * 0.5, "and stays inside the world")
	check(absf(hunter.model.basis.determinant() - 1.0) < 1e-4, "and stays well-conditioned")
	hunter.free()
	prey.free()
```

Add `"res://tests/test_ai.gd"` to `SUITES`.

- [ ] **Step 3: Run to verify it fails** — `AIPilot` unknown, `exit=1`.

- [ ] **Step 4: Write the implementation**

`scripts/ai_pilot.gd`:
```gdscript
class_name AIPilot
extends RefCounted

enum State { PURSUE, ATTACK, BREAK, REPOSITION }

var target: Aircraft = null
var state := State.PURSUE
var state_timer := 0.0
var jitter_degrees := Config.AIM_JITTER_START_DEG

var _weapon := Weapon.new()
var _jitter_axis := Vector3.UP
var _jitter_phase := 0.0

## Aim is a direction to a point in the world. There is deliberately no body
## frame here: expressing AI aim relative to the aircraft's own basis is exactly
## what made the player's controls dive in Phase 1.
func command(aircraft: Aircraft, dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.throttle_delta = 1.0 if aircraft.model.throttle < Config.AI_THROTTLE else -1.0
	if target == null or not target.is_alive():
		cmd.aim_dir = aircraft.model.forward()
		return cmd
	var to_target := target.model.position - aircraft.model.position
	var distance := to_target.length()
	_update_state(aircraft, distance, dt)
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
## out to perfect aim, which is not what a beatable enemy looks like.
func _apply_jitter(aim: Vector3, dt: float) -> Vector3:
	if jitter_degrees <= 0.0:
		return aim
	_jitter_phase += dt
	var axis := aim.cross(Vector3.UP)
	if axis.length_squared() < 1e-6:
		axis = Vector3.RIGHT
	axis = axis.normalized().rotated(aim, _jitter_phase * 1.7)
	return aim.rotated(axis, deg_to_rad(jitter_degrees) * sin(_jitter_phase * 0.9))

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
```

The pilot decides *whether* to shoot and sets `cmd.fire`; the aircraft's own `Weapon` decides
*when* a round actually leaves the barrel. Keeping the rate limit out of the pilot means the AI
cannot accidentally out-shoot the player, and `game.gd` never has to run a state machine twice to
find out what a pilot wanted.

- [ ] **Step 5: Run to verify it passes.** Expect `checks: 175  failures: 0` (160 + 15).

- [ ] **Step 6: Commit** — `"Add the AI pilot state machine"`

---

## Task 7: Waves

**Files:** create `scripts/wave_director.gd`, `tests/test_waves.gd`; modify `scripts/config.gd`, `tests/run_tests.gd`.

- [ ] **Step 1: add constants**

```gdscript

# --- Waves ---
const WAVE_GAP := 3.0               # s between waves
const MAX_WAVE_SIZE := 6
const JITTER_RAMP_WAVES := 10
const SPAWN_RADIUS := 2200.0        # m from the player
const SPAWN_ALTITUDE := 700.0       # m
```

- [ ] **Step 2: Write the failing test**

`tests/test_waves.gd`:
```gdscript
extends TestCase

func test_wave_size_grows_and_caps() -> void:
	check(WaveDirector.wave_size(1) == 1, "the first wave is a single fighter")
	check(WaveDirector.wave_size(3) == 2, "waves grow every second wave")
	check(WaveDirector.wave_size(100) == Config.MAX_WAVE_SIZE, "and cap at MAX_WAVE_SIZE")

func test_wave_size_never_shrinks() -> void:
	var previous := 0
	for wave in range(1, 40):
		var size := WaveDirector.wave_size(wave)
		check(size >= previous, "wave %d is not smaller than the one before" % wave)
		previous = size

func test_jitter_tightens_with_waves() -> void:
	check_approx(WaveDirector.jitter_for(1), Config.AIM_JITTER_START_DEG, 1e-4,
		"the first wave shoots at the loosest jitter")
	check_approx(WaveDirector.jitter_for(Config.JITTER_RAMP_WAVES), Config.AIM_JITTER_END_DEG, 1e-4,
		"the ramp ends at AIM_JITTER_END_DEG")
	check_approx(WaveDirector.jitter_for(50), Config.AIM_JITTER_END_DEG, 1e-4,
		"and stays there afterwards")
	check(WaveDirector.jitter_for(3) < WaveDirector.jitter_for(2),
		"jitter tightens monotonically")

func test_spawn_points_ring_the_player_at_altitude() -> void:
	var centre := Vector3(100.0, 600.0, -200.0)
	for i in 6:
		var point := WaveDirector.spawn_point(centre, i, 6)
		var flat := Vector2(point.x - centre.x, point.z - centre.z).length()
		check_approx(flat, Config.SPAWN_RADIUS, 1.0, "spawn %d rings the player" % i)
		check_approx(point.y, Config.SPAWN_ALTITUDE, 1e-4, "spawn %d is at altitude" % i)

func test_spawn_points_are_spread_out() -> void:
	var centre := Vector3.ZERO
	var first := WaveDirector.spawn_point(centre, 0, 4)
	var second := WaveDirector.spawn_point(centre, 1, 4)
	check(first.distance_to(second) > Config.SPAWN_RADIUS * 0.5,
		"consecutive spawns are not stacked on top of each other")

func test_spawn_points_stay_inside_the_world() -> void:
	var edge := Vector3(Config.BOUNDARY_SOFT_START, 600.0, 0.0)
	for i in 6:
		var point := WaveDirector.spawn_point(edge, i, 6)
		check(Vector2(point.x, point.z).length() < Config.WORLD_SIZE * 0.5,
			"spawn %d near the boundary is still inside the world" % i)
```

Add `"res://tests/test_waves.gd"` to `SUITES`.

- [ ] **Step 3: Run to verify it fails** — `WaveDirector` unknown, `exit=1`.

- [ ] **Step 4: Write the implementation**

`scripts/wave_director.gd`:
```gdscript
class_name WaveDirector
extends RefCounted

static func wave_size(wave: int) -> int:
	return mini(1 + int(floor(float(wave) / 2.0)), Config.MAX_WAVE_SIZE)

static func jitter_for(wave: int) -> float:
	var t := clampf(float(wave - 1) / float(maxi(Config.JITTER_RAMP_WAVES - 1, 1)), 0.0, 1.0)
	return lerpf(Config.AIM_JITTER_START_DEG, Config.AIM_JITTER_END_DEG, t)

## Ringed around the player and pulled back toward the world centre if that ring
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
```

- [ ] **Step 5: Run to verify it passes.** Expect `checks: 192  failures: 0` (175 + 17).

- [ ] **Step 6: Commit** — `"Add the wave size, difficulty and spawn placement curves"`

---

## Task 8: Scoring, combo and high score

**Files:** create `scripts/scoring.gd`, `tests/test_scoring.gd`; modify `scripts/config.gd`, `tests/run_tests.gd`.

- [ ] **Step 1: add constants**

```gdscript

# --- Scoring ---
const BASE_KILL_SCORE := 100
const COMBO_WINDOW := 4.0           # s within which kills chain
const COMBO_STEP := 0.5
const COMBO_CAP := 4.0
const HIGH_SCORE_PATH := "user://highscore.cfg"
```

- [ ] **Step 2: Write the failing test**

`tests/test_scoring.gd`:
```gdscript
extends TestCase

func test_a_single_kill_scores_the_base_value() -> void:
	var scoring := Scoring.new()
	scoring.register_kill()
	check(scoring.score == Config.BASE_KILL_SCORE, "one kill scores the base value")
	check_approx(scoring.multiplier, 1.0, 1e-6, "and leaves the multiplier at one")

func test_quick_kills_chain() -> void:
	var scoring := Scoring.new()
	scoring.register_kill()
	scoring.advance(Config.COMBO_WINDOW * 0.5)
	scoring.register_kill()
	check(scoring.multiplier > 1.0, "a second kill inside the window raises the multiplier")
	check(scoring.score > Config.BASE_KILL_SCORE * 2,
		"and the second kill is worth more than the first")

func test_slow_kills_do_not_chain() -> void:
	var scoring := Scoring.new()
	scoring.register_kill()
	scoring.advance(Config.COMBO_WINDOW + 0.1)
	scoring.register_kill()
	check_approx(scoring.multiplier, 1.0, 1e-6, "a kill outside the window breaks the chain")
	check(scoring.score == Config.BASE_KILL_SCORE * 2, "and scores the base value again")

func test_the_multiplier_caps() -> void:
	var scoring := Scoring.new()
	for i in 40:
		scoring.register_kill()
		scoring.advance(0.1)
	check_approx(scoring.multiplier, Config.COMBO_CAP, 1e-6, "the multiplier caps at COMBO_CAP")

func test_the_chain_expires_without_kills() -> void:
	var scoring := Scoring.new()
	scoring.register_kill()
	scoring.advance(0.5)
	scoring.register_kill()
	check(scoring.multiplier > 1.0, "the chain is running")
	scoring.advance(Config.COMBO_WINDOW + 0.1)
	check_approx(scoring.multiplier, 1.0, 1e-6, "and lapses once the window passes with no kill")

func test_high_score_round_trips() -> void:
	var scoring := Scoring.new()
	var previous := scoring.high_score
	scoring.score = previous + 12345
	scoring.save_high_score()
	var reloaded := Scoring.new()
	check(reloaded.high_score >= previous + 12345, "a new best survives a reload")
	# Leave no residue: restore whatever was there before.
	reloaded.score = previous
	reloaded.high_score = previous
	reloaded.save_high_score(true)

func test_a_lower_score_does_not_overwrite_the_best() -> void:
	var scoring := Scoring.new()
	scoring.high_score = 9999
	scoring.score = 10
	scoring.save_high_score()
	check(scoring.high_score == 9999, "a worse run does not replace the high score")
```

Add `"res://tests/test_scoring.gd"` to `SUITES`.

- [ ] **Step 3: Run to verify it fails** — `Scoring` unknown, `exit=1`.

- [ ] **Step 4: Write the implementation**

`scripts/scoring.gd`:
```gdscript
class_name Scoring
extends RefCounted

var score := 0
var multiplier := 1.0
var high_score := 0

var _since_last_kill := 0.0
var _chaining := false

func _init() -> void:
	high_score = _load_high_score()

## The chain lapses when COMBO_WINDOW passes with no kill.
func advance(dt: float) -> void:
	if not _chaining:
		return
	_since_last_kill += dt
	if _since_last_kill > Config.COMBO_WINDOW:
		_chaining = false
		multiplier = 1.0

func register_kill() -> void:
	if _chaining and _since_last_kill <= Config.COMBO_WINDOW:
		multiplier = minf(multiplier + Config.COMBO_STEP, Config.COMBO_CAP)
	else:
		multiplier = 1.0
	score += int(round(float(Config.BASE_KILL_SCORE) * multiplier))
	_chaining = true
	_since_last_kill = 0.0

func save_high_score(force := false) -> void:
	if not force and score <= high_score:
		return
	high_score = score
	var file := ConfigFile.new()
	file.set_value("run", "high_score", high_score)
	file.save(Config.HIGH_SCORE_PATH)

## A missing file on first launch is normal, not an error.
func _load_high_score() -> int:
	var file := ConfigFile.new()
	if file.load(Config.HIGH_SCORE_PATH) != OK:
		return 0
	return int(file.get_value("run", "high_score", 0))
```

- [ ] **Step 5: Run to verify it passes.** Expect `checks: 205  failures: 0` (192 + 13).

- [ ] **Step 6: Commit** — `"Add kill scoring, the combo chain and a persisted high score"`

---

## Task 9: Debris and the combat HUD

**Files:** create `scripts/debris.gd`; modify `scripts/hud.gd`, `scripts/config.gd`.

- [ ] **Step 1: add constants**

```gdscript

# --- Debris ---
const DEBRIS_COUNT := 5
const DEBRIS_LIFETIME := 6.0        # s
const DEBRIS_SPEED := 14.0          # m/s of initial scatter
```

- [ ] **Step 2: Write `scripts/debris.gd`**

The one place the physics engine is used, and deliberately so: wreckage is decoration, not
control, which is exactly where a solver belongs.

```gdscript
class_name Debris
extends Node3D

## Scatters a handful of tumbling chunks that free themselves. Rigid bodies are
## used here and nowhere else: this is decoration, so nondeterminism costs
## nothing and collision response comes free.
static func scatter(parent: Node3D, at: Vector3, inherited: Vector3) -> void:
	for i in Config.DEBRIS_COUNT:
		var chunk := RigidBody3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.4, 1.2), randf_range(0.4, 1.0), randf_range(0.6, 1.6))
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.32, 0.30, 0.28)
		mesh.material = material
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		chunk.add_child(visual)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		chunk.add_child(shape)
		chunk.position = at
		chunk.linear_velocity = inherited + Vector3(
			randf_range(-1.0, 1.0), randf_range(0.0, 1.0), randf_range(-1.0, 1.0)
		).normalized() * Config.DEBRIS_SPEED
		chunk.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0),
			randf_range(-6.0, 6.0))
		parent.add_child(chunk)
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = Config.DEBRIS_LIFETIME
		timer.timeout.connect(chunk.queue_free)
		chunk.add_child(timer)
		timer.start()
```

- [ ] **Step 3: Extend the HUD**

In `scripts/hud.gd`, add members:
```gdscript
var scoring: Scoring = null
var enemies: Array = []
```

and extend `_draw()` after `_draw_readouts()`:
```gdscript
	_draw_health()
	_draw_score()
	_draw_enemy_markers(centre)
```

with:
```gdscript
func _draw_health() -> void:
	var fraction := clampf(target.hp / maxf(target.max_hp, 1.0), 0.0, 1.0)
	var bar := Rect2(28.0, size.y - 76.0, 220.0, 14.0)
	draw_rect(bar, HUD_COLOR, false, 2.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), HUD_COLOR)

func _draw_score() -> void:
	if scoring == null:
		return
	_text(Vector2(size.x - 220.0, 44.0), "SCORE %7d" % scoring.score)
	_text(Vector2(size.x - 220.0, 68.0), "BEST  %7d" % scoring.high_score)
	if scoring.multiplier > 1.0:
		_text(Vector2(size.x - 220.0, 92.0), "x%.1f" % scoring.multiplier)

## A chevron at the screen edge for every enemy that is not on screen, so a
## dogfight does not become a hunt for something behind you.
func _draw_enemy_markers(centre: Vector2) -> void:
	var basis := target.model.basis
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var to_enemy: Vector3 = enemy.model.position - target.model.position
		if to_enemy.length_squared() < 1e-6:
			continue
		var local := basis.inverse() * to_enemy
		var flat := Vector2(local.x, -local.y)
		if local.z < 0.0 and flat.length() < size.y * 0.35:
			continue  # roughly ahead and on screen already
		if flat.length_squared() < 1e-6:
			flat = Vector2(0.0, 1.0)
		var direction := flat.normalized()
		var at := centre + direction * (size.y * 0.40)
		draw_circle(at, 6.0, HUD_COLOR)
```

- [ ] **Step 4: Verify the project still parses and the suite is green.** Expect `checks: 205  failures: 0`.

- [ ] **Step 5: Commit** — `"Add wreckage and the combat HUD"`

---

## Task 10: Wire combat into the game, and accept

**Files:** modify `scripts/game.gd`; create `tests/test_combat_integration.gd`; modify `tests/run_tests.gd`.

- [ ] **Step 1: Write the failing integration test**

`tests/test_combat_integration.gd`:
```gdscript
extends TestCase

## The shape of test Phase 1 lacked: a real AI pilot driving a real FlightModel
## against a real target, for long enough for a fight to actually happen.

func test_an_ai_can_kill_a_stationary_target() -> void:
	var hunter := Aircraft.new()
	hunter.max_hp = Config.ENEMY_HP
	hunter.reset(Vector3(0.0, 800.0, 900.0))
	var prey := Aircraft.new()
	prey.max_hp = Config.PLAYER_HP
	prey.reset(Vector3(0.0, 800.0, 0.0))
	var pilot := AIPilot.new()
	pilot.jitter_degrees = 0.0
	pilot.target = prey
	hunter.controller = pilot
	var bullets := Bullets.new()
	var dt := 1.0 / 60.0
	for i in 3600:  # one minute
		hunter.tick(dt)
		if hunter.fired:
			bullets.spawn(hunter.muzzle(), hunter.model.forward(), hunter)
		for hit in bullets.step(dt, [prey]):
			hit.take_damage(Config.BULLET_DAMAGE)
		if not prey.is_alive():
			break
	check(not prey.is_alive(), "an AI with no aim error eventually kills a stationary target")
	hunter.free()
	prey.free()
	bullets.free()

func test_rounds_expire_rather_than_accumulating() -> void:
	var bullets := Bullets.new()
	for i in 600:
		bullets.spawn(Vector3.ZERO, Vector3.FORWARD, null)
		bullets.step(1.0 / 60.0, [])
	check(bullets.count() <= int(Config.FIRE_RATE * Config.BULLET_LIFETIME) + 60,
		"live rounds are bounded, so a long fight cannot leak")
	bullets.free()
```

Add `"res://tests/test_combat_integration.gd"` to `SUITES`.

- [ ] **Step 2: Run, expect failure, then wire `game.gd`**

Add members:
```gdscript
var bullets: Bullets
var scoring: Scoring
var enemies: Array[Aircraft] = []
var wave := 0
var _wave_gap := 0.0
```

In `_ready()`, after the HUD wiring:
```gdscript
	bullets = Bullets.new()
	add_child(bullets)
	scoring = Scoring.new()
	hud.scoring = scoring
	hud.enemies = enemies
	aircraft.max_hp = Config.PLAYER_HP
	aircraft.died.connect(_on_player_died)
```

Add:
```gdscript
## Every aircraft has already ticked its own controller and weapon by the time
## this runs, so `fired` is read rather than recomputed. Calling command() again
## here would run each AI state machine twice per tick and get a different answer
## the second time.
func _physics_process(delta: float) -> void:
	scoring.advance(delta)
	var combatants: Array = [aircraft]
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			combatants.append(enemy)
	for craft in combatants:
		if craft.fired:
			bullets.spawn(craft.muzzle(), craft.model.forward(), craft)
	for hit in bullets.step(delta, combatants):
		hit.take_damage(Config.BULLET_DAMAGE)
	_advance_waves(delta)

func _advance_waves(delta: float) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			return
	_wave_gap -= delta
	if _wave_gap > 0.0:
		return
	_wave_gap = Config.WAVE_GAP
	wave += 1
	_spawn_wave()

func _spawn_wave() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	var size := WaveDirector.wave_size(wave)
	for i in size:
		var enemy: Aircraft = preload("res://scenes/aircraft.tscn").instantiate()
		enemy.terrain = terrain
		enemy.max_hp = Config.ENEMY_HP
		var pilot := AIPilot.new()
		pilot.target = aircraft
		pilot.jitter_degrees = WaveDirector.jitter_for(wave)
		enemy.controller = pilot
		enemy.died.connect(_on_enemy_died.bind(enemy))
		add_child(enemy)
		enemy.reset(WaveDirector.spawn_point(aircraft.model.position, i, size))
		enemies.append(enemy)
	hud.enemies = enemies

func _on_enemy_died(enemy: Aircraft) -> void:
	scoring.register_kill()
	Debris.scatter(self, enemy.model.position, enemy.model.forward() * enemy.model.speed * 0.3)
	enemy.queue_free()

func _on_player_died() -> void:
	scoring.save_high_score()
	wave = 0
	scoring.score = 0
	_restart()
	_spawn_wave()
```

- [ ] **Step 3: Run to verify green.** Expect `checks: 208  failures: 0` (205 + 3).

- [ ] **Step 4: Headless boot check**

```bash
"$GODOT" --headless --path . --quit-after 1600 2>&1 | tail -30; echo "exit=${PIPESTATUS[0]}"
```
No `SCRIPT ERROR`, no engine `ERROR:`. Headless has no pointer, so the player will spiral and
crash — check for errors, not flight quality.

- [ ] **Step 5: Commit and push**

```bash
git commit -m "Wire combat into the game loop" && git push -u origin phase2-combat
```

---

## Phase 2 acceptance

Automated: `checks: 208  failures: 0`, plus every mutation check named in each task.

Manual, for the user:

- [ ] Enemies visibly pursue, attack, overshoot and break rather than tailing rigidly
- [ ] Wave 1 is winnable and wave 8 is genuinely hard
- [ ] Rounds hit at high closing speed — no visible pass-through
- [ ] Score, combo and high score behave, and the best survives a restart
- [ ] Wreckage appears on a kill and disappears again
- [ ] Off-screen enemy markers point somewhere useful
- [ ] No frame-rate collapse after ten consecutive waves

---

## Still deferred after Phase 2

Missiles · ground targets · aircraft selection or unlocks · audio · multiplayer netcode ·
the Android toolchain. The `InputCommand` seam remains the insertion point for all of it.
