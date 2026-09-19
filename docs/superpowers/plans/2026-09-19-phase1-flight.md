# Phase 1: Flight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A flyable jet over procedural island terrain on Windows desktop, with a chase camera, HUD and touch-ready controls, tuned until flying feels good on its own — no combat.

**Architecture:** `FlightModel` is a plain `RefCounted` holding `{position, basis, speed, throttle}` and advancing it with its own integrator. It never touches a node, so it runs headless under test. Every controller (player now, AI in Phase 2) produces the same `InputCommand`, which is the only thing `FlightModel.step()` accepts. Godot nodes read the model's state and draw it.

**Tech Stack:** Godot 4 (GDScript), `FastNoiseLite` + `SurfaceTool` for terrain, a bespoke ~45-line headless assert runner for tests (no plugin dependency).

**Spec:** `docs/superpowers/specs/2026-09-19-flying-arcade-dogfighter-design.md`

---

## Conventions

**Godot binary.** Godot 4.7.2 is installed (winget, `GodotEngine.GodotEngine`). Use the
**`_console`** variant: the plain `.exe` detaches from the terminal on Windows, so `print()`
output and exit codes would not come back. Every command below assumes:

```bash
export GODOT="/c/Users/KulkulZa/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
cd /d/toy_project/Flying
```

**Test command.** One command runs everything, used in every task:

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd; echo "exit=$?"
```

**Import first, after adding any new `class_name` script.** Godot resolves `class_name` types
from a registry built during import. A cold run, or the first run after a new class is added,
fails with `Parse Error: Could not find type "X" in the current scope` until you run:

```bash
"$GODOT" --headless --path . --import
```

This is not a fluke — expect it on every fresh clone and whenever a task introduces a new class.

**`.uid` sidecars.** Godot 4.4+ writes a `<script>.gd.uid` beside every script during import.
They are the stable resource-reference mechanism and **should be committed** (unlike `.godot/`,
which is ignored). Every task adding a `.gd` file produces one; that is expected, not stray.

**Commits.** Every commit message ends with the trailer:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

**Process hygiene.** Godot's editor and any `--headless` run must exit before a task is called
done. If a run hangs, terminate it rather than leaving it resident:
`powershell -c "Get-Process Godot* -ErrorAction SilentlyContinue | Stop-Process -Force"`.

**Scratch files** go outside the project. Only the files listed below are created in it.

**Visual verification.** Tasks that change what is on screen end with a manual checklist for the
user, because the running game cannot be observed from the development environment. One avenue
is still open: the desktop-control tooling matches *running* applications, and Godot was
installed as a portable executable with no Start-menu entry, so an access request made while the
game is running may succeed where one made beforehand cannot. Retry it at Task 10, once there is
a window to attach to. If it works, the checklists in Tasks 13, 14 and 17 shrink accordingly; if
it does not, they stand as written.

### Two deliberate deviations from the spec

1. **The ground check lives in `aircraft.gd`, not `FlightModel.step()`.** The spec put it at
   step 10 of the model. Terrain knowledge inside `FlightModel` would destroy the purity that
   makes it testable, so the node that already knows about the world does the test.
2. **`Camera3D` with lag, not `SpringArm3D`.** A spring arm exists to stop a camera clipping
   through geometry; in Phase 1 nothing can occlude the chase view. Revisit when something can.

---

## File Structure

| File | Responsibility |
|---|---|
| `project.godot` | Project settings, 60 Hz physics, main scene |
| `scripts/config.gd` | Every tunable constant. No logic. |
| `scripts/input_command.gd` | The one struct every controller emits |
| `scripts/flight_model.gd` | Pure flight integrator. No nodes. Fully tested. |
| `scripts/boundary.gd` | Pure function biasing aim back inside the world |
| `scripts/terrain.gd` | Noise heightmap, mesh build, `height_at()` query |
| `scripts/aircraft.gd` | Node glue: controller to model to transform, ground test |
| `scripts/jet_visual.gd` | Primitive geometry only — the swappable slot |
| `scripts/chase_camera.gd` | Follow with lag, FOV by speed |
| `scripts/player_controller.gd` | Mouse/keys/touch to `InputCommand` |
| `scripts/hud.gd` | Instruments, horizon, reticle |
| `scripts/touch_controls.gd` | Floating stick, throttle slider, fire button |
| `scripts/game.gd` | Builds the world, owns restart |
| `scenes/main.tscn`, `scenes/aircraft.tscn` | Thin scene roots; geometry is built in code |
| `tests/run_tests.gd`, `tests/test_case.gd` | Headless harness |
| `tests/test_*.gd` | One suite per tested unit |

Scenes are kept to a root node plus a script because all geometry is generated in GDScript;
hand-authored `.tscn` geometry would be harder to review and impossible to test.

---

## Task 1: Project skeleton and a test harness that can fail

**Files:**
- Create: `project.godot`, `scenes/main.tscn`, `scripts/game.gd`
- Create: `tests/test_case.gd`, `tests/run_tests.gd`, `tests/test_smoke.gd`

- [x] **Step 1: Install Godot 4** — done, 4.7.2 via winget

Verify the binary responds before doing anything else:

```bash
"$GODOT" --version
```

Expected: `4.7.2.stable.official.ed1daf0bf`.

- [ ] **Step 2: Create the project skeleton**

`project.godot`:

```ini
config_version=5

[application]
config/name="Flying"
run/main_scene="res://scenes/main.tscn"

[physics]
common/physics_ticks_per_second=60
```

`scenes/main.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/game.gd" id="1_game"]

[node name="Main" type="Node3D"]
script = ExtResource("1_game")
```

`scripts/game.gd`:

```gdscript
extends Node3D

func _ready() -> void:
	print("Flying: booted")
```

- [ ] **Step 3: Write the harness, with a deliberately failing test**

`tests/test_case.gd`:

```gdscript
class_name TestCase
extends RefCounted

var runner: Object = null

func check(condition: bool, message: String) -> void:
	runner.check(condition, message)

func check_approx(actual: float, expected: float, tol: float, message: String) -> void:
	runner.check_approx(actual, expected, tol, message)
```

`tests/run_tests.gd` — this is the shipped version, hardened after code review. The naive
shape (load, construct and loop all inline in `_initialize()`) **hangs the headless process
forever** when a `SUITES` path is wrong: `load()` returns null, `script.new()` errors directly
in `_initialize()`'s body, and `quit()` is never reached. Since `SUITES` is hand-edited in
nearly every later task, that is a routine mistake, not an exotic one.

```gdscript
extends SceneTree

const SUITES := [
	"res://tests/test_smoke.gd",
]

var _checks := 0
var _failures: Array[String] = []
var _suites_completed := 0
var _current := ""

func _initialize() -> void:
	for path in SUITES:
		_run_suite(path)
	if _suites_completed != SUITES.size():
		_failures.append("only %d of %d suites ran to completion - scan the output above for SCRIPT ERROR"
			% [_suites_completed, SUITES.size()])
	print("checks: %d  failures: %d" % [_checks, _failures.size()])
	for message in _failures:
		print("FAIL: ", message)
	quit(1 if _failures.size() > 0 else 0)

