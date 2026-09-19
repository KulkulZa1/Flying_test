extends Node3D

const BODY := Color(0.62, 0.65, 0.70)
const WING := Color(0.45, 0.48, 0.54)
const CANOPY := Color(0.15, 0.22, 0.30)

## Set before the node enters the tree; _ready() bakes it into the materials.
var tint := Color(1.0, 1.0, 1.0)

func _ready() -> void:
	_add_box(Vector3(1.2, 1.0, 7.0), Vector3(0.0, 0.0, 0.0), BODY * tint)      # fuselage
	_add_box(Vector3(9.0, 0.25, 1.6), Vector3(0.0, -0.1, 0.5), WING * tint)    # main wing
	_add_box(Vector3(3.4, 0.22, 0.9), Vector3(0.0, 0.0, 2.9), WING * tint)     # tailplane
	_add_box(Vector3(0.22, 1.6, 1.2), Vector3(0.0, 0.9, 3.0), WING * tint)     # fin
	_add_box(Vector3(0.9, 0.6, 1.8), Vector3(0.0, 0.62, -1.2), CANOPY * tint)  # canopy

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
