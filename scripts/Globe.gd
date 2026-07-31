extends Control

@export var globe_color: Color = Color(0.73, 0.64, 0.42, 0.5) # #b9a26a
@export var radius: float = 180.0
@export var seconds_per_rotation: float = 140.0

@export_range(0.0, 1.0) var visible_fraction: float = 0.55  # 0 = совсем скрыт, 1 = виден полностью

func _ready() -> void:
    custom_minimum_size = Vector2(radius * 2, radius * 2)
    size = custom_minimum_size
    pivot_offset = size / 2.0
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    set_anchors_preset(Control.PRESET_CENTER_RIGHT)
    # выезд глобуса за правый край экрана, как в HTML-версии (right: -10%)
    position.x -= radius * 2.0 * visible_fraction  # сдвигаем влево на нужную долю диаметра
    position.y -= radius

func _process(delta: float) -> void:
    rotation_degrees += (360.0 / seconds_per_rotation) * delta

func _draw() -> void:
    var c := Vector2(radius, radius)
    draw_arc(c, radius, 0, TAU, 64, globe_color, 1.0, true)

    _draw_ellipse(c, radius, radius * 0.33)
    _draw_ellipse(c, radius, radius * 0.66)
    _draw_ellipse(c, radius * 0.33, radius)
    _draw_ellipse(c, radius * 0.66, radius)

    draw_line(Vector2(0, radius), Vector2(radius * 2, radius), globe_color, 1.0)
    draw_line(Vector2(radius, 0), Vector2(radius, radius * 2), globe_color, 1.0)

func _draw_ellipse(center: Vector2, rx: float, ry: float) -> void:
    var points := PackedVector2Array()
    var steps := 64
    for i in range(steps + 1):
        var t := TAU * i / steps
        points.append(center + Vector2(cos(t) * rx, sin(t) * ry))
    draw_polyline(points, globe_color, 1.0, true)