## Runs one suite. GDScript has no exception handling, but a runtime error
## unwinds only the function it occurs in. Keeping load/new/runner-assignment
## in here means such an error returns control to _initialize()'s loop instead
## of aborting it, so quit() is always reached and the process can never hang.
## _suites_completed is incremented only on a clean finish.
func _run_suite(path: String) -> void:
	var script: GDScript = load(path)
	var suite: TestCase = script.new()
	suite.runner = self
	var seen := {}
	for method in suite.get_method_list():
		var name: String = method.name
		if name.begins_with("test_") and not seen.has(name):
			seen[name] = true
			_current = "%s#%s" % [path.get_file(), name]
			var before := _checks
			suite.call(name)
			if _checks == before:
				_failures.append("[%s] recorded no checks - it probably errored before asserting" % _current)
	_suites_completed += 1

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [_current, message])

func check_approx(actual: float, expected: float, tol: float, message: String) -> void:
	check(actual == expected or absf(actual - expected) <= tol,
		"%s (got %.6f, expected %.6f +/- %.6f)" % [message, actual, expected, tol])
```

**Known limitation, by design.** A test that errors *after* some checks have passed still
reports those checks as passes. GDScript has no exception handling, so this is not fixable
within this design. Always scan output for `SCRIPT ERROR`, not just the summary line.

`tests/test_smoke.gd`:

```gdscript
extends TestCase

func test_harness_reports_failures() -> void:
	check(false, "deliberate failure proving the harness can fail")
```

- [ ] **Step 4: Run and verify the harness FAILS**

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd; echo "exit=$?"
```

Expected:

```
checks: 1  failures: 1
FAIL: deliberate failure proving the harness can fail
exit=1
```

If Godot errors that resources are not imported, run `"$GODOT" --headless --path . --import`
once and retry. A harness that cannot report failure is worthless, which is why this step
exists before any real test.

- [ ] **Step 5: Flip the assertion and verify it PASSES**

In `tests/test_smoke.gd`, replace the body with:

```gdscript
extends TestCase

func test_harness_runs_test_methods() -> void:
	check(true, "harness executes methods prefixed test_")
```

Run the same command. Expected: `checks: 1  failures: 0` and `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add project.godot scenes scripts tests
git commit -m "Add Godot project skeleton and headless test harness"
```

---

## Task 2: Config constants and InputCommand

**Files:**
- Create: `scripts/config.gd`, `scripts/input_command.gd`
- Create: `tests/test_config.gd`
- Modify: `tests/run_tests.gd` (SUITES list)
- Delete: `tests/test_smoke.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_config.gd`:

```gdscript
extends TestCase

func test_speed_band_is_ordered() -> void:
	check(Config.MIN_SPEED < Config.MAX_SPEED, "MIN_SPEED must be below MAX_SPEED")
	check(Config.STALL_SPEED >= Config.MIN_SPEED, "STALL_SPEED must be at or above MIN_SPEED")
	check(Config.STALL_SPEED < Config.MAX_SPEED, "STALL_SPEED must be below MAX_SPEED")

func test_turn_scales_are_fractions() -> void:
	check(Config.MIN_TURN_SCALE > 0.0 and Config.MIN_TURN_SCALE <= 1.0,
		"MIN_TURN_SCALE must be in (0, 1]")
	check(Config.HIGH_SPEED_TURN_FLOOR > 0.0 and Config.HIGH_SPEED_TURN_FLOOR <= 1.0,
		"HIGH_SPEED_TURN_FLOOR must be in (0, 1]")

func test_input_command_defaults_are_finite_and_neutral() -> void:
	var cmd := InputCommand.new()
	check(cmd.aim_dir.is_finite(), "default aim_dir must be finite")
	check_approx(cmd.aim_dir.length(), 1.0, 1e-5, "default aim_dir must be unit length")
	check_approx(cmd.throttle_delta, 0.0, 1e-9, "default throttle_delta must be neutral")
	check_approx(cmd.roll, 0.0, 1e-9, "default roll must be neutral")
	check(not cmd.fire, "default fire must be false")
```

Replace the `SUITES` constant in `tests/run_tests.gd` with:

```gdscript
const SUITES := [
	"res://tests/test_config.gd",
]
```

Delete `tests/test_smoke.gd` — it has served its purpose.

- [ ] **Step 2: Run to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd; echo "exit=$?"
```

Expected: a parse error naming `Config` as an unknown identifier, and `exit=1`.

- [ ] **Step 3: Write the implementation**

`scripts/config.gd`:

```gdscript
class_name Config
extends RefCounted

# --- Flight ---
const MIN_SPEED := 40.0             # m/s at idle throttle
const MAX_SPEED := 180.0            # m/s at full throttle
const STALL_SPEED := 45.0           # m/s below which the nose sags
const THROTTLE_RATE := 0.8          # throttle units per second
const ENGINE_RESPONSE := 0.9        # 1/s, exponential approach to target speed
const GRAVITY := 9.81               # m/s^2

# --- Turning ---
const MAX_TURN_RATE := 1.8          # rad/s at best turn speed
const BEST_TURN_SPEED := 90.0       # m/s
const MIN_TURN_SCALE := 0.25        # turn authority floor when slow
const HIGH_SPEED_TURN_FLOOR := 0.6  # turn authority floor when fast
const AUTO_BANK_GAIN := 2.5         # bank angle per rad/s of yaw
const MAX_BANK := 1.3               # rad, about 75 degrees
const BANK_RESPONSE := 3.0          # 1/s, how fast bank chases its target
const MANUAL_ROLL_RATE := 2.5       # rad/s
const SAG_RATE := 1.2               # rad/s of nose drop at zero speed
const AIM_CONE_DEG := 35.0          # max aim offset from the nose
const GROUND_CLEARANCE := 3.0       # m

# --- World ---
const WORLD_SIZE := 8000.0          # m across
const TERRAIN_RES := 64.0           # m per grid cell
const TERRAIN_MAX_HEIGHT := 900.0   # m
const TERRAIN_SEED := 1337
const TERRAIN_FREQUENCY := 0.0006
const BOUNDARY_SOFT_START := 3600.0 # m from centre
const BOUNDARY_STRENGTH := 2.0      # how hard aim is pulled back inside

# --- Camera ---
const CAM_DIST := 18.0
const CAM_HEIGHT := 6.0
const CAM_LAG := 0.12               # seconds
const CAM_LOOK_AHEAD := 40.0        # m ahead of the nose
const CAM_FOV_MIN := 70.0
const CAM_FOV_MAX := 85.0

# --- Start state ---
const START_ALTITUDE := 600.0
const START_THROTTLE := 0.6
```

`scripts/input_command.gd`:

```gdscript
class_name InputCommand
extends RefCounted

## World-space unit vector the nose should turn toward.
var aim_dir := Vector3.FORWARD
## Rate command, -1..1. Held, not a target position.
var throttle_delta := 0.0
## Manual roll, -1..1. Positive banks right.
var roll := 0.0
var fire := false
```

- [ ] **Step 4: Run to verify it passes**

Expected: `checks: 10  failures: 0`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/config.gd scripts/input_command.gd tests/
git rm tests/test_smoke.gd
git commit -m "Add flight tunables and the shared InputCommand struct"
```

---

