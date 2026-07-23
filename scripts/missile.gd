extends Sprite2D
## Ракета, летящая от столицы к цели по дугообразной траектории
## (та же кривая Безье, что и линия в MissileMenu/MissileLinesLayer).

var settings = preload("res://new_resource.tres")

var start_pos: Vector2
var control_pos: Vector2
var target_pos: Vector2
var target_p_id: int

# Скорость полёта ракеты (px карты/сек). Переиспользуем скорость БПЛА как базу,
# ракета летит немного быстрее.
var base_speed: float = settings.UAV_SPEED * 1.5

var _t: float = 0.0
var _path_length: float = 0.0


func _ready() -> void:
    texture = preload("res://assets/icons_uav_menu/missile_main.png")
    var tex_size = texture.get_size()
    scale = Vector2(20.0 / tex_size.x, 20.0 / tex_size.y)

    _path_length = _estimate_length()
    position = start_pos
    _update_rotation(0.0)


func _process(delta: float) -> void:
    if GameClock.paused or GameClock.speed_index == 0:
        return

    if _path_length <= 0.0:
        _arrive()
        return

    var current_speed = base_speed * GameClock.SPEEDS[GameClock.speed_index]
    _t += (current_speed * delta) / _path_length

    if _t >= 1.0:
        _arrive()
    else:
        position = _point_on_curve(_t)
        _update_rotation(_t)


func _point_on_curve(t: float) -> Vector2:
    var a: Vector2 = start_pos.lerp(control_pos, t)
    var b: Vector2 = control_pos.lerp(target_pos, t)
    return a.lerp(b, t)


func _update_rotation(t: float) -> void:
    var t2: float = min(t + 0.02, 1.0)
    var dir: Vector2 = (_point_on_curve(t2) - _point_on_curve(t))
    if dir.length() > 0.001:
        rotation = dir.angle() + (PI / 2.0)


func _estimate_length() -> float:
    var length := 0.0
    var prev := start_pos
    const SEGMENTS := 24
    for i in range(1, SEGMENTS + 1):
        var t = float(i) / float(SEGMENTS)
        var p = _point_on_curve(t)
        length += prev.distance_to(p)
        prev = p
    return length


func _arrive() -> void:
    ProvinceRegistry.missile_strike(target_p_id)
    queue_free()
