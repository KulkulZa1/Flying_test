# Flying — Arcade Dogfighter

**Date:** 2026-09-19
**Status:** Approved design, ready for implementation planning
**Engine:** Godot 4 (GDScript)
**Targets:** Windows desktop first, Android APK second

---

## 1. Summary

A single-player arcade flight game with gun dogfighting. The player flies a jet over a
procedurally generated island region, fights escalating waves of AI fighters, and chases a
high score. Flight is arcade-forgiving, not a study sim: no spins, no procedures, instant
readability.

Built in two phases. **Phase 1 delivers flying** — the flight model, world, camera, controls
and HUD, tuned until it feels good on its own. **Phase 2 adds combat** on top of that
foundation. Combat is not started until the Phase 1 acceptance criteria are met.

---

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Genre | Arcade flight + gun dogfighting | Fun-first; readable on both a mouse and a thumb |
| Opponents | AI only in v1 | No server, no netcode, no lobbies; runs offline |
| Multiplayer | Structural seam only | `InputCommand` + serializable state; **no networking code written** |
| Engine | Godot 4 | Real 3D physics, native Windows and Android exports |
| Mobile delivery | Android APK, toolchain set up later | Touch designed in from day one; JDK/SDK setup deferred |
| Controls | Aim-to-steer | One control law serves mouse and touch equally |
| Loop | Endless waves + score | One complete replayable loop, no level design |
| Art | Code-generated primitives, swappable | Nothing blocks on assets; CC0 models can drop in later |
| Flight physics | Kinematic planes + rigid-body debris | Deterministic and testable where it is control; physics where it is decoration |
| Audio | Silent in v1 | No audio assets available; playback points left obvious |

### The multiplayer seam — what it is and is not

Both the player controller and every AI pilot emit the same struct:

```gdscript
class InputCommand:
    var aim_dir: Vector3      # unit vector, world space, clamped to a cone off the nose
    var throttle_delta: float # -1..1
    var roll: float           # -1..1
    var fire: bool
```

Both feed the identical `FlightModel.step()`. The AI requires that struct today regardless of
multiplayer, so it is not speculative flexibility. It happens to be exactly what would go on a
wire later. **No network abstraction, transport layer, or serialization format is built in v1.**

---

## 3. Non-goals for v1

No netcode · no missions or campaign · no ground targets or SAMs · no missiles (guns only) ·
no aircraft selection, unlocks or progression · no runway takeoff and landing procedures ·
no audio · no infinite terrain streaming · no weather or day/night cycle.

---

## 4. Architecture

The simulation is separated from the presentation. `flight_model.gd` is plain GDScript math
over a state object and never touches a node, so it runs headless under test. Everything else
is Godot nodes that read simulation state and draw it.

**Per 60 Hz physics tick:**

1. `PlayerController` reads mouse/keys or touch, emits an `InputCommand`
2. Each `AIPilot` emits an `InputCommand` for its own plane
3. Each `Aircraft` steps its `FlightModel` and applies the resulting transform
4. `Weapon` spawns bullets on `fire` (kinematic, raycast-swept between frames so they cannot
   tunnel through a target at closing speed)
5. Hits apply damage; death spawns rigid-body debris that frees itself after a lifetime
6. `WaveDirector` sees the sky is clear and sends the next wave
7. `HUD` renders from game state

---

## 5. File layout

```
project.godot
docs/superpowers/specs/          this document
scripts/
  config.gd                      every tunable constant, one file
  flight_model.gd                pure math, no nodes, headless-testable
  aircraft.gd                    node glue: state to transform, hosts visual + collider
  player_controller.gd           mouse/keys/touch to InputCommand
  ai_pilot.gd                    state machine to InputCommand
  weapon.gd                      firing, cooldown, bullet spawn
  wave_director.gd               wave composition and difficulty curve
  terrain.gd                     procedural mesh from noise
  game.gd                        score, death, restart, high score
scenes/
  main.tscn                      game root, wiring
  aircraft.tscn                  flight model + visual slot + collider
  hud.tscn                       instruments, reticle, touch controls
  bullet.tscn
  debris.tscn                    RigidBody3D chunk
  visuals/jet_player.tscn        geometry only — the swappable slot
  visuals/jet_enemy.tscn
tests/
  run_tests.gd                   headless assert runner
  test_flight_model.gd
  test_ai_pilot.gd
  test_wave_director.gd
  test_scoring.gd
```