## Task 3: Throttle and engine lag

The first real physics. `throttle_delta` is a **rate** — holding `W` spools the engine up — and
speed chases the throttle's target with exponential lag. The lag must use `1 - exp(-k*dt)` so
that a 120 Hz desktop and a 45 Hz phone agree; the third test below is what enforces that.

**Files:**
- Create: `scripts/flight_model.gd`, `tests/test_flight_model.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_flight_model.gd`:

```gdscript
extends TestCase

func test_throttle_rises_at_configured_rate() -> void:
	var fm := FlightModel.new()
	fm.throttle = 0.0
	var cmd := InputCommand.new()
	cmd.throttle_delta = 1.0
	fm.apply_throttle(cmd, 0.5)
	check_approx(fm.throttle, Config.THROTTLE_RATE * 0.5, 1e-6,
		"throttle rises by THROTTLE_RATE * dt")

func test_throttle_clamps_to_unit_range() -> void:
	var fm := FlightModel.new()
	var cmd := InputCommand.new()
	cmd.throttle_delta = 1.0
	for i in 100:
		fm.apply_throttle(cmd, 0.1)
	check_approx(fm.throttle, 1.0, 1e-6, "throttle clamps at 1.0")
	cmd.throttle_delta = -1.0
	for i in 100:
		fm.apply_throttle(cmd, 0.1)
	check_approx(fm.throttle, 0.0, 1e-6, "throttle clamps at 0.0")

func test_speed_approaches_full_throttle_target() -> void:
	var fm := FlightModel.new()
	fm.throttle = 1.0
	fm.speed = Config.MIN_SPEED
	for i in 200:
		fm.apply_engine_lag(0.05)
	check(fm.speed > Config.MAX_SPEED - 1.0, "10s at full throttle reaches near MAX_SPEED")
	check(fm.speed <= Config.MAX_SPEED + 1e-6, "speed never exceeds MAX_SPEED")

func test_engine_lag_is_framerate_independent() -> void:
	var fast := FlightModel.new()
	var slow := FlightModel.new()
	for fm in [fast, slow]:
		fm.throttle = 1.0
		fm.speed = Config.MIN_SPEED
	for i in 120:
		fast.apply_engine_lag(1.0 / 120.0)
	for i in 45:
		slow.apply_engine_lag(1.0 / 45.0)
	check_approx(fast.speed, slow.speed, 0.01,
		"one second of spool-up must not depend on timestep")
```

Add `"res://tests/test_flight_model.gd"` to `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run to verify it fails**

Expected: parse error, `FlightModel` unknown, `exit=1`.

- [ ] **Step 3: Write the implementation**

`scripts/flight_model.gd`:

```gdscript
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
```

- [ ] **Step 4: Run to verify it passes**

Expected: `failures: 0`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/flight_model.gd tests/
git commit -m "Add throttle and framerate-independent engine lag"
```

---

## Task 4: Gravity coupling

One term — `speed -= GRAVITY * forward().y * dt` — supplies most of the felt realism: climb and
you bleed energy, dive and you gain it.

**Files:**
- Modify: `scripts/flight_model.gd`, `tests/test_flight_model.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_flight_model.gd`:

```gdscript
func test_climbing_bleeds_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(30.0))  # nose up 30 degrees
	fm.apply_gravity(1.0)
	check_approx(fm.speed, 100.0 - Config.GRAVITY * 0.5, 0.01,
		"a 30 degree climb bleeds GRAVITY * sin(30) per second")

func test_diving_gains_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(-30.0))  # nose down 30 degrees
	fm.apply_gravity(1.0)
	check_approx(fm.speed, 100.0 + Config.GRAVITY * 0.5, 0.01,
		"a 30 degree dive gains GRAVITY * sin(30) per second")

func test_level_flight_does_not_change_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.apply_gravity(1.0)
	check_approx(fm.speed, 100.0, 1e-6, "level flight is energy neutral")

func test_speed_never_goes_negative() -> void:
	var fm := FlightModel.new()
	fm.speed = 1.0
	fm.basis = Basis(Vector3.RIGHT, deg_to_rad(90.0))  # straight up
	for i in 100:
		fm.apply_gravity(0.1)
	check(fm.speed >= 0.0, "speed must never go negative")
```

- [ ] **Step 2: Run to verify it fails**

Expected: `apply_gravity` not found, `exit=1`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/flight_model.gd`:

```gdscript
func apply_gravity(dt: float) -> void:
	speed = maxf(speed - Config.GRAVITY * forward().y * dt, 0.0)
```

- [ ] **Step 4: Run to verify it passes**

Expected: `failures: 0`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/flight_model.gd tests/test_flight_model.gd
git commit -m "Couple speed to climb and dive angle"
```

---

## Task 5: Turn authority and steering

The nose rotates toward `aim_dir`, clamped by a turn rate that falls off when slow (mushy) and
mildly when very fast. Malformed aim vectors must be ignored, not propagated as NaN through the
basis — once a basis goes NaN the plane is gone for good, so the guard is load-bearing.

**Files:**
- Modify: `scripts/flight_model.gd`, `tests/test_flight_model.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_flight_model.gd`:

```gdscript
func test_turn_rate_peaks_at_best_turn_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	check_approx(fm.turn_rate(), Config.MAX_TURN_RATE, 1e-6,
		"full authority at BEST_TURN_SPEED")

func test_turn_rate_falls_off_when_slow_but_never_to_zero() -> void:
	var fm := FlightModel.new()
	fm.speed = 1.0
	check(fm.turn_rate() < Config.MAX_TURN_RATE, "slow flight is mushy")
	check_approx(fm.turn_rate(), Config.MAX_TURN_RATE * Config.MIN_TURN_SCALE, 1e-6,
		"authority floors at MIN_TURN_SCALE")

func test_turn_rate_falls_off_when_fast() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.MAX_SPEED
	check(fm.turn_rate() < Config.MAX_TURN_RATE, "high speed stiffens the turn")
	check(fm.turn_rate() >= Config.MAX_TURN_RATE * Config.HIGH_SPEED_TURN_FLOOR - 1e-6,
		"authority floors at HIGH_SPEED_TURN_FLOOR")

func test_steering_never_exceeds_turn_rate() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var before := fm.forward()
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.RIGHT
	fm.apply_steering(cmd, 0.1)
	check(before.angle_to(fm.forward()) <= fm.turn_rate() * 0.1 + 1e-5,
		"one step turns at most turn_rate * dt")

func test_steering_converges_on_aim() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3(1.0, 0.0, -1.0).normalized()
	for i in 200:
		fm.apply_steering(cmd, 1.0 / 60.0)
	check(fm.forward().angle_to(cmd.aim_dir) < 0.01, "the nose reaches the aim direction")

func test_steering_ignores_degenerate_aim() -> void:
	var fm := FlightModel.new()
	var before := fm.forward()
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.ZERO
	fm.apply_steering(cmd, 0.1)
	check_approx(before.angle_to(fm.forward()), 0.0, 1e-9, "a zero aim vector is ignored")
	cmd.aim_dir = Vector3(NAN, 0.0, 0.0)
	fm.apply_steering(cmd, 0.1)
	check(fm.forward().is_finite(), "a non-finite aim vector must not corrupt the basis")
```

