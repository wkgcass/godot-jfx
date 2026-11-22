extends Node3D

const PANEL_SIZE := Vector2(1.60, 1.04)
const MISS := Vector2(-16, -16)
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Player/Camera
@onready var atlas: SubViewport = $Atlas
@onready var reticle: Control = $HUD/Reticle
var host: Node2D
var forwarding := false
var clicks: Array = []
var captured := false
var button_down := false
var last_pixel := MISS
var device_state := -1
var surfaces: Array[StaticBody3D] = []

func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_2X
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.23
	capsule.height = 1.72
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.86
	player.add_child(collider)
	atlas.world_2d = World2D.new()
	resize_atlas()
	get_window().size_changed.connect(resize_atlas)
	get_window().focus_exited.connect(func(): capture(false))
	for i in 2:
		make_panel(i)
	reticle.draw.connect(draw_hud)

func resize_atlas() -> void:
	atlas.size = get_window().size.max(Vector2i.ONE)
	last_pixel = Vector2.INF

func make_panel(index: int) -> void:
	var surface := StaticBody3D.new()
	surface.position = Vector3((index - 0.5) * 1.87, 1.54, -3.37)
	var mesh := QuadMesh.new()
	mesh.size = PANEL_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = atlas.get_texture()
	material.uv1_scale = Vector3(0.5, 1, 1)
	material.uv1_offset.x = index * 0.5
	mesh.material = material
	var face := MeshInstance3D.new()
	face.mesh = mesh
	surface.add_child(face)
	var shape := BoxShape3D.new()
	shape.size = Vector3(PANEL_SIZE.x, PANEL_SIZE.y, 0.01)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	surface.add_child(collision)
	add_child(surface)
	surfaces.append(surface)

func _process(_delta: float) -> void:
	# The JVM attaches its host after the main scene starts.
	host = get_node_or_null("/root/JavaFXHost")
	if host:
		RenderingServer.canvas_item_set_parent(host.get_canvas_item(), atlas.world_2d.canvas)
		host.set_process_input(false)
		set_process(false)

func on_javafx_message(topic: String, value: int) -> void:
	if topic != "room.devices" or value < 0 or (value >> 2) > 14:
		push_error("Unexpected JavaFX room message: %s (%d)" % [topic, value])
		return
	$Interior.apply_settings(bool(value & 1), bool(value & 2), 16 + (value >> 2))
	device_state = value

func capture(active: bool) -> void:
	captured = active
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE
	if not active:
		clicks.clear()
		move_pointer(MISS)
		if button_down:
			send_button(MISS, false)
	reticle.queue_redraw()

func _input(event: InputEvent) -> void:
	if forwarding or not is_instance_valid(host):
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		capture(false)
	elif event is InputEventMouseMotion and captured:
		player.rotate_y(-event.screen_relative.x * 0.0026)
		camera.rotation.x = clampf(camera.rotation.x - event.screen_relative.y * 0.0026, -1.42, 1.42)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not captured:
			if event.pressed:
				capture(true)
		else:
			# Preserve the aim and ordering even when press and release arrive in one physics tick.
			clicks.append([camera.global_transform, event.pressed])

func _physics_process(delta: float) -> void:
	var movement := Vector2.ZERO
	if captured:
		movement = Vector2(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
			int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))).normalized()
	player.velocity = player.basis * Vector3(movement.x * 2.8, -1.0, movement.y * 2.8)
	player.move_and_slide()
	if captured and is_instance_valid(host):
		for click in clicks:
			var pixel := pick(click[0])
			move_pointer(pixel)
			if (click[1] and pixel != MISS) or (not click[1] and button_down):
				send_button(pixel, click[1])
		move_pointer(pick(camera.global_transform))
	clicks.clear()

func pick(aim: Transform3D) -> Vector2:
	var query := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * 5.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var index := surfaces.find(hit.get("collider"))
	if index < 0 or hit.normal.z < 0.99:
		return MISS
	var local := surfaces[index].to_local(hit.position)
	var uv := Vector2(local.x / PANEL_SIZE.x + 0.5, 0.5 - local.y / PANEL_SIZE.y)
	return Vector2((index + uv.x) * 0.5, uv.y) * Vector2(atlas.size)

func move_pointer(pixel: Vector2) -> void:
	if pixel == last_pixel:
		return
	last_pixel = pixel
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button_down else 0
	deliver(event, pixel)
	reticle.queue_redraw()

func send_button(pixel: Vector2, pressed: bool) -> void:
	button_down = pressed
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	deliver(event, pixel)

func deliver(event: InputEventMouse, pixel: Vector2) -> void:
	if not is_instance_valid(host):
		return
	event.position = pixel
	event.global_position = pixel
	forwarding = true
	host.set_process_input(true)
	get_window().push_input(event, true)
	host.set_process_input(false)
	forwarding = false

func draw_hud() -> void:
	var dpi := maxf(1.0, DisplayServer.screen_get_scale(get_window().current_screen))
	reticle.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * dpi)
	var center := (reticle.size * 0.5 / dpi).round()
	var color := Color("bdf7d6") if captured and last_pixel != MISS else Color.WHITE
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		reticle.draw_line(center + dir * 3, center + dir * 9, Color("28322e"), 3)
		reticle.draw_line(center + dir * 3, center + dir * 9, color, 1)
	var text := "WASD   移动      鼠标   环顾      左键   操作      Esc   释放鼠标" if captured else "单击进入房间   ·   WASD 移动   /   鼠标环顾"
	var font := ThemeDB.fallback_font
	var baseline := Vector2(26, reticle.size.y / dpi - 24)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	reticle.draw_rect(Rect2(baseline - Vector2(12, 23), Vector2(width + 24, 34)), Color(0.08, 0.11, 0.10, 0.84))
	reticle.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