The files under `visuals/` contain geometry and nothing else, so a downloaded glTF model can
replace a primitive jet without any other file changing.

---

## 6. Flight model

State: `position: Vector3`, `basis: Basis`, `speed: float`, `throttle: float`.

`step(cmd: InputCommand, dt: float) -> void` applies, in order:

1. **Throttle** — `throttle += cmd.throttle_delta * THROTTLE_RATE * dt`, clamped 0..1.
   `throttle_delta` is a rate command (hold to spool up), not a target position.
2. **Target speed** — `lerp(MIN_SPEED, MAX_SPEED, throttle)`
3. **Engine lag** — `speed += (target - speed) * (1 - exp(-ENGINE_RESPONSE * dt))`, where
   `ENGINE_RESPONSE` is a rate in 1/s
4. **Gravity coupling** — `speed -= GRAVITY * forward.y * dt`; climbing bleeds speed, diving
   gains it. This single term supplies most of the felt realism.
5. **Turn authority** — `MAX_TURN_RATE` scaled by a curve over speed: mushy below
   `BEST_TURN_SPEED`, mildly reduced well above it
6. **Steer** — rotate the nose toward `cmd.aim_dir`, clamped to that turn rate times dt
7. **Bank** — auto-roll into the turn proportional to yaw rate (`AUTO_BANK_GAIN`), plus manual
   `cmd.roll` at `MANUAL_ROLL_RATE`
8. **Stall sag** — below `STALL_SPEED` the nose pitches down at `SAG_RATE`. Forgiving: dive and
   recover. Never a spin, never an unrecoverable state.
9. **Integrate** — `position += forward * speed * dt`
10. **Ground** — below terrain height plus `GROUND_CLEARANCE`, emit a crash event

### Framerate independence

All smoothing uses `1 - exp(-k * dt)`, never `k * dt`. A 120 Hz desktop and a 45 Hz phone must
produce the same trajectory for the same inputs. This is pinned by a test, not by inspection —
specifically by a test on **raw speed** after one second of spool-up, not by a trajectory
comparison.

That distinction was established by measurement, not assumed. A trajectory comparison is too
insensitive to serve as the guard: substituting the naive `k * dt` form moves the 3-second
trajectory from 0.076% to 0.106% of path length, which any reasonable position tolerance would
pass. The speed test fails it outright (123.27 vs 123.60, tolerance 0.01).

### Starting tunables (`config.gd`)

Starting values to be tuned by feel, not derived constants.

```
MIN_SPEED 40 m/s          MAX_SPEED 180 m/s        STALL_SPEED 45 m/s
THROTTLE_RATE 0.8/s       ENGINE_RESPONSE 0.9/s    GRAVITY 9.81 m/s^2
MAX_TURN_RATE 1.8 rad/s   BEST_TURN_SPEED 90 m/s
AUTO_BANK_GAIN 2.5        MANUAL_ROLL_RATE 2.5 rad/s      SAG_RATE 1.2 rad/s
AIM_CONE_DEG 35           GROUND_CLEARANCE 3 m
```

### Structural bounds — correcting two earlier overclaims

Earlier drafts of this document asserted that speed never exceeds `MAX_SPEED` and that bank never
exceeds `MAX_BANK`. Both were measured false, and in both cases the *code* is right and the claim
was wrong.

**Speed ceiling.** `MAX_SPEED` is the level-flight maximum, not an absolute limit. A sustained
dive settles at `MAX_SPEED + GRAVITY / ENGINE_RESPONSE` — about **191 m/s** vertically, 6% over.
This is correct and wanted: energy management is the substance of a dogfight, and a dive that
bought no speed would remove the main reason to trade altitude. Clamping it would be the bug.