- [ ] **Step 2: Run to verify it fails**

Expected: `turn_rate` / `apply_steering` not found, `exit=1`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/flight_model.gd`:

```gdscript
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
```

- [ ] **Step 4: Run to verify it passes**

Expected: `failures: 0`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/flight_model.gd tests/test_flight_model.gd
git commit -m "Add speed-dependent turn authority and aim steering"
```

---

## Task 6: Auto-bank and manual roll

A plane that yaws without banking looks broken. Bank is driven to a *target angle* derived from
yaw rate, not integrated as a rate — integrating would spin the plane in a sustained turn.

Sign convention, fixed here and relied on everywhere after: forward is `-Z`, right is `+X`.
Turning right rotates the nose toward `+X`, which is a **negative** rotation about `+Y`, so
`last_yaw_rate` is negative in a right turn. Positive rotation about the forward axis banks
right. Hence `target = -last_yaw_rate * AUTO_BANK_GAIN`.

**Files:**
- Modify: `scripts/flight_model.gd`, `tests/test_flight_model.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_flight_model.gd`:

```gdscript
func test_level_flight_has_no_bank() -> void:
	var fm := FlightModel.new()
	check_approx(fm.bank_angle(), 0.0, 1e-6, "an identity basis is wings level")

func test_right_turn_banks_right() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.RIGHT
	for i in 30:
		fm.apply_steering(cmd, 1.0 / 60.0)
		fm.apply_bank(cmd, 1.0 / 60.0)
	check(fm.bank_angle() > 0.1, "a sustained right turn banks right")

func test_left_turn_banks_left() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.LEFT
	for i in 30:
		fm.apply_steering(cmd, 1.0 / 60.0)
		fm.apply_bank(cmd, 1.0 / 60.0)
	check(fm.bank_angle() < -0.1, "a sustained left turn banks left")

func test_bank_is_clamped() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.BEST_TURN_SPEED
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3.RIGHT
	for i in 600:
		fm.apply_steering(cmd, 1.0 / 60.0)
		fm.apply_bank(cmd, 1.0 / 60.0)
	check(absf(fm.bank_angle()) <= Config.MAX_BANK + 0.05, "bank never exceeds MAX_BANK")

func test_manual_roll_rolls() -> void:
	var fm := FlightModel.new()
	var cmd := InputCommand.new()
	cmd.roll = 1.0
	fm.apply_bank(cmd, 0.1)
	check(fm.bank_angle() > 0.0, "positive roll input banks right")
```

- [ ] **Step 2: Run to verify it fails**

Expected: `bank_angle` / `apply_bank` not found, `exit=1`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/flight_model.gd`:

```gdscript
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
	var correction := clampf((target - bank_angle()) * Config.BANK_RESPONSE,
		-Config.MANUAL_ROLL_RATE, Config.MANUAL_ROLL_RATE)
	var rate := cmd.roll * Config.MANUAL_ROLL_RATE + correction
	if absf(rate) < 1e-9:
		return
	basis = (Basis(forward(), rate * dt) * basis).orthonormalized()
```

- [ ] **Step 4: Run to verify it passes**

Expected: `failures: 0`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/flight_model.gd tests/test_flight_model.gd
git commit -m "Bank into turns automatically and accept manual roll"
```

---

## Task 7: Stall sag and recovery

Below `STALL_SPEED` the nose drops in proportion to how far below it you are. Diving then buys
speed back, which lifts the nose authority again. There is no spin and no unrecoverable state —
the last test proves recovery actually terminates rather than oscillating forever.

**Files:**
- Modify: `scripts/flight_model.gd`, `tests/test_flight_model.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_flight_model.gd`:

```gdscript
func test_stall_drops_the_nose() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.STALL_SPEED * 0.5
	fm.apply_stall_sag(0.5)
	check(fm.forward().y < -0.01, "below stall speed the nose pitches down")

func test_no_sag_above_stall_speed() -> void:
	var fm := FlightModel.new()
	fm.speed = Config.STALL_SPEED + 1.0
	fm.apply_stall_sag(0.5)
	check_approx(fm.forward().y, 0.0, 1e-9, "above stall speed the nose is untouched")

func test_stall_recovery_terminates() -> void:
	var fm := FlightModel.new()
	fm.speed = 5.0
	fm.throttle = 1.0
	var cmd := InputCommand.new()
	var recovered := false
	for i in 1200:  # 20 seconds
		cmd.aim_dir = fm.forward()
		fm.step(cmd, 1.0 / 60.0)
		if fm.speed > Config.STALL_SPEED:
			recovered = true
			break
	check(recovered, "a deep stall recovers within 20 seconds")
	check(fm.basis.is_finite(), "the basis stays finite through a stall")
```

`test_stall_recovery_terminates` calls `step()`, which Task 8 adds. Expect it to fail on the
missing method until then; that is intentional, since recovery is only meaningful for the whole
integrator.

- [ ] **Step 2: Run to verify it fails**

Expected: `apply_stall_sag` not found, `exit=1`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/flight_model.gd`:

```gdscript
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
```

- [ ] **Step 4: Run to verify it passes (except the step() test)**

Expected: the two sag tests pass; `test_stall_recovery_terminates` still fails on the missing
`step()`. Task 8 closes it.

- [ ] **Step 5: Commit**

```bash
git add scripts/flight_model.gd tests/test_flight_model.gd
git commit -m "Add forgiving stall sag below minimum flying speed"
```

---

## Task 8: step() and trajectory framerate independence

`step()` fixes the order the terms are applied in, then integrates position.

On tolerance: the spec asked for an *identical* trajectory across timesteps. That is not
achievable — a first-order integrator with a clamped turn rate takes a marginally different path
at a different `dt`. The test instead pins **heading** to near-exact agreement and **position**
to within 2% of distance travelled. A `k*dt` smoothing bug, which is what this test exists to
catch, diverges by far more than 2%.

**Files:**
- Modify: `scripts/flight_model.gd`, `tests/test_flight_model.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_flight_model.gd`:

```gdscript
func _fly(dt: float, seconds: float) -> FlightModel:
	var fm := FlightModel.new()
	fm.speed = 100.0
	fm.throttle = 0.6
	var cmd := InputCommand.new()
	cmd.aim_dir = Vector3(0.3, 0.1, -1.0).normalized()
	for i in int(round(seconds / dt)):
		fm.step(cmd, dt)
	return fm

func test_step_moves_the_plane_forward() -> void:
	var fm := FlightModel.new()
	fm.speed = 100.0
	var cmd := InputCommand.new()
	cmd.aim_dir = fm.forward()
	fm.step(cmd, 0.1)
	check(fm.position.z < -9.0, "the plane advances along its nose (-Z)")

func test_trajectory_is_framerate_independent() -> void:
	var fast := _fly(1.0 / 120.0, 3.0)
	var slow := _fly(1.0 / 45.0, 3.0)
	check(fast.forward().angle_to(slow.forward()) < 0.01,
		"final heading must not depend on timestep")
	var path := fast.position.length()
	check(fast.position.distance_to(slow.position) <= 0.02 * path,
		"final position must agree within 2 percent of distance travelled")

