class_name Terrain
extends Node3D

var _noise := FastNoiseLite.new()

func _init() -> void:
	# Seeded here rather than in _ready() so height_at() works without a scene tree.
	_noise.seed = Config.TERRAIN_SEED
	_noise.frequency = Config.TERRAIN_FREQUENCY
	# Default 5 octaves puts the finest detail at a 104 m wavelength against a
	# 64 m mesh grid - below Nyquist, so the drawn surface and the collision
	# field disagreed by up to 29 m. Three octaves narrowed that to a worst
	# case of 8.9 m - only a 0.08 m margin under the 9 m test bound. Two
	# octaves widens the margin to 4.2 m (worst 4.8 m) while relief actually
	# increases (727 m highest vs 656 m at five octaves).
	_noise.fractal_octaves = 2

func height_at(x: float, z: float) -> float:
	var n := (_noise.get_noise_2d(x, z) + 1.0) * 0.5          # 0..1
	var r := Vector2(x, z).length() / (Config.WORLD_SIZE * 0.5)
	var falloff := clampf(1.0 - r * r, 0.0, 1.0)              # island edges sink to sea
	return n * falloff * Config.TERRAIN_MAX_HEIGHT

func _ready() -> void:
	add_child(build_land())
	add_child(build_sea())

func build_land() -> MeshInstance3D:
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

func build_sea() -> MeshInstance3D:
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
