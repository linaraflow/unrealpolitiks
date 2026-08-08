extends Control
class_name RadialBudgetAllocator

## Круговой бюджет: 4 сектора, идущие по кругу от 12 часов по часовой стрелке.
## 0) Военные — НЕ редактируется, меняется только извне (military_upkeep).
## 1) Экономика — редактируется ручкой на границе 1|2.
## 2) Население — редактируется ручкой на границе 1|2 и ручкой на границе 2|3.
## 3) Свободный ВВП — редактируется ручкой на границе 2|3.
##
## Использование:
##   var wheel := RadialBudgetAllocator.new()
##   parent.add_child(wheel)
##   wheel.gdp = 12_000_000.0
##   wheel.military_upkeep = 1_000_000.0
##   wheel.economy_value = 4_000_000.0
##   wheel.population_value = 3_000_000.0

signal economy_changed(value: float)
signal population_changed(value: float)

@export var gdp: float = 12_000_000.0
@export var military_upkeep: float = 1_000_000.0

@export var economy_value: float = 4_000_000.0:
    set(v):
        economy_value = v
        queue_redraw()

@export var population_value: float = 3_000_000.0:
    set(v):
        population_value = v
        queue_redraw()

@export var radius: float = 90.0
@export var inner_radius: float = 40.0
@export var handle_radius: float = 9.0

var _dragging_handle: int = -1 # 0 = граница 1|2 (экономика/население), 1 = граница 2|3 (население/своб.ВВП)
var _last_mouse_angle: float = 0.0

const COLORS := {
    0: Color(0.75, 0.18, 0.18),
    1: Color(0.22, 0.5, 0.92),
    2: Color(0.24, 0.72, 0.32),
    3: Color(0.85, 0.78, 0.22),
}

const LABELS := ["Военные", "Экономика", "Население", "Своб. ВВП"]

var _font: Font


## Строит легенду (цветной квадратик + подпись для каждой секции) сеткой
## 2x2 — по два параметра в строке. Использует те же COLORS/LABELS, что и
## само колесо — не может рассинхронизироваться.
static func build_legend() -> Control:
    var column := VBoxContainer.new()
    column.name = "BudgetWheelLegend"
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_theme_constant_override("separation", 4)

    for row_start in [0, 2]:
        var row := HBoxContainer.new()
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 18)

        for i in [row_start, row_start + 1]:
            var item := HBoxContainer.new()
            item.add_theme_constant_override("separation", 6)

            var swatch := ColorRect.new()
            swatch.color = COLORS[i]
            swatch.custom_minimum_size = Vector2(14, 14)
            swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER

            var label := Label.new()
            label.text = LABELS[i]
            label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

            item.add_child(swatch)
            item.add_child(label)
            row.add_child(item)

        column.add_child(row)

    return column



func _ready() -> void:
    custom_minimum_size = Vector2((radius + 40) * 2, (radius + 40) * 2)
    mouse_filter = Control.MOUSE_FILTER_STOP
    _font = ThemeDB.fallback_font


func get_free_gdp() -> float:
    return max(gdp - military_upkeep - economy_value - population_value, 0.0)


func _get_angles() -> Array:
    var total = max(gdp, 0.001)
    var a0 := -PI / 2.0
    var a1 = a0 + TAU * (military_upkeep / total)
    var a2 = a1 + TAU * (economy_value / total)
    var a3 = a2 + TAU * (population_value / total)
    var a4 = a3 + TAU * (get_free_gdp() / total)
    return [a0, a1, a2, a3, a4]


func _center() -> Vector2:
    return size / 2.0