func test_state_stays_finite_under_long_simulation() -> void:
	var fm := FlightModel.new()
	var cmd := InputCommand.new()
	for i in 3600:  # one minute of hard turning
		cmd.aim_dir = Vector3(sin(i * 0.01), 0.2, -1.0)
		fm.step(cmd, 1.0 / 60.0)
	check(fm.position.is_finite(), "position stays finite")
	check(fm.basis.is_finite(), "basis stays finite")
	check(fm.speed >= 0.0 and fm.speed <= Config.MAX_SPEED + 1.0, "speed stays in band")
```

- [ ] **Step 2: Run to verify it fails**

Expected: `step` not found, `exit=1`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/flight_model.gd`:

```gdscript
func step(cmd: InputCommand, dt: float) -> void:
	apply_throttle(cmd, dt)
	apply_engine_lag(dt)
	apply_gravity(dt)
	apply_steering(cmd, dt)
	apply_bank(cmd, dt)
	apply_stall_sag(dt)
	position += forward() * speed * dt
```

- [ ] **Step 4: Run to verify it passes**

Expected: `failures: 0`, `exit=0`. The Task 7 recovery test now passes too. **The flight model
is complete and fully tested at this point** — everything after this is presentation.

- [ ] **Step 5: Commit**

```bash
git add scripts/flight_model.gd tests/test_flight_model.gd
git commit -m "Complete the flight integrator with a framerate-independence guard"
```

---

## Task 9: Terrain

Noise heightmap with a radial falloff so the landmass becomes an island and the edges sink into
sea. `height_at()` is initialised in `_init()` rather than `_ready()` so it can be tested without
a scene tree.

**Files:**
- Create: `scripts/terrain.gd`, `tests/test_terrain.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_terrain.gd`:

```gdscript
extends TestCase

## Terrain extends Node3D, which is not reference-counted. Every test frees its
## instances, otherwise Godot prints "ObjectDB instances leaked at exit" and the
## run looks broken when it is not.

func test_height_is_within_bounds_everywhere() -> void:
	var terrain := Terrain.new()
	var half := Config.WORLD_SIZE * 0.5
	for i in 200:
		var x := randf_range(-half, half)
		var z := randf_range(-half, half)
		var h := terrain.height_at(x, z)
		check(h >= 0.0 and h <= Config.TERRAIN_MAX_HEIGHT,
			"height at (%.0f, %.0f) is inside [0, TERRAIN_MAX_HEIGHT]" % [x, z])
	terrain.free()

func test_world_edge_is_at_sea_level() -> void:
	var terrain := Terrain.new()
	var half := Config.WORLD_SIZE * 0.5
	check_approx(terrain.height_at(half, 0.0), 0.0, 1e-6, "the east edge is sea")
	check_approx(terrain.height_at(0.0, -half), 0.0, 1e-6, "the north edge is sea")
	terrain.free()

func test_height_is_deterministic_for_a_seed() -> void:
	var a := Terrain.new()
	var b := Terrain.new()
	check_approx(a.height_at(120.0, -340.0), b.height_at(120.0, -340.0), 1e-6,
		"the same seed gives the same terrain")
	a.free()
	b.free()
```

Add `"res://tests/test_terrain.gd"` to `SUITES`.

- [ ] **Step 2: Run to verify it fails**

Expected: `Terrain` unknown, `exit=1`.

- [ ] **Step 3: Write the implementation**

`scripts/terrain.gd`:

```gdscript
class_name Terrain
extends Node3D

var _noise := FastNoiseLite.new()

func _init() -> void:
	_noise.seed = Config.TERRAIN_SEED
	_noise.frequency = Config.TERRAIN_FREQUENCY

func height_at(x: float, z: float) -> float:
	var n := (_noise.get_noise_2d(x, z) + 1.0) * 0.5          # 0..1
	var r := Vector2(x, z).length() / (Config.WORLD_SIZE * 0.5)
	var falloff := clampf(1.0 - r * r, 0.0, 1.0)              # island edges sink to sea
	return n * falloff * Config.TERRAIN_MAX_HEIGHT

func _ready() -> void:
	add_child(_build_land())
	add_child(_build_sea())

func _build_land() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Config.WORLD_SIZE * 0.5
	var cells := int(Config.WORLD_SIZE / Config.TERRAIN_RES)
	for i in cells:
		for j in cells:
			var x0 := -half + i * Config.TERRAIN_RES
			var z0 := -half + j * Config.TERRAIN_RES
			var x1 := x0 + Config.TERRAIN_RES
			var z1 := z0 + Config.TERRAIN_RES
			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x1, height_at(x1, z0), z0)
			var c := Vector3(x1, height_at(x1, z1), z1)
			var d := Vector3(x0, height_at(x0, z1), z1)
			_add_tri(st, a, b, c)
			_add_tri(st, a, c, d)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	st.set_material(material)
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	return instance

func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal  # land always faces up, whatever the winding
	var color := _color_for_height((a.y + b.y + c.y) / 3.0)
	for v in [a, b, c]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(v)

func _color_for_height(h: float) -> Color:
	var t := h / Config.TERRAIN_MAX_HEIGHT
	if t < 0.05:
		return Color(0.76, 0.70, 0.50)              # sand
	if t < 0.45:
		return Color(0.24, 0.42, 0.20).lerp(Color(0.34, 0.50, 0.24), t / 0.45)
	if t < 0.75:
		return Color(0.42, 0.38, 0.34)              # rock
	return Color(0.92, 0.92, 0.95)                  # snow

func _build_sea() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(Config.WORLD_SIZE * 1.5, Config.WORLD_SIZE * 1.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.22, 0.38)
	material.metallic = 0.3
	material.roughness = 0.25
	plane.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	return instance
```

- [ ] **Step 4: Run to verify it passes**

Expected: `failures: 0`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/terrain.gd tests/
git commit -m "Generate island terrain from noise with a queryable heightmap"
```

---

## Task 10: Aircraft node and jet visual

`aircraft.gd` is the only glue between the pure model and the scene tree. It pulls a command from
whatever object is assigned as its `controller` — the same seam an AI pilot will use in Phase 2 —
and performs the ground test the spec put inside the model.

**Files:**
- Create: `scripts/aircraft.gd`, `scripts/jet_visual.gd`, `scenes/aircraft.tscn`

- [ ] **Step 1: Write `scripts/aircraft.gd`**

```gdscript
class_name Aircraft
extends Node3D

signal crashed

var model := FlightModel.new()
## Any object with: command(aircraft: Aircraft, dt: float) -> InputCommand
var controller: Object = null
var terrain: Terrain = null

func _physics_process(delta: float) -> void:
	if controller == null:
		return
	model.step(controller.command(self, delta), delta)
	global_position = model.position
	global_transform.basis = model.basis
	if terrain == null:
		return
	var ground := terrain.height_at(model.position.x, model.position.z)
	if model.position.y < ground + Config.GROUND_CLEARANCE:
		crashed.emit()

func reset(start_position: Vector3) -> void:
	model = FlightModel.new()
	model.position = start_position
	global_position = start_position
	global_transform.basis = Basis.IDENTITY
