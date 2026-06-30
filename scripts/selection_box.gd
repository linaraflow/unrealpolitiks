extends Control

var settings = preload("res://new_resource.tres")

var box_color: Color = Color(0.2, 0.6, 1.0, 0.15)
var border_color: Color = Color(0.2, 0.6, 1.0, 0.7)
var border_width: float = 1.5

var is_dragging: bool = false

# Координаты для РИСОВАНИЯ (на экране, в пикселях монитора)
var drag_start_screen: Vector2 = Vector2.ZERO
var drag_end_screen: Vector2 = Vector2.ZERO

# Координаты для ЛОГИКИ (на карте, с учетом зума и позиции камеры)
var drag_start_global: Vector2 = Vector2.ZERO
var drag_end_global: Vector2 = Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_dragging = true
            
            # Точка на карте для логики выбора армий
            drag_start_global = get_global_mouse_position()
            drag_end_global = drag_start_global
            
            # Точка на экране для идеального рисования под курсором
            drag_start_screen = get_viewport().get_mouse_position()
            drag_end_screen = drag_start_screen
            
            queue_redraw()
        else:
            if is_dragging:
                is_dragging = false
                _select_units_in_box()
                queue_redraw()

    if event is InputEventMouseMotion and is_dragging:
        drag_end_global = get_global_mouse_position()
        drag_end_screen = get_viewport().get_mouse_position()
        queue_redraw()

func _draw() -> void:
    if not is_dragging: return
    
    # Считаем текущий размер рамки прямо на экране
    var screen_size = (drag_end_screen - drag_start_screen).abs()
    
    # ЕСЛИ РАМКА СЛИШКОМ МАЛЕНЬКАЯ (микро-клик) — ВООБЩЕ НИЧЕГО НЕ РИСУЕМ
    if screen_size.x < 6 or screen_size.y < 6:
        return
    
    # Дальше твой стандартный код перевода координат...
    var ev_start = InputEventMouseMotion.new()
    ev_start.position = drag_start_screen
    
    var ev_end = InputEventMouseMotion.new()
    ev_end.position = drag_end_screen
    
    var local_start = make_input_local(ev_start).position
    var local_end = make_input_local(ev_end).position
    
    var rect = Rect2(local_start, local_end - local_start)
    
    draw_rect(rect, box_color, true)
    draw_rect(rect, border_color, false, border_width)

func _select_units_in_box() -> void:

    var selection_rect = Rect2(drag_start_global, drag_end_global - drag_start_global).abs()

    if selection_rect.size.x < 10 or selection_rect.size.y < 10:
        return

    if not Input.is_key_pressed(KEY_SHIFT):
        SelectionManager.clear_selection()

    var all_divisions = get_tree().get_nodes_in_group("army_circles")

    for div in all_divisions:
        if div.division_owner != settings.active_country and settings.can_select == false:
            continue

        if is_instance_valid(div) and not div.is_selected:
            if selection_rect.has_point(div.global_position):
                SelectionManager._select_division(div)  # без сброса, без дублей
