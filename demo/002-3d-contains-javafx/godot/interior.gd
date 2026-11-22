extends Node3D

const WALL := "dbd4c5"
const OAK := "a78061"
const DARK := "344441"
var finishes := {}
var lamps: Array[OmniLight3D] = []
var diffusers: Array[MeshInstance3D] = []
var louvres: Array[MeshInstance3D] = []
var indicator: MeshInstance3D

func finish(tint: String) -> StandardMaterial3D:
	if not finishes.has(tint):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(tint)
		material.roughness = 0.87
		finishes[tint] = material
	return finishes[tint]

func box(pos: Vector3, size: Vector3, tint: String, solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = finish(tint)
	item.position = pos
	add_child(item)
	if solid:
		var body := StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		item.add_child(body)
	return item

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("92b3c0")
	sky_material.sky_horizon_color = Color("f1e8d1")
	sky_material.sky_curve = 0.20
	env.sky = Sky.new()
	env.sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ebeae2")
	env.ambient_light_energy = 0.54
	world.environment = env
	add_child(world)
	box(Vector3(0,-0.11,0), Vector3(9,0.2,7), OAK, true)
	var boards := ["ba9877", "bf9d7c", "bc9979", "c2a080"]
	for i in 20:
		var x := (i - 9.5) * 0.45
		box(Vector3(x,-0.006,0), Vector3(0.444,0.012,7), boards[(i * 7) % 4])
		for j in 2:
			box(Vector3(x,0.001,(i % 3) * 0.65 + j * 2.9 - 2.8), Vector3(0.442,0.002,0.008), OAK)
	for z in [-3.59,3.59]:
		box(Vector3(0,1.70,z), Vector3(9.25,3.4,0.18), WALL, true)
		box(Vector3(0,0.09,z * 0.968), Vector3(9,0.18,0.06), "867663")
	box(Vector3(4.59,1.70,0), Vector3(0.18,3.4,7.18), WALL, true)
	# Leave a real opening between z = -2.1 and 1.7, from sill to lintel.
	box(Vector3(-4.59,0.46,0), Vector3(0.18,0.92,7.18), WALL, true)
	box(Vector3(-4.59,3.19,0), Vector3(0.18,0.42,7.18), WALL, true)
	box(Vector3(-4.59,1.95,-2.845), Vector3(0.18,2.06,1.49), WALL, true)
	box(Vector3(-4.59,1.95,2.645), Vector3(0.18,2.06,1.89), WALL, true)
	for x in [-4.48,4.48]:
		box(Vector3(x,0.09,0), Vector3(0.06,0.18,7), "867663")
	box(Vector3(0,3.46,0),Vector3(9.25,0.12,7.2), "e6e0d6")
	# Smoked oak backplates and a narrow shadow gap around each wall screen.
	for i in 2:
		var x := (i - 0.5) * 1.87
		box(Vector3(x,1.54,-3.448),Vector3(1.72,1.16,0.10), OAK)
		box(Vector3(x,1.54,-3.394),Vector3(1.64,1.08,0.046), DARK)
	# High wall-mounted split unit with a pivoting outlet and a status lamp.
	box(Vector3(0.94,2.70,-3.32),Vector3(1.66,0.40,0.32), "eeeae0")
	box(Vector3(0.94,2.60,-3.15),Vector3(1.48,0.105,0.035), DARK)
	for i in 3:
		louvres.append(box(Vector3(0.94,2.56+i*0.04,-3.124),Vector3(1.45,0.028,0.07), "c9c8bb"))
	indicator = box(Vector3(1.62,2.78,-3.15),Vector3(0.08,0.022,0.02), DARK)
	for x in [-2.85,2.85]:
		box(Vector3(x,2.0,-3.44),Vector3(0.21,0.68,0.12), OAK)
		diffusers.append(box(Vector3(x,2.0,-3.36),Vector3(0.16,0.58,0.07), "fff1ce"))
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,2.15,-2.53)
		lamp.light_color = Color("ffdeb0")
		lamp.omni_range = 6.5
		lamp.shadow_enabled = true
		add_child(lamp)
		lamps.append(lamp)
	build_window()
	var landscape := preload("res://lakeside.gd").new()
	add_child(landscape)
	box(Vector3(1.6,0.48,2.9),Vector3(2.95,0.16,0.79), OAK, true)
	for x in [0.35,2.85]:
		box(Vector3(x,0.22,2.9),Vector3(0.12,0.44,0.70), DARK, true)
	box(Vector3(1.28,0.64,2.9),Vector3(2.1,0.17,0.72), "81958a", true)
	box(Vector3(4.43,1.7,0.4),Vector3(0.09,1.46,1.04), OAK)
	box(Vector3(4.37,1.7,0.4),Vector3(0.04,1.35,0.93), "eee6d7")
	box(Vector3(4.34,1.66,0.47),Vector3(0.02,0.82,0.42), "83988b")
	box(Vector3(4.32,1.45,0.21),Vector3(0.02,0.39,0.31), "b78364")
	var daylight := OmniLight3D.new()
	daylight.position = Vector3(-4.95,2.65,-0.65)
	daylight.light_color = Color("e2f0f1")
	daylight.light_energy = 0.82
	daylight.omni_range = 7.0
	add_child(daylight)
	apply_settings(true, false, 23)

func build_window() -> void:
	# The timber lining extends into the reveal; the dark glazing seal sits behind it.
	for z in [-2.065, 1.665]:
		box(Vector3(-4.57,1.95,z), Vector3(0.26,2.06,0.07), OAK)
	for y in [0.95, 2.95]:
		box(Vector3(-4.57,y,-0.20), Vector3(0.26,0.06,3.66), OAK)
	box(Vector3(-4.51,0.906,-0.20), Vector3(0.47,0.065,3.96), "aa8866")
	for z in [-2.018, 1.618, 0.63]:
		box(Vector3(-4.59,1.95,z), Vector3(0.065,1.94,0.032), "514e44")
	for y in [0.99, 2.91]:
		box(Vector3(-4.59,y,-0.20), Vector3(0.065,0.025,3.66), "514e44")
	# Offset casement with a small returning brass handle.
	box(Vector3(-4.55,1.95,0.67), Vector3(0.09,1.92,0.052), "91795e")
	box(Vector3(-4.48,1.72,0.67), Vector3(0.075,0.038,0.034), "786953")
	box(Vector3(-4.44,1.666,0.67), Vector3(0.03,0.14,0.034), "655944")
	var glass := box(Vector3(-4.61,1.95,-0.20), Vector3(0.012,1.94,3.66), "e6efe9", true)
	var glazing := StandardMaterial3D.new()
	glazing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glazing.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glazing.albedo_color = Color(0.86, 0.94, 0.93, 0.035)
	glass.material_override = glazing
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func apply_settings(lit: bool, cooling: bool, temperature: int) -> void:
	for lamp in lamps:
		lamp.light_energy = 1.45 if lit else 0.0
	for face in diffusers:
		var mat := finish("fff1ce" if lit else "b3a99b")
		mat.emission_enabled = lit
		mat.emission = Color("ffdc9c")
		face.material_override = mat
	indicator.material_override = finish("82dad0" if cooling else DARK)
	for flap in louvres:
		flap.rotation.x = deg_to_rad(32 + (30 - temperature) * 1.5) if cooling else 0.0
