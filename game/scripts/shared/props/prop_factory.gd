class_name PropFactory
extends RefCounted

# Builds recognizable composite prop visuals and procedural surface patterns for
# every shape/pattern id in game/content, so the Quest host and the mobile 3D
# view render the exact same world with no bundled art assets.

static var _pattern_texture_cache: Dictionary = {}


# A prop node whose MeshInstance3D children compose the shape. Dimensions match
# the simulation's collision radii and half heights so visuals match physics.
static func make_prop(shape_id: String) -> Node3D:
	var prop := Node3D.new()
	prop.name = "Prop_" + shape_id
	match shape_id:
		"sphere":
			_add_part(prop, _sphere(0.16), Vector3.ZERO)
		"cylinder":
			_add_part(prop, _cylinder(0.14, 0.14, 0.34), Vector3.ZERO)
		"cone":
			_add_part(prop, _cylinder(0.02, 0.18, 0.34), Vector3.ZERO)
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.13
			capsule.height = 0.36
			_add_part(prop, capsule, Vector3.ZERO)
		"pyramid":
			_add_part(prop, _cylinder(0.01, 0.20, 0.28, 4), Vector3.ZERO)
		"star":
			# A toy starfish: flattened core with five stubby points.
			_add_part(prop, _sphere(0.09), Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
			for index in 5:
				var angle := TAU * index / 5.0
				var part := _add_part(prop, _cylinder(0.015, 0.055, 0.14), Vector3(cos(angle) * 0.13, 0.0, sin(angle) * 0.13))
				part.rotation = Vector3(PI / 2.0, -angle + PI / 2.0, 0.0)
		"ring":
			_add_part(prop, _torus(0.10, 0.17), Vector3.ZERO)
		"duck":
			_add_part(prop, _sphere(0.13), Vector3(0.0, -0.03, 0.0), Vector3(0.9, 0.75, 1.15))
			_add_part(prop, _sphere(0.08), Vector3(0.0, 0.09, 0.09))
			var beak := _add_part(prop, _cylinder(0.01, 0.035, 0.07), Vector3(0.0, 0.08, 0.18))
			beak.rotation.x = PI / 2.0
		"mug":
			_add_part(prop, _cylinder(0.13, 0.13, 0.30), Vector3.ZERO)
			var handle := _add_part(prop, _torus(0.025, 0.07), Vector3(0.15, 0.0, 0.0))
			handle.rotation.z = PI / 2.0
		"can":
			_add_part(prop, _cylinder(0.11, 0.11, 0.32), Vector3.ZERO)
			_add_part(prop, _cylinder(0.095, 0.095, 0.012), Vector3(0.0, 0.166, 0.0))
		"toy_block":
			_add_part(prop, _box(Vector3(0.26, 0.24, 0.26)), Vector3(0.0, -0.02, 0.0))
			_add_part(prop, _cylinder(0.08, 0.08, 0.05), Vector3(0.0, 0.125, 0.0))
		"book":
			_add_part(prop, _box(Vector3(0.30, 0.09, 0.22)), Vector3.ZERO)
			_add_part(prop, _box(Vector3(0.27, 0.095, 0.19)), Vector3(0.02, 0.0, 0.0))
		"bottle":
			_add_part(prop, _cylinder(0.10, 0.10, 0.26), Vector3(0.0, -0.06, 0.0))
			_add_part(prop, _cylinder(0.035, 0.07, 0.10), Vector3(0.0, 0.12, 0.0))
			_add_part(prop, _cylinder(0.035, 0.035, 0.05), Vector3(0.0, 0.19, 0.0))
		"donut":
			_add_part(prop, _torus(0.06, 0.16), Vector3.ZERO)
		"gem":
			# Crown and pavilion cut like a toy jewel, with a small flat base.
			_add_part(prop, _cylinder(0.06, 0.15, 0.10, 8), Vector3(0.0, 0.09, 0.0))
			_add_part(prop, _cylinder(0.15, 0.05, 0.18, 8), Vector3(0.0, -0.05, 0.0))
		_:
			_add_part(prop, _box(Vector3(0.28, 0.28, 0.28)), Vector3.ZERO)
	return prop


# Material for a prop color + surface pattern. Pattern textures are grayscale
# and multiplied by the albedo color, so one cached texture serves every color.
static func make_material(color: Color, pattern_id: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.metallic = 0.0
	match pattern_id:
		"metallic":
			material.metallic = 0.85
			material.roughness = 0.28
		"glow":
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.55
		"solid":
			pass
		_:
			var texture := pattern_texture(pattern_id)
			if texture != null:
				material.albedo_texture = texture
				material.uv1_scale = Vector3(2.0, 2.0, 2.0)
				material.uv1_triplanar = true
	return material


static func apply_material(prop: Node3D, material: Material) -> void:
	for child in prop.get_children():
		if child is MeshInstance3D:
			child.material_override = material


# Cached grayscale pattern tile; white keeps the full albedo color and the
# darker tone reads as the pattern accent.
static func pattern_texture(pattern_id: String) -> ImageTexture:
	if _pattern_texture_cache.has(pattern_id):
		return _pattern_texture_cache[pattern_id]
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var value := 1.0
			match pattern_id:
				"stripes":
					value = 1.0 if int(x / 8) % 2 == 0 else 0.55
				"dots":
					var cell := 16
					var dx := x % cell - cell / 2
					var dy := y % cell - cell / 2
					value = 0.5 if dx * dx + dy * dy < 22 else 1.0
				"checker":
					value = 1.0 if (int(x / 16) + int(y / 16)) % 2 == 0 else 0.6
				"wood":
					# Soft concentric grain bands around the tile center.
					var d := Vector2(x - size / 2.0, y - size / 2.0).length()
					value = 0.78 + 0.22 * sin(d * 0.9)
				_:
					value = 1.0
			image.set_pixel(x, y, Color(value, value, value))
	var texture := ImageTexture.create_from_image(image)
	_pattern_texture_cache[pattern_id] = texture
	return texture


static func _add_part(prop: Node3D, mesh: Mesh, offset: Vector3, part_scale := Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = offset
	part.scale = part_scale
	prop.add_child(part)
	return part


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


static func _cylinder(top: float, bottom: float, height: float, segments: int = 24) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.ring_segments = 24
	return mesh
