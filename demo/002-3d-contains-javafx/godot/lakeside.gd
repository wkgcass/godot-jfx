extends Node3D

# The lake and each wooded ridge sit at a different distance beyond the west wall.
func matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func model(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.position = pos
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	return item

func _ready() -> void:
	ridge(-83.0, 10.0, 5.6, 0.7, Color("a3b5b2"))
	ridge(-53.0, 5.1, 3.7, 2.6, Color("97ada8"))
	ridge(-31.0, 2.1, 1.65, 4.1, Color("819c92"))
	var water := PlaneMesh.new()
	water.size = Vector2(320, 440)
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://lake.gdshader")
	model(water, surface, Vector3(-150,-0.5,0))
	pine(Vector3(-9.8,-0.6,2.45), 0.92, 27)
	pine(Vector3(-12.1,-0.6,-3.85), 1.0, 42, true)

func ridge(x: float, height: float, amplitude: float, phase: float, tint: Color) -> void:
	var strip := ImmediateMesh.new()
	var material := matte(tint)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	strip.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(-600, 601):
		var z := i * 0.30
		var t := z / absf(x) * 4.8 + phase
		var slope := 0.53 * sin(t) + 0.32 * sin(2.9*t + phase) + 0.15 * cos(6.8*t)
		var trees := 0.055 * sin(9.7*z) + 0.025 * sin(21.3*z + phase)
		strip.surface_add_vertex(Vector3(0, height + amplitude * slope + trees, z))
		strip.surface_add_vertex(Vector3(0,-0.54,z))
	strip.surface_end()
	model(strip, material, Vector3(x,0,0))

func limb(start: Vector3, end: Vector3, radius: float, wood: Material) -> void:
	var stem := CylinderMesh.new()
	stem.radial_segments = 7
	stem.rings = 0
	stem.bottom_radius = radius
	stem.top_radius = radius * 0.58
	stem.height = start.distance_to(end)
	var item := model(stem, wood, (start + end) * 0.5)
	item.quaternion = Quaternion(Vector3.UP, (end - start).normalized())

func pine(base: Vector3, size_factor: float, seed_value: int, forked := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wood := matte(Color("645f4f"))
	var sphere := SphereMesh.new()
	sphere.radial_segments = 19
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 4.8
	for k in vertices.size():
		var direction := vertices[k].normalized()
		var variation := noise.get_noise_3dv(direction)
		vertices[k] *= 1.0 + 0.28 * variation
		var value := 0.85 + 0.11 * direction.y + 0.13 * variation
		colors.append(Color(value, value, value))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var crown := ArrayMesh.new()
	crown.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var greens := [matte(Color("576f62")), matte(Color("617c69")), matte(Color("788c72"))]
	for green: StandardMaterial3D in greens:
		green.vertex_color_use_as_albedo = true
	if forked:
		var fork := base + Vector3(0.08, 1.42, 0.12) * size_factor
		var elbow := fork + Vector3(0.15, 0.76, 0.87) * size_factor
		var upper := fork + Vector3(-0.15, 1.50, -0.51) * size_factor
		limb(base, fork, 0.16 * size_factor, wood)
		limb(fork, elbow, 0.10 * size_factor, wood)
		limb(fork, upper, 0.12 * size_factor, wood)
		pine_bough(elbow, Vector3(0.18, 0.55, 0.74), size_factor, wood, crown, greens, rng)
		pine_bough(elbow, Vector3(-0.28, 1.06, 0.20), size_factor, wood, crown, greens, rng)
		pine_bough(upper, Vector3(0.35, 0.63, -0.78), size_factor, wood, crown, greens, rng)
		pine_bough(upper, Vector3(-0.16, 1.42, 0.36), size_factor, wood, crown, greens, rng)
		return
	var trunk := base
	for i in 6:
		var joint := base + size_factor * Vector3(0.09*i, 0.73*(i+1), -0.035*i*i)
		limb(trunk, joint, size_factor * (0.13 - 0.014*i), wood)
		trunk = joint
		if i == 0:
			continue
		var side := 1.0 if i % 2 == 0 else -1.0
		pine_bough(joint, Vector3(0.25,0.57,side*(1.48 - 0.14*i)), size_factor, wood, crown, greens, rng)

func pine_bough(joint: Vector3, direction: Vector3, size_factor: float, wood: Material,
		crown: Mesh, greens: Array, rng: RandomNumberGenerator) -> void:
	var tip := joint + direction * size_factor
	limb(joint, tip, 0.068*size_factor, wood)
	for j in 18:
		var a := rng.randf_range(0,TAU)
		var r := rng.randf_range(0.0,1.0)
		var tuft := Vector3(cos(a)*0.72*r,0.31*(1.0-r),sin(a)*1.05*r)
		var needles := model(crown, greens[j % 3], tip + tuft*size_factor)
		needles.scale = Vector3(0.81, rng.randf_range(0.32,0.48), rng.randf_range(0.65,1.12)) * size_factor
