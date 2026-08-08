extends Camera2D

var settings = preload("res://new_resource.tres")

@export var zoom_speed: float = 0.1
@export var max_zoom: float = 10.0

signal zoom_changed(new_zoom: Vector2)

var min_zoom: float = 1.0
var map_rect: Rect2
var is_dragging: bool = false

func _ready():
    var map = get_parent().get_node("Map")
    var texture_size = map.texture.get_size() * map.scale
    var map_pos = map.position
    
    # Если спрайт центрирован (Centered = true, по умолчанию)
    map_rect = Rect2(map_pos - texture_size / 2.0, texture_size)
    
    _update_min_zoom()

func _update_min_zoom():
    var viewport_size = get_viewport_rect().size
    var zoom_x = viewport_size.x / map_rect.size.x
    var zoom_y = viewport_size.y / map_rect.size.y
    min_zoom = max(zoom_x, zoom_y)  # чтобы карта всегда заполняла экран
    zoom = Vector2(min_zoom, min_zoom)

func _is_mouse_over_gui() -> bool:
    # Спрашиваем у Viewport'а напрямую, без флагов и сигналов —
    # никакой гонки между mouse_entered/exited и _unhandled_input.
    var hovered = get_viewport().gui_get_hovered_control()
    if hovered == null:
        return false

    # Кнопки армий (army_circle/Button) не должны блокировать управление
    # камерой — над юнитами на карте камеру всё равно нужно крутить/таскать/
    # зумить как обычно. Поднимаемся вверх по дереву в поисках узла из
    # группы "army_circles" (сама кнопка — его дочерний Control).
    var node: Node = hovered
    while node:
        if node.is_in_group("army_circles"):
            return false
        node = node.get_parent()

    return true

func _unhandled_input(event):
    if event is InputEventMouseButton:
        if _is_mouse_over_gui():
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _set_zoom(zoom.x + zoom_speed)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _set_zoom(zoom.x - zoom_speed)
        if event.button_index == MOUSE_BUTTON_MIDDLE:
            is_dragging = event.pressed
    if event is InputEventMouseMotion and is_dragging:
        position -= event.relative / zoom.x
        _clamp_position()

func _set_zoom(value: float):
    var new_zoom = clamp(value, min_zoom, max_zoom)
    zoom = Vector2(new_zoom, new_zoom)
    zoom_changed.emit(zoom)
    print("New zoom: " + str(zoom))
    _clamp_position()

func _clamp_position():
    var viewport_size = get_viewport_rect().size
    var half = viewport_size / 2.0 / zoom.x
    
    var min_x = map_rect.position.x + half.x
    var max_x = map_rect.end.x - half.x
    var min_y = map_rect.position.y + half.y
    var max_y = map_rect.end.y - half.y
    
    if min_x > max_x:
        position.x = map_rect.position.x + map_rect.size.x / 2.0
    else:
        position.x = clamp(position.x, min_x, max_x)
    
    if min_y > max_y:
        position.y = map_rect.position.y + map_rect.size.y / 2.0
    else:
        position.y = clamp(position.y, min_y, max_y)
