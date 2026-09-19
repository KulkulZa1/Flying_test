class_name Game
extends Node3D

var terrain: Terrain
var aircraft: Aircraft
var camera: ChaseCamera
var controller: PlayerController
var hud: HUD

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
	aircraft.crashed.connect(_on_crashed)
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
	environment.fog_density = 0.0001
	environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func _restart() -> void:
	aircraft.reset(spawn_point(terrain))
	camera.snap_to_target()
	_centre_pointer()

## The pointer IS the control input, so a respawn must re-centre it. Without this
## the aircraft starts in whatever bank the cursor's resting position commands.
func _centre_pointer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var size := get_viewport().get_visible_rect().size
	Input.warp_mouse(size * 0.5)

func _on_crashed() -> void:
	_restart()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

## Spec section 14: the game pauses on focus loss. Notifications are delivered
## regardless of pause state, so Game receives focus events and can unpause
## itself even while the tree is paused - no special process_mode is needed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		get_tree().paused = false