**Bank ceiling.** `MAX_BANK` clamps the *automatic* bank target only. Manual roll folds in on top,
so the reachable bound is `MAX_BANK + MANUAL_ROLL_RATE / BANK_RESPONSE` = **2.13 rad (122°)**;
the peak actually measured with the stick held into a sustained turn is **1.85 rad (106°)**. Also
correct: manual roll that could not beat the automatic lean would not be manual control.

**Bank is exact at any timestep.** `apply_bank` folds manual roll into the target rather than
adding it as a separate term, because `bank' = roll·MANUAL_ROLL_RATE + BANK_RESPONSE·(target -
bank)` is an exponential approach to `target + roll·MANUAL_ROLL_RATE/BANK_RESPONSE`. An earlier
attempt that added the manual term separately was exact only as `dt` approached zero and made the
equilibrium spread 2.1% across 120 Hz to 45 Hz. The current form agrees to 1.3e-7 rad across that
range. The rate cap survives because it can bind only during transients, never at equilibrium.

Both bounds are now pinned by tests, so a future change that alters them is deliberate.

**Open feel question for Phase 1 tuning.** With no turn, holding full roll converges to
**0.83 rad (47.7°)** and stops, because the auto-bank servo cancels it. The plane therefore
cannot barrel-roll or fly inverted. That is literally what "plus manual roll at
`MANUAL_ROLL_RATE`" specifies, and may be right for an aim-to-steer game where roll is mostly
cosmetic — but it will surprise anyone who holds the stick expecting a roll. Suppressing the
servo while roll is held (two lines) would give continuous rolling. Deferred to the Phase 1
manual tuning pass, when it can be judged with the game actually running rather than from a test
harness.

### Which levers actually move which behaviour

Measured on the implemented model, so that tuning by feel is not tuning blind.

`STALL_SPEED` sits deliberately **above** `MIN_SPEED`. That means idle throttle targets a speed
below stall, keeping the plane in permanent gentle sag — which is what turns closing the throttle
into a glide rather than a hover. The glide converges, without oscillation, to **-27.1° pitch at
45 m/s**, losing 561 m in 30 seconds.

That equilibrium slope is set by `STALL_SPEED`, `MIN_SPEED`, `ENGINE_RESPONSE` and `GRAVITY`
together. **`SAG_RATE` does not appear in it at all** — it governs only how briskly the plane
rotates into the glide (about 13.6 s at 1.2 rad/s), not the angle it settles at. Turning
`SAG_RATE` up to make gliding steeper will not work; it only makes the transition quicker.

Stall recovery at full throttle is likewise dominated by engine spool-up, not aerodynamics: the
engine alone crosses `STALL_SPEED` in roughly 17 frames, so `SAG_RATE` and `STALL_SPEED` barely
influence how a power-on stall resolves.

### Constants that currently do less than their names suggest

Found by mutation testing the finished model. None is a defect; all are tuning decisions best
made with the game running, and all are recorded here so nobody later wonders why turning a knob
changes nothing.

**`AUTO_BANK_GAIN` is inert.** The bank target saturates at `MAX_BANK` for any yaw rate above
0.52 rad/s, and `turn_rate()` never drops below 0.8 rad/s anywhere in the flyable band. So every
sustained turn banks to exactly `MAX_BANK` — bank is effectively binary, not "proportional to yaw
rate". Multiplying the gain by ten changes no test and no behaviour. Setting it to
`MAX_BANK / MAX_TURN_RATE` ≈ 0.72 would map the full turn-rate range onto the full bank range and
make it live.

**The turn law is effectively bang-bang.** At 90 m/s, *any* aim offset beyond 1.72° commands the
full turn rate. With `AIM_CONE_DEG` at 35, that means 95% of the cone is saturated: a 2° mouse
nudge and a 35° shove turn at the same rate, differing only in where the nose ends up. That is
coherent for aim-to-steer — the reticle is a position target, not a rate command — but it is not
the proportional control the controls section reads as. Note the coupling: because yaw rate is
then just `turn_rate(speed)`, a live `AUTO_BANK_GAIN` would make bank read *speed* rather than
stick deflection. Changing either alone will disappoint.