func _draw() -> void:
    var center := _center()
    var angles := _get_angles()
    var values := [military_upkeep, economy_value, population_value, get_free_gdp()]

    for i in range(4):
        if angles[i + 1] - angles[i] <= 0.0001:
            continue
        var points := PackedVector2Array()
        points.append(center)
        var steps: int = max(2, int(64.0 * (angles[i + 1] - angles[i]) / TAU))
        for s in range(steps + 1):
            var t: float = angles[i] + (angles[i + 1] - angles[i]) * s / float(steps)
            points.append(center + Vector2(cos(t), sin(t)) * radius)
        draw_colored_polygon(points, COLORS[i])

    draw_circle(center, inner_radius, Color(0.12, 0.12, 0.14))
    draw_arc(center, radius, 0, TAU, 64, Color(0, 0, 0, 0.35), 2.0)

    # подписи сумм по секторам — центрируем и по горизонтали, и по вертикали
    var font_size := 13
    var ascent: float = _font.get_ascent(font_size)
    var descent: float = _font.get_descent(font_size)
    for i in range(4):
        if angles[i + 1] - angles[i] <= 0.0001:
            continue
        var mid: float = (angles[i] + angles[i + 1]) / 2.0
        var label_pos: Vector2 = center + Vector2(cos(mid), sin(mid)) * (radius * 0.65)
        var txt: String = _format_money(values[i])
        var text_width: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
        var baseline: Vector2 = Vector2(
            label_pos.x - text_width / 2.0,
            label_pos.y + (ascent - descent) / 2.0
        )
        draw_string(_font, baseline, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

    # ВВП в центре — тоже по ascent/descent, без произвольных смещений
    var center_txt := "ВВП\n" + _format_money(gdp)
    var lines := center_txt.split("\n")
    var line_height: float = ascent + descent + 2.0
    var block_height: float = line_height * lines.size()
    for i in range(lines.size()):
        var lw: float = _font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
        var ly: float = center.y - block_height / 2.0 + line_height * i + ascent
        draw_string(_font, Vector2(center.x - lw / 2.0, ly), lines[i], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

    # ручки только на границах экономика|население (a2) и население|своб.ВВП (a3)
    for h_idx in [2, 3]:
        var t: float = angles[h_idx]
        var p: Vector2 = center + Vector2(cos(t), sin(t)) * radius
        draw_circle(p, handle_radius, Color.WHITE)
        draw_circle(p, handle_radius - 3, Color(0.15, 0.15, 0.15))


func _format_money(v: float) -> String:
    if v >= 1_000_000.0:
        return "%.1fM" % (v / 1_000_000.0)
    elif v >= 1_000.0:
        return "%.0fK" % (v / 1_000.0)
    return "%.0f" % v


func _mouse_angle(local_pos: Vector2) -> float:
    var dir: Vector2 = local_pos - _center()
    return atan2(dir.y, dir.x)


## Кратчайшая угловая разница a-b, всегда в диапазоне [-PI, PI].
## Без этого при переходе через границу -180/180 значение "прыгает" на TAU.
func _angle_diff(a: float, b: float) -> float:
    return wrapf(a - b, -PI, PI)


## Проверяет, попал ли клик в ручку на границе сектора h_idx.
## Вместо точного попадания в маленькую точку на окружности проверяем:
## 1) расстояние от центра — курсор должен быть где-то в пределах кольца
##    (с запасом внутрь и наружу), а не строго на радиусе;
## 2) угловое расстояние до границы сектора — с запасом в градусах,
##    который растёт по мере уменьшения радиуса, чтобы у центра тоже
##    было удобно попадать.
func _handle_hit(local_pos: Vector2, h_idx: int, angles: Array) -> bool:
    var center := _center()
    var dist: float = local_pos.distance_to(center)
    if dist < inner_radius - 15.0 or dist > radius + 25.0:
        return false

    var click_angle: float = _mouse_angle(local_pos)
    var boundary_angle: float = angles[h_idx]
    var ang_diff: float = abs(_angle_diff(click_angle, boundary_angle))

    # допуск в радианах: примерно handle_radius*2.5 пикселей дуги на текущем радиусе
    var tolerance: float = clamp((handle_radius * 3.0) / max(dist, 20.0), 0.12, 0.5)
    return ang_diff <= tolerance


func _gui_input(event: InputEvent) -> void:
    var angles := _get_angles()

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                for h_idx in [2, 3]:
                    if _handle_hit(event.position, h_idx, angles):
                        _dragging_handle = 0 if h_idx == 2 else 1
                        _last_mouse_angle = _mouse_angle(event.position)
                        accept_event()
                        return
            else:
                _dragging_handle = -1

    elif event is InputEventMouseMotion and _dragging_handle != -1:
        var current_angle: float = _mouse_angle(event.position)
        var diff: float = _angle_diff(current_angle, _last_mouse_angle)
        _last_mouse_angle = current_angle

        var value_delta: float = (diff / TAU) * gdp
        var available: float = max(gdp - military_upkeep, 0.0)

        if _dragging_handle == 0:
            # граница 1|2: тянем экономику, население компенсирует ровно на дельту
            var new_economy: float = clamp(economy_value + value_delta, 0.0, available - population_value)
            var applied_delta: float = new_economy - economy_value
            economy_value = new_economy
            population_value = clamp(population_value - applied_delta, 0.0, available - economy_value)
            economy_changed.emit(economy_value)
            population_changed.emit(population_value)

        elif _dragging_handle == 1:
            # граница 2|3: тянем население, свободный ВВП компенсируется автоматически
            population_value = clamp(population_value + value_delta, 0.0, available - economy_value)
            population_changed.emit(population_value)

        accept_event()
        queue_redraw()
