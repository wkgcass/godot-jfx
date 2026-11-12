extends Node2D

var ticks := 0
var mouse_events := 0
var touch_events := 0
var key_events := 0
var mouse_releases := 0
var key_releases := 0
var touch_releases := 0
var canceled_touches := 0
var drag_events := 0
var last_mouse_position := Vector2.ZERO
var last_touch_position := Vector2.ZERO
var last_key := 0
var last_unicode := 0
var wheel_events := 0
var wheel_factor := 0.0
var last_position := Vector2.ZERO
var color := Color.RED

func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)

func _process(_delta: float) -> void:
	ticks += 1

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		last_mouse_position = event.position
		if event.pressed and event.button_index >= 4 and event.button_index <= 7:
			wheel_events += 1
			wheel_factor = event.factor
		if not event.pressed:
			mouse_releases += 1
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		last_touch_position = event.position
		if event is InputEventScreenDrag:
			drag_events += 1
		elif not event.pressed:
			touch_releases += 1
			if event.is_canceled():
				canceled_touches += 1
	if event is InputEventKey:
		last_key = event.keycode
		last_unicode = event.unicode
		if not event.pressed:
			key_releases += 1
	if event is InputEventMouseButton and event.pressed:
		mouse_events += 1
		last_position = event.position
		color = Color.BLUE
	if event is InputEventScreenTouch and event.pressed:
		touch_events += 1
		last_position = event.position
	if event is InputEventKey and event.pressed:
		key_events += 1
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(8,8,24,24),color)
	draw_rect(Rect2(40,8,16,24),Color(0,1,0,.5))
	draw_rect(Rect2(get_viewport_rect().size.x-12,44,8,8),Color.GREEN)