**The rate cap binds the automatic servo too.** `MANUAL_ROLL_RATE` caps every bank change, not
just manual ones, so it sets the airframe's roll-in rate and `BANK_RESPONSE` governs only the
tail of the motion. Defensible, but the name points the wrong way.

**Both turn-authority floors are nearly unreachable.** `MIN_TURN_SCALE` engages only below
22.5 m/s while level flight floors at 40, so the "mushy when slow" feel bottoms out at scale 0.44
and the floor itself is reachable only transiently in a zoom climb. `HIGH_SPEED_TURN_FLOOR`
engages at 150 m/s, so the top of the throttle band and the entire dive range share one turn
authority.

---

## 7. World

One fixed region, generated once at load, never streamed.

```
WORLD_SIZE 8000 m              TERRAIN_RES 64 m (125x125 grid)
TERRAIN_MAX_HEIGHT 900 m       SEA_LEVEL 0
BOUNDARY_SOFT_START 3600 m from centre
```

A `FastNoiseLite` heightmap becomes a single `ArrayMesh` with flat-shaded low-poly normals,
over a flat sea plane at y=0. Past `BOUNDARY_SOFT_START` the aim direction is progressively
biased back toward the centre — the player is turned around, never walled or teleported.

---

## 8. Camera

`SpringArm3D` chase camera, `CAM_DIST 18 m` behind and `CAM_HEIGHT 6 m` above, following with
`CAM_LAG 0.12 s`. Field of view widens from 70° to 85° across the speed range so that speed
reads visually. The camera looks at a point ahead of the nose rather than at the plane, so the
aim reticle stays centred.

---

## 9. Controls

Both platforms produce the identical `InputCommand`; only the source differs.

**PC.** Mouse position inside a screen-centre deadzone maps to an aim offset from the nose,
clamped to `AIM_CONE_DEG`. `W`/`S` throttle, `A`/`D` roll, left mouse or `Space` fire. `Esc`
quits — a pause menu is out of scope for Phase 1.

### Which axes the aim rotates about, and why it matters

This is the single most consequential detail in the controls, and getting it wrong made the game
unflyable in a way no unit test caught.

**Yaw is about world up.** Rotating about the aircraft's own `basis.y` couples aim to bank: the
auto-bank servo rolls the aircraft up to 75° in any sustained turn, at which point "right" in the
body frame is nearly "down" in the world. Measured on the body-frame version, *any* held rightward
cursor offset — 8 px or 324 px, bit-identically — reached −69° of pitch and hit the ground four
seconds after spawn. With yaw about world up, the same input holds exactly 600 m for a full
minute at 74.5° of bank.

**Pitch is about the body's right axis.** The obvious counterpart, pitching about
`forward.cross(UP)`, flips sign the instant the nose crosses vertical, reversing the pitch command
at the top of a loop and pinning the nose there. `basis.x` is continuous through a full rotation.

The trade-off is taken deliberately: pitching about a body axis means an inverted aircraft pitches
toward the ground when the pointer is pushed up. That is conventional for flight games, and it is
the price of being able to loop at all.

**The deadzone is load-bearing, not polish.** Without it a single pixel of cursor offset commands
6.5°/s and the aircraft cannot be flown straight.

**Touch.** A floating stick spawns wherever the left half of the screen is first touched and
tracks the drag to set aim. The right side carries a vertical throttle slider and a fire button.

Layout is selected by `DisplayServer.is_touchscreen_available()`, with a debug flag forcing the
touch UI on desktop so it can be checked without a phone.

---

## 10. HUD

Speed, altitude, throttle bar, artificial horizon line, aim reticle. Phase 2 adds health,
score, combo multiplier, and an off-screen enemy direction indicator.

---

## 11. Combat (Phase 2)

