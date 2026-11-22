extends Node2D

const DIRECTIONS := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const COLORS := [Color("#ffab93"), Color("#65dfc3"), Color("#b9abff")]
const LABELS := ["X", "Y", "Z"]

func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)

func _draw() -> void:
	var camera: Camera3D = $"../Camera"
	var origin := Vector2(59, get_viewport_rect().size.y - 56)
	var world_to_eye := camera.global_transform.basis.inverse()
	for i in 3:
		var unit: Vector3 = world_to_eye * DIRECTIONS[i]
		var direction := Vector2(unit.x, -unit.y)
		var end := origin + direction * 28
		draw_line(origin, end, COLORS[i], 2, true)
		draw_circle(end, 2.6, COLORS[i], true, -1, true)
		draw_string(ThemeDB.fallback_font, end + direction * 9 + Vector2(-4, 4),
				LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLORS[i])
	draw_circle(origin, 3, Color("#eaf1f4"), true, -1, true)
