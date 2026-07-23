extends Node2D
class_name UAVLinesLayer
## Слой отрисовки тонких линий "столица -> вражеская провинция" и бегущих
## по ним стрелочек-"конвейера" в режиме UAVMenu.
##
## Добавляется как child-нода Map (Sprite2D) в map.gd, поэтому использует
## ту же локальную систему координат, что и Map.province_centers —
## никаких дополнительных пересчётов позиций не требуется.

const LINE_COLOR: Color = Color(1.0, 0.35, 0.1, 0.85)
const LINE_WIDTH: float = 1.5

const ARROWS_PER_LINE: int = 4     # сколько стрелочек одновременно бежит по одной линии
const ARROW_SPEED: float = 220.0   # скорость движения стрелочек, px карты/сек
const ARROW_SIZE: float = 10.0     # размер треугольника стрелки

# Array[Dictionary]: {"from": Vector2, "to": Vector2}
var _lines: Array = []
var _time: float = 0.0


func _process(delta: float) -> void:
    if _lines.is_empty():
        return
    _time += delta
    queue_redraw()


## from_pos — локальная позиция столицы (Map.province_centers[cap_id]).
## target_positions — Array[Vector2], локальные позиции выбранных вражеских провинций.
func set_lines(from_pos: Vector2, target_positions: Array) -> void:
    _lines.clear()
    for target_pos in target_positions:
        _lines.append({"from": from_pos, "to": target_pos})
    queue_redraw()


func clear_lines() -> void:
    _lines.clear()
    queue_redraw()


func _draw() -> void:
    for line in _lines:
        var from_pos: Vector2 = line["from"]
        var to_pos: Vector2 = line["to"]

        draw_line(from_pos, to_pos, LINE_COLOR, LINE_WIDTH)
        _draw_conveyor_arrows(from_pos, to_pos)


func _draw_conveyor_arrows(from_pos: Vector2, to_pos: Vector2) -> void:
    var delta: Vector2 = to_pos - from_pos
    var dist: float = delta.length()
    if dist < 1.0:
        return

    var dir: Vector2 = delta / dist
    var perp: Vector2 = Vector2(-dir.y, dir.x)
    var spacing: float = dist / float(ARROWS_PER_LINE)

    for i in ARROWS_PER_LINE:
        # Каждая стрелка едет от from к to и зацикливается — эффект конвейера
        var offset: float = fmod(_time * ARROW_SPEED + i * spacing, dist)
        var pos: Vector2 = from_pos + dir * offset

        var tip: Vector2 = pos + dir * (ARROW_SIZE * 0.6)
        var back_left: Vector2 = pos - dir * (ARROW_SIZE * 0.6) + perp * (ARROW_SIZE * 0.5)
        var back_right: Vector2 = pos - dir * (ARROW_SIZE * 0.6) - perp * (ARROW_SIZE * 0.5)

        var pts := PackedVector2Array([tip, back_left, back_right])
        draw_colored_polygon(pts, LINE_COLOR)