Guns only. `BULLET_SPEED 600 m/s`, `FIRE_RATE 12/s`, `DAMAGE 8`, `BULLET_LIFETIME 2.5 s`.
Bullets are kinematic and swept by raycast between frames. `PLAYER_HP 100`, `ENEMY_HP 30`.
A kill spawns 4 to 6 `RigidBody3D` debris chunks that free themselves after
`DEBRIS_LIFETIME 6 s`.

---

## 12. AI

One state machine per enemy, driving the same `FlightModel` through the same `InputCommand`.
Enemies obey identical physics to the player, which is what makes the fight feel fair rather
than rigged.

- **Pursue** — aim at a lead-intercept point on the projected path of the player
- **Attack** — inside `ATTACK_CONE 12°` and within `ATTACK_RANGE 600 m`, fire
- **Break** — on overshoot or inside `MIN_SEPARATION 120 m`, peel away for `BREAK_TIME 2.5 s`
- **Reposition** — regain altitude and speed, then return to Pursue

Aim jitter per difficulty keeps them beatable: `AIM_JITTER` starts at 8° and tightens toward 2°
as waves progress.

---

## 13. Waves and scoring

Wave `N`: `count = min(1 + floor(N / 2), 6)`, with `AIM_JITTER` interpolating from 8° to 2° over
waves 1 to 10 and flat thereafter. A wave ends when all of its enemies are dead; the next spawns
after `WAVE_GAP 3 s` at the region edge.

Kills within `COMBO_WINDOW 4 s` of each other chain: multiplier `+0.5` per link, capped at `x4`.
Score is `BASE_KILL_SCORE 100` times the multiplier. High score persists to
`user://highscore.cfg`.

Single life. Death shows the score and restarts.

---

## 14. Robustness

Zero-length or non-finite aim vectors are rejected and the previous aim is held. Every tunable
is clamped at use, not merely at definition. Bullets and debris free on a lifetime timer so a
long session cannot leak nodes. A missing `highscore.cfg` on first launch is normal, not an
error. The game pauses on focus loss.

---

## 15. Testing

A small assert-based runner executed as `godot --headless --script tests/run_tests.gd`, with no
plugin dependency. The exact invocation is verified against the real binary at the start of
implementation rather than assumed.

Covered headless:

- **Flight model** — speed is never negative and stays within the dive ceiling below; turn rate
  never exceeds the authority curve; cruise flight with neutral input holds altitude without
  drift; climbing bleeds speed and diving gains it; **one second of spool-up gives the same speed
  at dt=1/120 and dt=1/45** (the real framerate guard); one second of bank response likewise;
  trajectory heading and position agree across timestep; peak bank stays within the bank ceiling
  below; recovery from below stall speed terminates, including from a near-vertical zoom climb;
  idle throttle settles into a descending glide rather than diverging
- **AI** — each state transition fires on its documented condition; no state can deadlock
- **Waves** — count and jitter curves match the specified formulas at wave boundaries
- **Scoring** — combo chains inside the window, breaks outside it, caps at x4

Visual and feel behaviour is verified by a manual checklist run by the user, since the running
game cannot be observed from the development environment.

---

## 16. Phases and acceptance criteria

### Phase 1 — Flight

Automated: all flight-model tests pass, including dt-independence.

Manual checklist:

- Level flight with neutral input holds altitude with no drift
- A full loop completes without losing orientation or control
- Throttle produces a felt difference between slow and mushy versus fast and stiff turning
- Terrain contact triggers a crash and a clean restart
- Touch UI is usable via the forced-touch debug flag
- Holds 60 fps on the desktop target

**Combat work does not begin until every item above passes.**

### Phase 2 — Combat

Automated: AI, wave and scoring tests pass.

Manual checklist:

- Enemies visibly pursue, attack, overshoot and break rather than tailing rigidly
- A fight is winnable at wave 1 and genuinely hard by wave 8
- Bullets never pass through a target at high closing speed
- Score, combo and high score persist correctly across a restart
- No node leak after ten consecutive waves

---

## 17. Platform and build notes

Godot 4 is not currently installed on this machine and must be installed before implementation
starts. Android export additionally needs JDK 17, the Android SDK command-line tools, Godot
export templates and a debug keystore — all deferred until the game is worth installing on a
phone, per the phase ordering.

