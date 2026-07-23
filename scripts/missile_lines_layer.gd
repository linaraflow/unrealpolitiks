extends Node2D
class_name MissileLinesLayer
## Слой отрисовки дугообразной линии "столица -> вражеская провинция"
## с бегущими по ней стрелочками — имитация баллистической траектории ракеты.
## Работает как UAVLinesLayer, но линия не прямая, а квадратичная кривая Безье.

const LINE_COLOR: Color = Color(1.0, 0.35, 0.1, 0.85)
const LINE_WIDTH: float = 1.5

const ARROWS_PER_LINE: int = 4
const ARROW_SPEED: float = 260.0
const ARROW_SIZE: float = 10.0

const CURVE_SEGMENTS: int = 32
const ARC_HEIGHT_RATIO: float = 0.25  # высота дуги относительно длины линии

var _has_line: bool = false
var _from: Vector2
var _to: Vector2
var _control: Vector2
var _time: float = 0.0


func _process(delta: float) -> void:
    if not _has_line:
        return
    _time += delta
    queue_redraw()


## Считает контрольную точку квадратичной кривой Безье для дуги "баллистики".
## Статическая — используется также из missile_menu.gd/missile.gd,
## чтобы визуальная линия и реальная траектория полёта совпадали.
static func compute_arc_control(from_pos: Vector2, to_pos: Vector2) -> Vector2:
    var mid: Vector2 = (from_pos + to_pos) / 2.0
    var delta: Vector2 = to_pos - from_pos
    var dist: float = delta.length()
    if dist < 1.0:
        return mid

    var perp: Vector2 = Vector2(-delta.y, delta.x).normalized()
    # Дуга всегда идёт "вверх" (в сторону -Y), чтобы траектория была похожа
    # на баллистическую независимо от взаимного расположения точек.
    if perp.y > 0:
        perp = -perp

    return mid + perp * dist * ARC_HEIGHT_RATIO


func set_line(from_pos: Vector2, to_pos: Vector2) -> void:
    _from = from_pos
    _to = to_pos
    _control = compute_arc_control(from_pos, to_pos)
    _has_line = true
    queue_redraw()


func clear_line() -> void:
    _has_line = false
    queue_redraw()


func get_point_on_curve(t: float) -> Vector2:
    var a: Vector2 = _from.lerp(_control, t)
    var b: Vector2 = _control.lerp(_to, t)
    return a.lerp(b, t)


func _draw() -> void:
    if not _has_line:
        return

    var points := PackedVector2Array()
    for i in range(CURVE_SEGMENTS + 1):
        var t = float(i) / float(CURVE_SEGMENTS)
        points.append(get_point_on_curve(t))

    for i in range(points.size() - 1):
        draw_line(points[i], points[i + 1], LINE_COLOR, LINE_WIDTH)

    _draw_conveyor_arrows(points)


func _draw_conveyor_arrows(points: PackedVector2Array) -> void:
    var seg_lengths: Array = []
    var total_len: float = 0.0
    for i in range(points.size() - 1):
        var seg_len = points[i].distance_to(points[i + 1])
        seg_lengths.append(seg_len)
        total_len += seg_len

    if total_len < 1.0:
        return

    var spacing: float = total_len / float(ARROWS_PER_LINE)

    for i in ARROWS_PER_LINE:
        var offset: float = fmod(_time * ARROW_SPEED + i * spacing, total_len)
        var result = _point_at_distance(offset, points, seg_lengths)
        var pos: Vector2 = result[0]
        var dir: Vector2 = result[1]
        var perp: Vector2 = Vector2(-dir.y, dir.x)

        var tip: Vector2 = pos + dir * (ARROW_SIZE * 0.6)
        var back_left: Vector2 = pos - dir * (ARROW_SIZE * 0.6) + perp * (ARROW_SIZE * 0.5)
        var back_right: Vector2 = pos - dir * (ARROW_SIZE * 0.6) - perp * (ARROW_SIZE * 0.5)

        var pts := PackedVector2Array([tip, back_left, back_right])
        draw_colored_polygon(pts, LINE_COLOR)


func _point_at_distance(dist: float, points: PackedVector2Array, seg_lengths: Array) -> Array:
    var accumulated: float = 0.0
    for i in range(seg_lengths.size()):
        var seg_len = seg_lengths[i]
        if accumulated + seg_len >= dist:
            var local_t: float = (dist - accumulated) / seg_len if seg_len > 0.0 else 0.0
            var pos: Vector2 = points[i].lerp(points[i + 1], local_t)
            var dir: Vector2 = (points[i + 1] - points[i]).normalized()
            return [pos, dir]
        accumulated += seg_len

    var last: Vector2 = points[points.size() - 1]
    var prev: Vector2 = points[points.size() - 2]
    return [last, (last - prev).normalized()]
