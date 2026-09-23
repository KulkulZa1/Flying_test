# Flying — PC Setup (Phase 3)

**Date:** 2026-09-23
**Status:** Approved design, pending review of this written spec
**Builds on:** `2026-09-19-flying-arcade-dogfighter-design.md` (the main spec). Where the two
disagree about PC behaviour, this document wins: main spec §9's "`Esc` quits" is replaced by §4
here.
**Branch:** `phase3-pc`, off `phase2-combat`

---

## 1. Summary

Mobile testing is deferred. This phase makes the PC version a complete standalone game, in the
three pieces the user chose:

1. A Windows build: a single `.exe` that runs without Godot.
2. A pause menu with settings: mouse sensitivity, invert pitch, fullscreen.
3. Rebindable controls.

Out of scope: gamepad support (offered, not chosen), a title or main menu, graphics-quality or
field-of-view settings, audio, and any change to touch controls or to how the Android build
behaves. The Android build ships the new code, but none of it changes what a phone does
(§4, §7).

---

## 2. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Input mechanism | Godot `InputMap` actions | Standard Godot; rebinding is editing an action; no parallel key table to keep in sync |
| Menu construction | `.tscn` scene, root anchored full-rect | The HUD is built this way and sizes correctly; the code-built touch overlay kept a zero rect (main spec §18) |
| Windows build | Release template, x86_64, PCK embedded | One file to double-click, no console window |
| Settings storage | `user://settings.cfg` via `ConfigFile`, saved on every change | Same pattern as the high score; nothing is lost if the game is killed |
| Focus loss | Unchanged: silent pause, resume on return | The user's choice; §5 records the trade-off it keeps |

Rejected approaches: a hand-rolled binding table (it duplicates `InputMap`, and every input read
must route through it) and a third-party remapping add-on (a download and a dependency for five
actions).

---

## 3. Windows build

A second export preset, `Windows Desktop`, in the tracked `export_presets.cfg`, exporting to
`build/Flying.exe`, which `.gitignore` already covers. Release template, x86_64, with the PCK
embedded so the build is one file. The export filter mirrors the Android preset.

The window icon already comes from `application/config/icon`. Whether Godot can also stamp
`icon.png` onto the `.exe` file itself is checked at export. If that needs the external `rcedit`
tool, nothing is downloaded without asking the user first.

The `.exe` is unsigned, so Windows SmartScreen may warn the first time it runs on another machine.
An exported build and an editor run share one user-data folder, so the high score and settings
carry over between them.

---

## 4. Pause menu

`Esc` pauses the tree, frees the pointer (`MOUSE_MODE_VISIBLE`) and opens the pause menu:
**Resume**, **Settings**, **Quit**.

- **Quit** saves the high score and exits, which is exactly what `Esc` did before this phase.
- **`Esc` always backs out one level:** assigning a binding → Controls → Settings → pause menu →
  flying. Leaving the pause menu by `Esc` takes the same path as Resume.
- **Resume re-arms the pointer.** Before the tree unpauses, it re-confines the pointer, warps it to
  the centre and re-arms the controller: the same `_centre_pointer()` path the game takes at
  launch. The pointer's position *is* the aim input, so resuming with the pointer wherever the menu
  left it would command an instant turn, the same failure as the launch spiral.
- The menu processes while the tree is paused (`process_mode` always). A paused node receives no
  input, so a pausable menu could never close itself.

**The menu is PC-only for now.** Nothing on a phone opens it: there is no `Esc`, and focus loss
keeps its silent pause (§5). A touch pause button, and deciding which settings apply to touch,
belong to the mobile pass.

---

## 5. Focus loss: kept as is, with one guard

By the user's choice, switching away from the window still pauses silently and returning still
resumes. The pause menu adds one rule so the two cannot fight: **focus return only unpauses a
pause that focus loss caused.** Alt-tabbing out of an open pause menu and back leaves the menu
open and the game paused.

The trade-off this keeps: on return the pointer is wherever the user clicked to refocus, and that
position is read as aim at once, so the aircraft can turn the moment play resumes. This is accepted
behaviour, recorded here so it is not rediscovered as a bug.

---

## 6. Controls and rebinding

**Actions.** `PlayerController` stops calling `Input.is_key_pressed` and reads actions declared in
`project.godot`, with today's bindings as defaults:

| Action | Primary | Secondary |
|---|---|---|
| `throttle_up` | W | — |
| `throttle_down` | S | — |
| `roll_left` | A | — |
| `roll_right` | D | — |
| `fire` | Left click | Space |
| `pause` | Esc | — (fixed; not shown on the Controls screen) |

Keys are stored as physical keycodes, so the defaults sit in the same place on any keyboard layout.
The Controls screen names each key as the player's own layout labels it. With the defaults, flying
is unchanged.

