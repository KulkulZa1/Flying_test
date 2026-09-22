class_name Game
extends Node3D

var terrain: Terrain
var aircraft: Aircraft
var camera: ChaseCamera
var controller: PlayerController
var hud: HUD
var bullets: Bullets
var scoring: Scoring
var enemies: Array[Aircraft] = []
var wave := 0
var _wave_gap := 0.0
var _credit: Aircraft = null

## Out over the sea with the nose pointed inland, clearing whatever ground is
## actually underneath. A fixed altitude can spawn inside a mountain: the island
## reaches 656 m within 580 m of the origin and START_ALTITUDE is only 600 m.
static func spawn_point(ground: Terrain) -> Vector3:
	var x := 0.0
	var z := Config.WORLD_SIZE * 0.4
	var y := maxf(Config.START_ALTITUDE, ground.height_at(x, z) + Config.START_CLEARANCE)
	return Vector3(x, y, z)

func _ready() -> void:
	_build_environment()
	terrain = Terrain.new()
	add_child(terrain)
	controller = PlayerController.new()
	add_child(controller)
	aircraft = preload("res://scenes/aircraft.tscn").instantiate()
	aircraft.controller = controller
	aircraft.terrain = terrain
	# Hitting the ground ends the run like any other death. Restarting on a crash
	# made flying into the sea a free full-heal that kept your score and wave.
	aircraft.crashed.connect(_on_player_died)
	add_child(aircraft)
	camera = ChaseCamera.new()
	camera.target = aircraft
	camera.far = Config.WORLD_SIZE
	camera.current = true
	add_child(camera)
	var hud_layer := preload("res://scenes/hud.tscn").instantiate()
	add_child(hud_layer)
	hud = hud_layer.get_node("HUD")
	hud.target = aircraft
	if TouchControls.is_active():
		var touch := TouchControls.new()
		hud_layer.add_child(touch)
		controller.touch = touch
	bullets = Bullets.new()
	add_child(bullets)
	scoring = Scoring.new()
	hud.scoring = scoring
	hud.enemies = enemies
	aircraft.max_hp = Config.PLAYER_HP
	aircraft.died.connect(_on_player_died)
	_restart()

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.1
	# Off deliberately. The terrain is one 8 km mesh whose bounds intersect every
	# shadow split, so enabling shadows resubmits all 93,750 of its vertices once
	# per split - about 375,000 vertices a frame - to cast shadows a player at
	# 600 m altitude cannot see.
	sun.shadow_enabled = false
	add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.45, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.82, 0.90)
	# ProceduralSkyMaterial draws a ground hemisphere below its horizon, and its
	# default is a dark grey. Everywhere the island did not occlude it, that
	# rendered as a dark bar along the entire horizon — the sea and the fog were
	# both blamed for it first. Matched to the horizon so it reads as haze.
	sky_material.ground_horizon_color = Color(0.72, 0.82, 0.90)
	sky_material.ground_bottom_color = Color(0.58, 0.70, 0.82)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Held well below full. With shadows off for mobile, sky ambient at full
	# strength lit every face of the terrain almost equally, so the island read
	# as a pale flat wash with no sense of form. Dimming it lets the sun's
	# direction do the shaping instead.
	environment.ambient_light_energy = 0.45
	environment.fog_enabled = true
	environment.fog_density = 0.0001
	environment.fog_sky_affect = 0.0
	# Matched to the sky's horizon colour. Left at its neutral grey default,
	# distant geometry faded to grey against a pale blue sky and the far sea
	# read as a dark bar drawn along the whole horizon.
	environment.fog_light_color = Color(0.72, 0.82, 0.90)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func _restart() -> void:
	aircraft.reset(spawn_point(terrain))
	camera.snap_to_target()
	# Deferred because _restart() runs from _ready(), before the window exists:
	# a warp issued there goes nowhere, which is how the game came to launch with
	# the cursor wherever it happened to be.
	_centre_pointer.call_deferred()

## The pointer IS the control input, so it must start centred and must never be
## able to leave the window. Measured without this: launching with the cursor
## 372 px above the window read as a held full-deflection command, and the
## aircraft spiralled from 646 m to 921 m in ten seconds untouched.
func _centre_pointer() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	controller.armed = true

## Every aircraft ticks its own controller and weapon, so `fired` is read here
## rather than recomputed. Calling command() again would run each AI state
## machine twice per tick and get a different answer the second time. Godot runs
## a parent's _physics_process before its children, so `fired` is one tick old -
## sixteen milliseconds, which no one can see.
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
		# died is emitted synchronously inside take_damage, so _on_enemy_died
		# reads the right shooter here and nowhere else.
		_credit = hit["shooter"]
		Debris.spark(self, hit["at"])
		hit["target"].take_damage(Config.BULLET_DAMAGE)
	_credit = null
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
	var count := WaveDirector.wave_size(wave)
	for i in count:
		var enemy: Aircraft = preload("res://scenes/aircraft.tscn").instantiate()
		enemy.terrain = terrain
		enemy.max_hp = Config.ENEMY_HP
		var pilot := AIPilot.new()
		pilot.target = aircraft
		pilot.jitter_degrees = WaveDirector.jitter_for(wave)
		enemy.controller = pilot
		enemy.died.connect(_on_enemy_died.bind(enemy))
		enemy.crashed.connect(_on_enemy_crashed.bind(enemy))
		enemy.get_node("Visual").tint = Color(1.45, 0.62, 0.55)
		add_child(enemy)
		enemy.reset(WaveDirector.spawn_point(aircraft.model.position, i, count))
		enemies.append(enemy)

func _on_enemy_died(enemy: Aircraft) -> void:
	if _credit == aircraft:
		scoring.register_kill()
	Debris.scatter(self, enemy.model.position, enemy.model.forward() * enemy.model.speed * 0.3)
	enemies.erase(enemy)
	enemy.queue_free()

## Flying into a mountain removes an enemy but scores nothing. Routing it
## through take_damage would credit the player for a kill they did not make,
## and enemies meet terrain often enough for that to be farmable.
func _on_enemy_crashed(enemy: Aircraft) -> void:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return
	enemy.hp = 0.0
	Debris.scatter(self, enemy.model.position, Vector3.ZERO)
	enemies.erase(enemy)
	enemy.queue_free()

## Clears the wave as well as the score. Leaving survivors alive meant a
## respawned pilot faced the wave that had just killed them, with the counter
## stuck at zero until they cleared it.
func _on_player_died() -> void:
	hud.show_death(scoring.score)
	scoring.save_high_score()
	scoring.reset_run()
	wave = 0
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	_wave_gap = Config.WAVE_GAP
	_restart()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		scoring.save_high_score()
		get_tree().quit()

## Spec section 14: the game pauses on focus loss. Notifications are delivered
## regardless of pause state, so Game receives focus events and can unpause
## itself even while the tree is paused - no special process_mode is needed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		get_tree().paused = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		scoring.save_high_score()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's back gesture quits without a close request, so this is the
		# only hook that runs before the app dies on a phone.
		scoring.save_high_score()
