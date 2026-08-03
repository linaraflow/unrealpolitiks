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
    SaveManager.SelectionBox = self
    
    mouse_filter = Control.MOUSE_FILTER_IGNORE

# === ГЛАВНЫЙ ФИКС ===
# Раньше этот Control лежал прямо под "Game" (Node2D), а НЕ под CanvasLayer.
# Из-за этого его отрисовка и хит-тест зависели от трансформации Camera2D
# (позиция/zoom), как будто это часть карты, а не UI поверх экрана.
# Поэтому рамка "уезжала"/пропадала в некоторых частях карты и при зуме.
#
# Теперь узел перенесён в сцене (game.tscn) внутрь CanvasLayer — там он
# полностью независим от камеры, и экранные координаты = локальным координатам
# этого Control'а всегда (anchors full rect, growы по обе стороны).
#
# ВАЖНО: раз мы теперь в CanvasLayer, self.get_global_mouse_position() и
# self.get_global_transform() возвращают ЭКРАННЫЕ координаты, а не мировые
# (координаты карты)! Поэтому мировую позицию мыши для логики выделения
# нужно брать через активную камеру, а не через self.

func _get_world_mouse_position() -> Vector2:
    var cam := get_viewport().get_camera_2d()
    if cam:
        return cam.get_global_mouse_position()
    # fallback, если камеры почему-то нет
    return get_global_mouse_position()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_dragging = true

            # Точка на карте (мировые координаты) для логики выбора армий
            drag_start_global = _get_world_mouse_position()
            drag_end_global = drag_start_global

            # Точка на экране для рисования рамки под курсором
            drag_start_screen = get_viewport().get_mouse_position()
            drag_end_screen = drag_start_screen

            queue_redraw()
        else:
            if is_dragging:
                is_dragging = false
                _select_units_in_box()
                queue_redraw()

    if event is InputEventMouseMotion and is_dragging:
        drag_end_global = _get_world_mouse_position()
        drag_end_screen = get_viewport().get_mouse_position()
        queue_redraw()

func _draw() -> void:
    if not is_dragging: return

    # Мы в CanvasLayer с anchors на весь экран без своей трансформации,
    # поэтому локальные координаты Control'а совпадают с экранными
    # напрямую — global_position этого Control'а равен (0,0).
    var local_start = drag_start_screen - global_position
    var local_end = drag_end_screen - global_position

    var screen_size = (local_end - local_start).abs()

    # ЕСЛИ РАМКА СЛИШКОМ МАЛЕНЬКАЯ (микро-клик) — ВООБЩЕ НИЧЕГО НЕ РИСУЕМ
    if screen_size.x < 6 or screen_size.y < 6:
        return

    var rect = Rect2(local_start, local_end - local_start)

    draw_rect(rect, box_color, true)
    draw_rect(rect, border_color, false, border_width)

func _select_units_in_box() -> void:
    var selection_rect = Rect2(drag_start_global, drag_end_global - drag_start_global).abs()

    if selection_rect.size.x < 10 or selection_rect.size.y < 10:
        return

    var shift_held = Input.is_key_pressed(KEY_SHIFT)

    # Без Shift — старое выделение сбрасывается, начинаем заново.
    # С зажатым Shift — ничего не чистим: новые юниты в рамке ДОБАВЛЯЮТСЯ
    # к уже выделенным. Можно тащить рамку сколько угодно раз подряд
    # с зажатым Shift — выделение стакается.
    if not shift_held:
        SelectionManager.clear_selection()

    var all_divisions = get_tree().get_nodes_in_group("army_circles")

    for div in all_divisions:
        if not is_instance_valid(div):
            continue

        if div.division_owner != settings.active_country and settings.can_select == false:
            continue

        # Уже выделенные (в т.ч. с прошлой рамки при Shift) — пропускаем,
        # чтобы не было дублей в SelectionManager.selected_divisions.
        if div.is_selected:
            continue

        if selection_rect.has_point(div.global_position):
            SelectionManager._select_division(div)