**The Controls screen** lists the five rebindable actions, each with two slots. There are two
because `fire` must keep both left click and Space. Clicking a slot waits for the next key or mouse
button (not the wheel, which has no held state) and assigns it. If that input was already bound to
another slot, it moves: it is removed from the old slot, so one input never drives two actions.
That can leave an action unbound; an empty slot shows as `—`. **Reset to defaults** restores the
table above.

`Esc` is reserved for the menu and cannot be bound. Pressing it while assigning cancels the
assignment. Aim stays on the pointer and is not rebindable.

---

## 7. Settings

| Setting | Range | Default | Effect |
|---|---|---|---|
| Mouse sensitivity | 1.0–3.0, step 0.1 | 1.0 | Scales the pointer offset before the deadzone |
| Invert pitch | on / off | off | Flips the pointer's vertical offset |
| Fullscreen | on / off | off | Borderless fullscreen at desktop resolution, or windowed |

**Sensitivity, defined.** At 1.0, today's behaviour, full pitch deflection needs the pointer at the
top or bottom edge of the window. At 2.0 it needs half that travel. The floor is 1.0 because below
it full pitch deflection lies outside the window, where a confined pointer cannot go. Sensitivity
and invert apply to the mouse only; touch is untouched.

The HUD already sizes itself from the viewport height, so fullscreen needs no HUD change.
Fullscreen is applied on desktop only. A phone's window mode stays with the Android export
settings, which run the game in immersive fullscreen; applying a saved "windowed" there could
bring the system bars back.

**Persistence.** `Settings` loads `user://settings.cfg` at launch and saves on every change. A
missing file means defaults. A damaged file never breaks the game: an unreadable value falls back
to its default, and an out-of-range sensitivity is clamped.

---

## 8. Components

| Unit | Purpose | Depends on |
|---|---|---|
| `scripts/bindings.gd` (`Bindings`) | The binding table: defaults, move-on-assign, reset, conversion to and from plain data, application to `InputMap`, display names | `InputMap` |
| `scripts/settings.gd` (`Settings`) | Sensitivity, invert, fullscreen and a `Bindings`; load and save through an injectable path, like `Scoring` | `Bindings`, `ConfigFile`, `Config` |
| `scenes/pause_menu.tscn`, `scripts/pause_menu.gd` | Pause, Settings and Controls panels; `Esc` backs out one level; emits `resumed` and `quit_requested` | `Settings` |
| `scripts/controls_panel.gd` | The Controls panel's rows, and capturing a new binding | `Bindings` |
| `PlayerController` | Reads actions; scales and inverts the pointer offset through a static pure function | `Settings` |
| `Game` | Owns `Settings`; opens the menu; re-arms the pointer on `resumed`; the focus-loss guard (§5) | all of the above |
| `Config` | `SETTINGS_PATH`, the sensitivity bounds and default | — |

At startup `Game._ready()` loads `Settings`, applies the bindings to `InputMap` and, on desktop
only, the window mode, and hands `Settings` to the controller and the menu. A change made in the menu updates `Settings`,
which saves and re-applies it at once.

---

## 9. Testing

**Headless**, in the existing harness:

- `Settings`: defaults; a save and load round trip through an injected path; a damaged file falls
  back value by value; sensitivity is clamped on load
- `Bindings`: move-on-assign, reset, `Esc` refused, the plain-data round trip, application to
  `InputMap`
- `PlayerController` reads the actions, driven through `Input.action_press`
- **A sustained flight test.** The same pointer offset, run through the controller's real offset
  function and the real `FlightModel` for several seconds, climbs with invert off and descends
  with it on. The offset is off-axis, so the test also sees that invert leaves the turn direction
  alone. This follows the rule from the Phase 2 work: a sign error passes every pure-function
  check, and only driving the real model shows it.

Tests that change `InputMap` restore it from the project settings afterwards, so no test leaks
bindings into the next.

**Rendered.** The menus live where headless tests cannot reach (main spec §18: a node added inside
`_initialize()` never enters the tree, so its `_ready()` never runs). They are verified with the
capture harness: flying → `Esc` → Settings → Controls → back out → Resume, in a window and at
1920×1080. The same run measures that the aircraft holds heading and pitch after resuming with the
pointer left in a corner. The captures are shown to the user.

**The build.** The exported `.exe` is launched, run briefly, and its log (`user://logs/godot.log`)
checked for errors.

---

## 10. Acceptance criteria

Automated: every existing and new test passes.

Manual checklist:

- `build/Flying.exe` starts the game by double-click
- `Esc` pauses; Resume returns to straight flight wherever the pointer was left
- Each setting takes effect at once and survives a restart
- A rebound control works in flight and survives a restart; Reset restores the defaults
- The menus are legible and correctly sized, both windowed and fullscreen at 1920×1080

---

## 11. Build order

1. Windows export: independent, and gives a playable `.exe` straight away
2. Input actions: a behaviour-preserving move off hard-coded keys
3. `Bindings` and `Settings`
4. The pause menu, then the Controls panel
5. Rebuild the `.exe`; render and verify
