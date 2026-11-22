extends Node

const SPIN_RATE := PI / 5.0
const FACE_COLORS := [Color("#63dec5"), Color("#aa99ff"), Color("#ffa576"), Color("#608dea")]
const TIP := Vector3(0, 1.48, 0)
const BASE_Y := -0.88
var spinning := true
var yaw := 0.52
var pitch := 0.27

func _ready() -> void:
	# GodotView creates a dedicated 2D-only SubViewport. Opt this scene into 3D.
	var viewport := get_viewport()
	if viewport is SubViewport:
		viewport.own_world_3d = true
		viewport.disable_3d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.transparent_bg = false
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#f7f5ef")
	$Camera.environment = environment
	$Camera.current = true
	$Solid.mesh = tetrahedron_mesh()
	update_camera()

func vertex_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func tetrahedron_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var base: Array[Vector3] = []
	for i in 3:
		var angle := TAU * i / 3.0
		base.append(Vector3(sin(angle) * 1.52, BASE_Y, cos(angle) * 1.52))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, vertex_material())
	for i in 3:
		var color: Color = FACE_COLORS[i]
		mesh.surface_set_color(color.lightened(0.30))
		mesh.surface_add_vertex(TIP)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(base[i])
		mesh.surface_set_color(color.darkened(0.24))
		mesh.surface_add_vertex(base[(i + 1) % 3])
	for point in base:
		mesh.surface_set_color(FACE_COLORS[3])
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh

func update_camera() -> void:
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	$Camera.position = direction * 8.0
	$Camera.look_at(Vector3.ZERO)
	$Axes.queue_redraw()

func _process(delta: float) -> void:
	if spinning:
		$Solid.rotate_y(SPIN_RATE * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			spinning = true
		elif event.keycode == KEY_P:
			spinning = false
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.009
		pitch = clampf(pitch + event.relative.y * 0.009, -1.48, 1.48)
		update_camera()
