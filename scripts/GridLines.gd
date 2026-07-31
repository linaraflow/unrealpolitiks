extends Control

@export var line_color: Color = Color(0.56, 0.63, 0.55, 0.35)
@export var lines_count: int = 6

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	for i in range(1, lines_count):
		var y := h * i / float(lines_count)
		draw_line(Vector2(0, y), Vector2(w, y), line_color, 1.0)
	for i in range(1, lines_count):
		var x := w * i / float(lines_count)
		draw_line(Vector2(x, 0), Vector2(x, h), line_color, 1.0)