```

- [ ] **Step 2: Write `scripts/jet_visual.gd`**

Geometry only. Replacing this node with an imported glTF scene is the entire asset-swap path.
Forward is `-Z`, so the nose points at negative Z.

```gdscript
extends Node3D

const BODY := Color(0.62, 0.65, 0.70)
const WING := Color(0.45, 0.48, 0.54)
const CANOPY := Color(0.15, 0.22, 0.30)

func _ready() -> void:
	_add_box(Vector3(1.2, 1.0, 7.0), Vector3(0.0, 0.0, 0.0), BODY)      # fuselage
	_add_box(Vector3(9.0, 0.25, 1.6), Vector3(0.0, -0.1, 0.5), WING)    # main wing
	_add_box(Vector3(3.4, 0.22, 0.9), Vector3(0.0, 0.0, 2.9), WING)     # tailplane
	_add_box(Vector3(0.22, 1.6, 1.2), Vector3(0.0, 0.9, 3.0), WING)     # fin
	_add_box(Vector3(0.9, 0.6, 1.8), Vector3(0.0, 0.62, -1.2), CANOPY)  # canopy

func _add_box(size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	add_child(instance)
```

- [ ] **Step 3: Write `scenes/aircraft.tscn`**

```ini
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/aircraft.gd" id="1_aircraft"]
[ext_resource type="Script" path="res://scripts/jet_visual.gd" id="2_visual"]

[node name="Aircraft" type="Node3D"]
script = ExtResource("1_aircraft")

[node name="Visual" type="Node3D" parent="."]
script = ExtResource("2_visual")
```

- [ ] **Step 4: Verify the project still parses**

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd; echo "exit=$?"
```

Expected: `failures: 0`, `exit=0`, with no parse errors for the new scripts.

- [ ] **Step 5: Commit**

```bash
git add scripts/aircraft.gd scripts/jet_visual.gd scenes/aircraft.tscn
git commit -m "Add the aircraft node and its swappable primitive jet visual"
```

---

## Task 11: Chase camera

**Files:**
- Create: `scripts/chase_camera.gd`

- [ ] **Step 1: Write `scripts/chase_camera.gd`**

`target.global_transform.basis.z` is the plane's *backward* axis (forward is `-Z`), so adding it
places the camera behind. Lag uses the same `1 - exp(-dt/tau)` form as the flight model, so the
camera does not judder at a different framerate.

```gdscript
class_name ChaseCamera
extends Camera3D

var target: Aircraft = null

func _process(delta: float) -> void:
	if target == null:
		return
	var t := target.global_transform
	var desired := t.origin + t.basis.z * Config.CAM_DIST + t.basis.y * Config.CAM_HEIGHT
	global_position = global_position.lerp(desired, 1.0 - exp(-delta / Config.CAM_LAG))
	look_at(t.origin - t.basis.z * Config.CAM_LOOK_AHEAD, t.basis.y)
	var speed_t := clampf(
		(target.model.speed - Config.MIN_SPEED) / (Config.MAX_SPEED - Config.MIN_SPEED),
		0.0, 1.0)
	fov = lerpf(Config.CAM_FOV_MIN, Config.CAM_FOV_MAX, speed_t)

func snap_to_target() -> void:
	if target == null:
		return
	var t := target.global_transform
	global_position = t.origin + t.basis.z * Config.CAM_DIST + t.basis.y * Config.CAM_HEIGHT
	look_at(t.origin - t.basis.z * Config.CAM_LOOK_AHEAD, t.basis.y)
```

`snap_to_target()` exists so a restart does not send the camera sailing across the map.

- [ ] **Step 2: Verify the project still parses**

Run the test command. Expected: `failures: 0`, `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add scripts/chase_camera.gd
git commit -m "Add a lagging chase camera with speed-driven field of view"
```

---

## Task 12: Player controller (desktop)

Keys are read directly rather than through an InputMap: Phase 1 has no remapping requirement, and
a hand-written InputMap in `project.godot` is brittle to author.

Sign derivation, so nobody has to re-derive it: mouse right gives `offset.x > 0` and must turn
right, which is a negative rotation about the plane's up axis. Mouse down gives `offset.y > 0`
(screen Y grows downward) and must pitch down, which is a negative rotation about the plane's
right axis. Both therefore take a leading minus.

**Files:**
- Create: `scripts/player_controller.gd`

- [ ] **Step 1: Write `scripts/player_controller.gd`**

```gdscript
class_name PlayerController
extends Node

func command(aircraft: Aircraft, _dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.aim_dir = _aim_from_pointer(aircraft, _pointer_offset(aircraft))
	var throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	cmd.throttle_delta = throttle
	var roll := 0.0
	if Input.is_key_pressed(KEY_D):
		roll += 1.0
	if Input.is_key_pressed(KEY_A):
		roll -= 1.0
	cmd.roll = roll
	cmd.fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	return cmd

## Pointer position as -1..1 from screen centre.
func _pointer_offset(aircraft: Aircraft) -> Vector2:
	var viewport := aircraft.get_viewport()
	var size := viewport.get_visible_rect().size
	if size.y < 1.0:
		return Vector2.ZERO
	var centred := viewport.get_mouse_position() - size * 0.5
	return (centred / (size.y * 0.5)).limit_length(1.0)

func _aim_from_pointer(aircraft: Aircraft, offset: Vector2) -> Vector3:
	var b := aircraft.model.basis
	var cone := deg_to_rad(Config.AIM_CONE_DEG)
	var aim := -b.z
	aim = aim.rotated(b.y, -offset.x * cone)
	aim = aim.rotated(b.x, -offset.y * cone)
	return aim
```

- [ ] **Step 2: Verify the project still parses**

Run the test command. Expected: `failures: 0`, `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add scripts/player_controller.gd
git commit -m "Add desktop mouse-aim and keyboard flight controls"
```

---

## Task 13: Assemble the world, crash and restart

First playable. `game.gd` builds everything, wires the crash signal, and restarts.

A `DirectionalLight3D` and a `WorldEnvironment` with a procedural sky are mandatory — without
them the scene renders black and the terrain work looks broken when it is not.

**Files:**
- Modify: `scripts/game.gd`

- [ ] **Step 1: Write `scripts/game.gd`**

```gdscript
extends Node3D

var terrain: Terrain
var aircraft: Aircraft
var camera: ChaseCamera
var controller: PlayerController

func _ready() -> void:
	_build_environment()
	terrain = Terrain.new()
	add_child(terrain)
	controller = PlayerController.new()
	add_child(controller)
	aircraft = preload("res://scenes/aircraft.tscn").instantiate()
	aircraft.controller = controller
	aircraft.terrain = terrain
	aircraft.crashed.connect(_on_crashed)
	add_child(aircraft)
	camera = ChaseCamera.new()
	camera.target = aircraft
	camera.far = Config.WORLD_SIZE
	camera.current = true
	add_child(camera)
	_restart()

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.45, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.82, 0.90)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.fog_enabled = true
	environment.fog_density = 0.0004
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func _restart() -> void:
	aircraft.reset(Vector3(0.0, Config.START_ALTITUDE, Config.WORLD_SIZE * 0.25))
	aircraft.model.throttle = Config.START_THROTTLE
	aircraft.model.speed = lerpf(Config.MIN_SPEED, Config.MAX_SPEED, Config.START_THROTTLE)
	camera.snap_to_target()

func _on_crashed() -> void:
	_restart()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

## Spec section 14: the game pauses on focus loss. PROCESS_MODE_ALWAYS keeps this
## node running while the tree is paused, so it can unpause itself on focus return.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		get_tree().paused = false
```

Add this as the first line of `_ready()`:

```gdscript
	process_mode = Node.PROCESS_MODE_ALWAYS
```

- [ ] **Step 2: Run the game and fly it**

```bash
"$GODOT" --path . 
```

Verify by hand, then close the window (`Esc`):

- The sky renders and the island is visible below
- The jet is visible ahead of the camera and the camera trails it
- Mouse steers; `W`/`S` visibly change speed; `A`/`D` roll
- Flying into a hill restarts you in the air rather than freezing or falling through
- Clicking away to another window freezes the plane; returning resumes it

- [ ] **Step 3: Confirm no Godot process is left running**

```bash
powershell -c "Get-Process Godot* -ErrorAction SilentlyContinue | Select-Object Id,ProcessName"
```

Expected: no output. If any remain, stop them before continuing.

- [ ] **Step 4: Commit**

```bash
git add scripts/game.gd
git commit -m "Assemble the flyable world with lighting, sky, crash and restart"
```

---

## Task 14: HUD

**Files:**
- Create: `scripts/hud.gd`, `scenes/hud.tscn`
- Modify: `scripts/game.gd`

- [ ] **Step 1: Write `scripts/hud.gd`**

The horizon and reticle are drawn in `_draw()`; numbers are drawn with the same call so there is
only one font and one redraw path.

```gdscript
class_name HUD
extends Control

const HUD_COLOR := Color(0.85, 1.0, 0.85, 0.9)

var target: Aircraft = null
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if target == null:
		return
	var centre := size * 0.5
	_draw_reticle(centre)
	_draw_horizon(centre)
	_draw_readouts()

func _draw_reticle(centre: Vector2) -> void:
	draw_arc(centre, 14.0, 0.0, TAU, 32, HUD_COLOR, 2.0)
	draw_line(centre + Vector2(-26.0, 0.0), centre + Vector2(-16.0, 0.0), HUD_COLOR, 2.0)
	draw_line(centre + Vector2(16.0, 0.0), centre + Vector2(26.0, 0.0), HUD_COLOR, 2.0)

func _draw_horizon(centre: Vector2) -> void:
	var fwd := target.model.forward()
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	var bank := target.model.bank_angle()
	var offset := -pitch / deg_to_rad(45.0) * (size.y * 0.35)
	var direction := Vector2(cos(bank), sin(bank))
	var mid := centre + Vector2(0.0, offset)
	var half := direction * (size.x * 0.22)
	draw_line(mid - half, mid - half * 0.25, HUD_COLOR, 2.0)
	draw_line(mid + half * 0.25, mid + half, HUD_COLOR, 2.0)

func _draw_readouts() -> void:
	var model := target.model
	_text(Vector2(28.0, size.y * 0.5), "SPD %4d" % int(round(model.speed)))
	_text(Vector2(size.x - 130.0, size.y * 0.5), "ALT %5d" % int(round(model.position.y)))
	_text(Vector2(28.0, size.y - 40.0), "THR %3d%%" % int(round(model.throttle * 100.0)))

func _text(at: Vector2, content: String) -> void:
	draw_string(_font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, HUD_COLOR)
```

- [ ] **Step 2: Write `scenes/hud.tscn`**

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/hud.gd" id="1_hud"]

[node name="HUDLayer" type="CanvasLayer"]

[node name="HUD" type="Control" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_hud")
```

- [ ] **Step 3: Wire it into `scripts/game.gd`**

Add a field beside the others:

```gdscript
var hud: HUD
```

and, at the end of `_ready()` just before `_restart()`:

```gdscript
	var hud_layer := preload("res://scenes/hud.tscn").instantiate()
	add_child(hud_layer)
	hud = hud_layer.get_node("HUD")
	hud.target = aircraft
```

- [ ] **Step 4: Run and verify by hand**

```bash
"$GODOT" --path .
```

- Speed, altitude and throttle read plausibly and change as you fly
- The horizon line rotates opposite to your bank and slides with pitch
- The reticle sits at screen centre

Close the window, then confirm no Godot process remains (Task 13 Step 3 command).

- [ ] **Step 5: Commit**

```bash
git add scripts/hud.gd scenes/hud.tscn scripts/game.gd
git commit -m "Add HUD with speed, altitude, throttle, horizon and reticle"
```

---

## Task 15: Touch controls

A floating stick spawns where the left half of the screen is first touched; the right side holds
a throttle slider and a fire button. `Config.FORCE_TOUCH_UI` lets the layout be exercised on a
desktop, which is the only way to check it before the Android toolchain exists.

**Files:**
- Create: `scripts/touch_controls.gd`
- Modify: `scripts/config.gd`, `scripts/player_controller.gd`, `scripts/game.gd`

- [ ] **Step 1: Add the flag to `scripts/config.gd`**

```gdscript
# --- Input ---
const FORCE_TOUCH_UI := false     # set true to exercise the touch layout on desktop
const TOUCH_STICK_RADIUS := 110.0 # px of drag for full deflection
```

- [ ] **Step 2: Write `scripts/touch_controls.gd`**

```gdscript
class_name TouchControls
extends Control

const UI_COLOR := Color(1.0, 1.0, 1.0, 0.35)

var aim := Vector2.ZERO        # -1..1, read by PlayerController
var throttle_delta := 0.0      # -1..1
var fire := false

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_current := Vector2.ZERO

static func is_active() -> bool:
	return Config.FORCE_TOUCH_UI or DisplayServer.is_touchscreen_available()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		_stick_current = event.position
		aim = ((_stick_current - _stick_origin) / Config.TOUCH_STICK_RADIUS).limit_length(1.0)

func _handle_touch(event: InputEventScreenTouch) -> void:
	var on_left := event.position.x < size.x * 0.5
	if event.pressed and on_left and _stick_touch == -1:
		_stick_touch = event.index
		_stick_origin = event.position
		_stick_current = event.position
		aim = Vector2.ZERO
	elif event.pressed and not on_left:
		_press_right(event.position)
	elif not event.pressed:
		if event.index == _stick_touch:
			_stick_touch = -1
			aim = Vector2.ZERO
		else:
			throttle_delta = 0.0
			fire = false

func _press_right(at: Vector2) -> void:
	if at.y < size.y * 0.5:
		throttle_delta = 1.0
	elif at.x > size.x * 0.8:
		fire = true
	else:
		throttle_delta = -1.0

func _draw() -> void:
	if _stick_touch != -1:
		draw_arc(_stick_origin, Config.TOUCH_STICK_RADIUS, 0.0, TAU, 40, UI_COLOR, 2.0)
		draw_circle(_stick_current, 26.0, UI_COLOR)
	var right := size.x * 0.78
	draw_rect(Rect2(right, size.y * 0.18, 64.0, size.y * 0.30), UI_COLOR, false, 2.0)
	draw_rect(Rect2(right, size.y * 0.52, 64.0, size.y * 0.30), UI_COLOR, false, 2.0)
	draw_circle(Vector2(size.x * 0.90, size.y * 0.80), 44.0, UI_COLOR)
```

- [ ] **Step 3: Teach `PlayerController` to read it**

In `scripts/player_controller.gd`, add a field and prefer touch when it is present:

```gdscript
var touch: TouchControls = null
```

Replace the body of `command()` with:

```gdscript
func command(aircraft: Aircraft, _dt: float) -> InputCommand:
	var cmd := InputCommand.new()
	if touch != null:
		cmd.aim_dir = _aim_from_pointer(aircraft, touch.aim)
		cmd.throttle_delta = touch.throttle_delta
		cmd.roll = touch.aim.x * 0.5   # the stick banks as it steers
		cmd.fire = touch.fire
		return cmd
	cmd.aim_dir = _aim_from_pointer(aircraft, _pointer_offset(aircraft))
	var throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	cmd.throttle_delta = throttle
	var roll := 0.0
	if Input.is_key_pressed(KEY_D):
		roll += 1.0
	if Input.is_key_pressed(KEY_A):
		roll -= 1.0
	cmd.roll = roll
	cmd.fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)
	return cmd
```

- [ ] **Step 4: Wire it into `scripts/game.gd`**

After the HUD wiring in `_ready()`:

```gdscript
	if TouchControls.is_active():
		var touch := TouchControls.new()
		hud_layer.add_child(touch)
		controller.touch = touch
```

- [ ] **Step 5: Verify both layouts**

Run with `FORCE_TOUCH_UI = false`: mouse and keys fly the plane, no touch overlay is drawn.

Set `FORCE_TOUCH_UI = true` in `scripts/config.gd`, run again, and confirm the overlay draws.
Godot emulates touch from mouse when **Project Settings > Input Devices > Pointing >
Emulate Touch From Mouse** is enabled; turn it on to drive the stick with the mouse.

Set `FORCE_TOUCH_UI` back to `false` before committing.

- [ ] **Step 6: Commit**

```bash
git add scripts/touch_controls.gd scripts/player_controller.gd scripts/config.gd scripts/game.gd
git commit -m "Add touch flight controls with a desktop override for testing"
```

---

## Task 16: Soft world boundary

Past `BOUNDARY_SOFT_START` the aim direction is blended toward the world centre, increasingly
hard, so the player is turned around instead of hitting an invisible wall. It is a pure function,
so it is tested.

**Files:**
- Create: `scripts/boundary.gd`, `tests/test_boundary.gd`
- Modify: `tests/run_tests.gd`, `scripts/player_controller.gd`

- [ ] **Step 1: Write the failing test**

`tests/test_boundary.gd`:

```gdscript
extends TestCase

func test_inside_the_boundary_aim_is_untouched() -> void:
	var aim := Vector3(0.0, 0.0, -1.0)
	var result := Boundary.constrain(aim, Vector3.ZERO)
	check_approx(result.angle_to(aim), 0.0, 1e-6, "aim is unchanged at the world centre")

func test_outside_the_boundary_aim_bends_inward() -> void:
	var outward := Vector3(1.0, 0.0, 0.0)
	var far_east := Vector3(Config.WORLD_SIZE * 0.5, 500.0, 0.0)
	var result := Boundary.constrain(outward, far_east)
	check(result.x < outward.x, "aim bends back toward the centre when far out")

func test_constrain_always_returns_a_usable_vector() -> void:
	var far := Vector3(Config.WORLD_SIZE, 500.0, Config.WORLD_SIZE)
	var result := Boundary.constrain(Vector3(1.0, 0.0, 1.0).normalized(), far)
	check(result.is_finite(), "result is finite")
	check(result.length_squared() > 1e-6, "result is not degenerate")
```

Add `"res://tests/test_boundary.gd"` to `SUITES`.

- [ ] **Step 2: Run to verify it fails**

Expected: `Boundary` unknown, `exit=1`.

- [ ] **Step 3: Write the implementation**

`scripts/boundary.gd`:

```gdscript
class_name Boundary
extends RefCounted

## Bends aim back toward the world centre once the plane is past the soft boundary.
static func constrain(aim: Vector3, position: Vector3) -> Vector3:
	var flat := Vector2(position.x, position.z)
	var distance := flat.length()
	if distance <= Config.BOUNDARY_SOFT_START:
		return aim
	var span := maxf(Config.WORLD_SIZE * 0.5 - Config.BOUNDARY_SOFT_START, 1.0)
	var strength := clampf((distance - Config.BOUNDARY_SOFT_START) / span, 0.0, 1.0)
	strength = clampf(strength * Config.BOUNDARY_STRENGTH, 0.0, 1.0)
	var inward := Vector3(-position.x, 0.0, -position.z).normalized()
	var blended := aim.lerp(inward, strength)
	if not blended.is_finite() or blended.length_squared() < 1e-6:
		return inward
	return blended.normalized()
```

- [ ] **Step 4: Apply it in `scripts/player_controller.gd`**

In `command()`, wrap both assignments to `cmd.aim_dir`:

```gdscript
	cmd.aim_dir = Boundary.constrain(_aim_from_pointer(aircraft, touch.aim), aircraft.model.position)
```

and

```gdscript
	cmd.aim_dir = Boundary.constrain(
		_aim_from_pointer(aircraft, _pointer_offset(aircraft)), aircraft.model.position)
```

- [ ] **Step 5: Run to verify it passes**

Expected: `failures: 0`, `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/boundary.gd scripts/player_controller.gd tests/
git commit -m "Turn the player back at the world edge instead of walling them"
```

---

## Task 17: Phase 1 acceptance

Phase 1 is done, and Phase 2 may start, only when every box below is ticked.

**Files:** none created.

- [ ] **Step 1: Full automated run**

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd; echo "exit=$?"
```

Expected: `failures: 0`, `exit=0`, covering config, flight model, terrain and boundary.

- [ ] **Step 2: Manual flight checklist**

```bash
"$GODOT" --path .
```

- [ ] Level flight with the mouse at screen centre holds altitude with no drift
- [ ] A full loop completes without losing orientation or control
- [ ] Throttle produces a felt difference: slow is mushy, fast is stiff
- [ ] Terrain contact restarts cleanly in the air
- [ ] The world edge turns you back rather than stopping you
- [ ] HUD speed, altitude, throttle and horizon all track reality
- [ ] With `FORCE_TOUCH_UI = true` and mouse touch emulation on, the touch layout flies the plane
- [ ] Holds 60 fps (check with **Debug > Visible Profiler**, or Godot's `--print-fps`)

- [ ] **Step 3: Confirm no process is left behind**

```bash
powershell -c "Get-Process Godot* -ErrorAction SilentlyContinue | Select-Object Id,ProcessName"
```

Expected: no output.

- [ ] **Step 4: Tag and push**

```bash
git tag -a phase1-flight -m "Phase 1: flight complete"
git push origin main --tags
```

---

## Deferred to Phase 2

Weapons, bullets and hit detection · `AIPilot` and its state machine · `WaveDirector` · scoring,
combo and high score · rigid-body debris · health and damage · HUD health/score/off-screen
indicator. All of it consumes `InputCommand` and `FlightModel` unchanged.
