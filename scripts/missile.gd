extends Sprite2D
## Ракета, летящая от столицы к цели по дугообразной траектории
## (та же кривая Безье, что и линия в MissileMenu/MissileLinesLayer).

var settings = preload("res://new_resource.tres")

var start_pos: Vector2
var control_pos: Vector2
var target_pos: Vector2
var target_p_id: int
var attacker_country: String = "" # Страна, запустившая ракету (для начисления продукта за уничтоженные фабрики)

# Дивизия-цель (ArmyCircle), за которой наводится ракета. Пока она жива —
# ракета каждый кадр довoрачивает на её текущую позицию/провинцию.
# Если дивизия погибла до попадания — ракета долетает по последнему
# известному курсу и бьёт по последней известной провинции цели.
var target_division: Node = null

# Порог смещения цели (px), ниже которого курс не пересчитывается —
# защита от лишней работы при неподвижной/почти неподвижной цели.
const _RETARGET_EPS: float = 0.5

# Скорость полёта ракеты (px карты/сек). Переиспользуем скорость БПЛА как базу,
# ракета летит немного быстрее.
var base_speed: float = settings.UAV_SPEED * 1.5

var _t: float = 0.0
var _path_length: float = 0.0

# ── Неоновый след ракеты ────────────────────────────────────────────────
# Две Line2D с аддитивным блендом: широкая полупрозрачная (свечение) +
# тонкая яркая (ядро). Без CanvasGroup/шейдера — тот подход давал видимые
# артефакты (серые пятна), которые росли при отдалении камеры из-за того,
# что буфер CanvasGroup завязан на масштаб экрана. Этот вариант стабилен
# при любом зуме.
const TRAIL_GLOW_COLOR: Color = Color(1.0, 0.05, 0.15, 0.8)
const TRAIL_CORE_COLOR: Color = Color(1.0, 0.75, 0.8, 1.0)

const TRAIL_GLOW_WIDTH: float = 3.0
const TRAIL_CORE_WIDTH: float = 1.0

const TRAIL_FADE_OUT_TIME: float = 0.5  # плавное исчезновение после попадания

var _glow_line: Line2D
var _core_line: Line2D


func _ready() -> void:
    z_index = 2
    texture = preload("res://assets/icons_uav_menu/missile_main.png")
    var tex_size = texture.get_size()
    scale = Vector2(20.0 / tex_size.x, 20.0 / tex_size.y)

    _path_length = _estimate_length()
    position = start_pos
    _update_rotation(0.0)

    _create_trail()


## Создаёт узлы следа как детей родителя ракеты (Map), а не самой ракеты —
## иначе точки следа двигались бы вместе с ракетой вместо того, чтобы
## оставаться на карте.
func _create_trail() -> void:
    var parent := get_parent()
    if parent == null:
        return

    _glow_line = _make_trail_line(TRAIL_GLOW_WIDTH, TRAIL_GLOW_COLOR)
    _glow_line.z_index = 50
    var mat := CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # аддитивный бленд = свечение
    _glow_line.material = mat
    parent.add_child(_glow_line)

    _core_line = _make_trail_line(TRAIL_CORE_WIDTH, TRAIL_CORE_COLOR)
    _core_line.z_index = 51
    _core_line.material = mat
    parent.add_child(_core_line)

    _glow_line.add_point(start_pos)
    _core_line.add_point(start_pos)


func _make_trail_line(width: float, color: Color) -> Line2D:
    var line := Line2D.new()
    line.width = width
    line.default_color = color
    line.joint_mode = Line2D.LINE_JOINT_ROUND
    line.begin_cap_mode = Line2D.LINE_CAP_ROUND
    line.end_cap_mode = Line2D.LINE_CAP_ROUND
    line.antialiased = true

    # Хвост (старые точки, offset 0) прозрачный, голова (свежие точки,
    # offset 1) полностью яркая — плавное затухание следа "на лету".
    var grad := Gradient.new()
    grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
    grad.set_color(1, color)
    line.gradient = grad
    line.z_index = 2
    
    return line


func _extend_trail(p: Vector2) -> void:
    if _glow_line:
        _glow_line.add_point(p)
    if _core_line:
        _core_line.add_point(p)


func _process(delta: float) -> void:
    if GameClock.paused or GameClock.speed_index == 0:
        return

    _update_homing()

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
        _extend_trail(position)


## Наведение по живой дивизии: если цель ещё существует, каждый кадр
## перестраиваем дугу от ТЕКУЩЕЙ позиции ракеты к НОВОЙ позиции дивизии
## (и обновляем target_p_id — провинцию, по которой ударит ракета при
## попадании). Если дивизия сменила провинцию — ракета доворачивает
## следом. Если дивизия уничтожена по пути — просто перестаём её
## отслеживать и долетаем по последнему курсу.
func _update_homing() -> void:
    if not is_instance_valid(target_division):
        return

    target_p_id = target_division.province_id

    var new_target: Vector2 = target_division.position
    if new_target.distance_to(target_pos) < _RETARGET_EPS:
        return

    start_pos = position
    target_pos = new_target
    control_pos = MissileLinesLayer.compute_arc_control(start_pos, target_pos)
    _t = 0.0
    _path_length = _estimate_length()


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
    ProvinceRegistry.missile_strike(target_p_id, attacker_country)
    _fade_out_trail()
    queue_free()


## Плавно гасит след после попадания и убирает его с карты.
## Трейл — отдельные узлы (дети Map), поэтому queue_free() самой ракеты
## их не затрагивает, и tween успевает доиграть после исчезновения ракеты.
func _fade_out_trail() -> void:
    var layers := [_glow_line, _core_line]

    var any_valid := false
    for l in layers:
        if is_instance_valid(l):
            any_valid = true
    if not any_valid:
        return

    var tree := get_tree()
    if tree == null:
        return

    var tw := tree.create_tween()
    tw.set_parallel(true)

    for l in layers:
        if is_instance_valid(l):
            tw.tween_property(l, "modulate:a", 0.0, TRAIL_FADE_OUT_TIME) \
                .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

    tw.chain().tween_callback(func():
        for l in layers:
            if is_instance_valid(l):
                l.queue_free()
    )