Touch controls are built and tested from Phase 1 using Godot touch emulation, so the eventual
Android export is a packaging exercise rather than a redesign.

---

### Degenerate-case guards must decide, not abstain

Two separate guards, each individually reasonable, composed into a permanent no-op. The world
boundary at full strength returns an aim exactly antiparallel to a radial heading; `apply_steering`
saw "exactly reversed, no unique rotation axis" and returned without turning. The result was an
aircraft flying dead straight out of the world to 11,240 m against a 4,000 m radius — with the
boundary having *bit-for-bit identical* effect to not existing at all.

The lesson generalises past this instance. When a guard detects a degenerate input, abstaining is
rarely the safe default it looks like: here, "no unique axis" was true and irrelevant, because any
perpendicular axis turns the aircraft around. Prefer picking an arbitrary valid answer over
declining to act.

Worth noting how it was caught: not by either component's own tests, both of which pass. It took a
test that drove a real controller through a real `FlightModel` for a sustained period — the same
shape that caught the Phase 1 aim-frame blocker, and the first thing that shape was pointed at in
Phase 2.

---

## 18. Known limitations at the end of Phase 1

Found by a final review that measured the assembled game rather than reading it. None blocks
flying; all are recorded so they are not rediscovered.

**The test suite's shape is its real weakness.** Every check is on a pure function or a static
helper. There is no coverage of `PlayerController.command`, `Aircraft._physics_process`,
`ChaseCamera._process`, `HUD._draw`, `TouchControls._input`, or any method of `Game` except the
static `spawn_point`. Every blocker the final review found lived in exactly that gap — the model
was provably correct while the game was unflyable. Phase 2 should add at least one test that
drives the real controller through the real model for a sustained period, which is what finally
caught it.

**Field of view is vertical, not horizontal.** Godot's `Camera3D.fov` with the default
`KEEP_HEIGHT` is the vertical angle, so `CAM_FOV_MIN`/`MAX` of 70–85 are **102°–117° horizontal**
at 16:9. That is very wide and will stretch at the edges. Left as-is because it is a feel
judgement that needs eyes on it, not a defect.

**The HUD horizon is not a true overlay.** `horizon_offset` is linear in pitch at 0.446 screen
heights per radian, while the real horizon moves at 0.714 (at FOV 70) to 0.546 (at FOV 85). The
drawn line therefore tracks at 62–82% of the real horizon's rate, and the ratio shifts with speed.
It reads correctly as an attitude indicator; it will not sit on the actual horizon.

**Touch banks harder than desktop.** `player_controller.gd` feeds `touch.aim.x * 0.5` into
`cmd.roll`, which folds roughly 0.42 rad on top of `MAX_BANK` — about 98° of bank on touch against
75° on desktop. Tune when the Android build is first flown.

**Touch hit zones are not the drawn rectangles.** The fire zone is any press with `x > 0.8w` and
`y > 0.6h`, which overlaps the drawn throttle-down box; the whole right half is live, and the
drawn boxes are decorative. Releasing any non-stick touch zeroes both throttle and fire.

**Testing the touch layout needs an editor setting.** `FORCE_TOUCH_UI` alone is not enough:
`input_devices/pointing/emulate_touch_from_mouse` must also be on, or no `InputEventScreenTouch`
is ever delivered and the aircraft is uncontrollable.

**The boundary aims you at the summit.** It rotates aim toward `(0, 0, 0)`, and the island's peak
sits within 600 m of the origin at roughly cruise altitude. A hands-off return from the world edge
flies into it after about 30 seconds.

**No physics interpolation.** On a display above 60 Hz the aircraft's transform steps about 2 m
per tick against a smoothly interpolated camera, which reads as mild judder.

---

## 19. Working agreements

- Only real project files live in the project directory; scratch work goes to a scratchpad
  outside it.
- Any process launched during development (headless test runs, the editor, servers) is
  terminated once it has served its purpose. No orphaned PIDs are left on the machine.
