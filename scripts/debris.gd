class_name Debris
extends Node3D

## Scatters tumbling chunks that free themselves. Rigid bodies are used here and
## nowhere else in the project: this is decoration rather than control, so the
## solver's nondeterminism costs nothing and tumbling comes free. Note the
## terrain has no collision body, so chunks fall through the island rather than
## landing on it.
static func scatter(parent: Node3D, at: Vector3, inherited: Vector3) -> void:
	for i in Config.DEBRIS_COUNT:
		var size := Vector3(randf_range(0.4, 1.2), randf_range(0.4, 1.0), randf_range(0.6, 1.6))
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.32, 0.30, 0.28)
		mesh.material = material
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		var box := BoxShape3D.new()
		box.size = size
		var shape := CollisionShape3D.new()
		shape.shape = box
		var chunk := RigidBody3D.new()
		chunk.add_child(visual)
		chunk.add_child(shape)
		chunk.position = at
		chunk.linear_velocity = inherited + Vector3(
			randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)
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

## One shared mesh and material for every spark. A fresh default SphereMesh is
## 4,224 triangles - more than a tenth of the whole island - built and destroyed
## up to sixty times a second during sustained fire.
static var _spark_mesh: SphereMesh = null

static func _shared_spark_mesh() -> SphereMesh:
	if _spark_mesh == null:
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 1.4
		_spark_mesh.height = 2.8
		_spark_mesh.radial_segments = 8
		_spark_mesh.rings = 4
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.92, 0.55)
		_spark_mesh.material = material
	return _spark_mesh

## A brief flash where a round lands. Without it there is no feedback at all
## between pulling the trigger and an enemy eventually exploding.
static func spark(parent: Node3D, at: Vector3) -> void:
	var flash := MeshInstance3D.new()
	flash.mesh = _shared_spark_mesh()
	flash.position = at
	parent.add_child(flash)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.09
	timer.timeout.connect(flash.queue_free)
	flash.add_child(timer)
	timer.start()
