extends Node2D

# Размер флажка подобран так, чтобы визуально занимать примерно ту же площадь,
# что и старый кружок (диаметр 20 = RADIUS*2)
const FLAG_WIDTH  = 20.0
const FLAG_HEIGHT = 14.0

# Модуляция иконки-флага для разных состояний (вместо цвета фона кружка)
const COLOR_NORMAL   = Color(1.0,  1.0,  1.0,  1.0)
const COLOR_SELECTED = Color(0.55, 1.0,  0.55, 1.0)   # зеленоватый оттенок — выделено
const COLOR_HOVER    = Color(1.15, 1.15, 1.15, 1.0)   # чуть светлее — наведение
const COLOR_MISSILE_TARGET = Color(0.5, 0.5, 0.5, 1.0) # серый — выбрана целью ракеты

var is_missile_target: bool = false

var province_id: int  = -1
var is_selected: bool = false
var army_name:  String = ""
var soldiers: int = 0
var division_owner: String = ""

var current_path_node: Path2D = null
var current_line_node: Line2D = null   
var is_moving: bool = false

var current_curve: Curve2D = null
var current_baked_points: PackedVector2Array
var current_movement_offset: float = 0.0
var line_growth: float = 0.0  
var target_destination_pos: Vector2 = Vector2.ZERO
var current_target_province_id: int = -1 
var distance_since_last_check: float = 0.0
var target_owner: String = ""
var _cached_path_length: float = 0.0

var settings = preload("res://new_resource.tres")
@onready var map_node = get_node("/root/Game/Map")

# -----------------------------------------------------------------------------
# ОПТИМИЗАЦИЯ: раньше _process() у КАЖДОЙ армии на КАЖДЫЙ кадр:
#   1) вызывал _check_if_stranded() — ненужная работа, т.к. окружение армии
#      меняется только при смене владельца территории, а не 60 раз в секунду;
#   2) вызывал DivisionManager.reposition_armies_in_province() — эта функция
#      перебирает ВСЕ армии в провинции, т.е. если в провинции N армий и
#      каждая из них сама зовёт reposition каждый кадр — это O(N^2) в кадр
#      на одну провинцию. При 300 провинциях N было маленьким и незаметным,
#      при 10000 провинциях (и кратно выросшем числе армий) это давало
#      просадку FPS каждый кадр — отсюда лаги камеры и выделения (они не
#      виноваты сами по себе, просто общий FPS проседал).
#
# РЕШЕНИЕ:
#   - stranded-проверка теперь идёт раз в STRANDED_CHECK_INTERVAL секунд,
#     а не каждый кадр (снабжение не такая быстро меняющаяся вещь);
#   - reposition_armies_in_province() убран из ежекадрового вызова: он и так
#     вызывается в местах, где состав армий в провинции РЕАЛЬНО меняется —
#     _transfer_data_to(), _arrive_at_destination(), _destroy_division().
#     Вызывать его ещё и на каждом простаивающем юните каждый кадр было
#     чистой лишней работой без изменения состояния.
const STRANDED_CHECK_INTERVAL := 1.0
var _stranded_check_accum: float = 0.0

## Пустой (прозрачный) стиль — нужен, чтобы Button не рисовал никакого фона
## под флагом (раньше здесь была цветная заливка-кружок)
func _make_empty_style() -> StyleBoxEmpty:
    return StyleBoxEmpty.new()

## Загружает флаг страны-владельца и назначает его иконкой кнопки
func _update_flag_texture() -> void:
    if not is_inside_tree():
        return
    var btn = $Button
    if division_owner == "":
        btn.icon = null
        return

    var flag_path = "res://assets/flags/" + division_owner + ".png"
    if ResourceLoader.exists(flag_path):
        btn.icon = load(flag_path)
    else:
        print("[ArmyCircle] Флаг не найден: ", flag_path)
        btn.icon = null

func setup(p_id: int, name: String = "") -> void:
    province_id = p_id
    army_name   = name
    division_owner = ProvinceRegistry.province_data[p_id].get("owner", "")
    _update_flag_texture()

func _ready() -> void:
    z_index = 1 
    add_to_group("army_circles")

    # Разброс фазы таймера: без этого все армии, созданные в одном кадре,
    # проверяли бы stranded-статус синхронно в один и тот же кадр каждую
    # секунду, давая периодический пик нагрузки вместо равномерной.
    _stranded_check_accum = randf() * STRANDED_CHECK_INTERVAL

    var btn      = $Button
    btn.size     = Vector2(FLAG_WIDTH, FLAG_HEIGHT)
    btn.position = Vector2(-FLAG_WIDTH / 2.0, -FLAG_HEIGHT / 2.0)
    btn.text     = ""

    # Убираем фон кнопки полностью — виден будет только флаг-иконка
    var empty_style = _make_empty_style()
    btn.add_theme_stylebox_override("normal",  empty_style)
    btn.add_theme_stylebox_override("hover",   empty_style)
    btn.add_theme_stylebox_override("pressed", empty_style)

    # Флаг растягивается на всю кнопку и не режется по кругу
    btn.expand_icon = true
    btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

    btn.add_theme_color_override("icon_normal_color", COLOR_NORMAL)
    btn.add_theme_color_override("icon_hover_color",  COLOR_HOVER)
    btn.add_theme_color_override("icon_pressed_color", COLOR_HOVER)

    _update_flag_texture()

    # Размер флага не должен меняться при приближении/отдалении камеры —
    # компенсируем зум масштабом узла (как и раньше с кружком)
    var cam = get_viewport().get_camera_2d()
    if cam:
        scale = Vector2.ONE / cam.zoom
        if cam.has_signal("zoom_changed"):
            cam.zoom_changed.connect(func(new_zoom): scale = Vector2.ONE / new_zoom)

    # -------------------------------------------------------------------------
    # ОПТИМИЗАЦИЯ: при 10к провинциях одновременно может существовать много
    # тысяч ArmyCircle. Каждый из них имеет Control (Button), а Godot делает
    # обход дерева Control-нод при hit-test'е мыши (движение/клик) — чем
    # больше видимых Button на экране, тем дороже каждое движение мыши,
    # что и ощущается как лаги при выделении/наведении, особенно при
    # отдалении камеры, когда на экран попадает сразу много юнитов.
    #
    # Юниты вне экрана визуально не нужны и не должны участвовать в hit-test —
    # выключаем им mouse-обработку кнопки, когда они не видны. Игровая логика
    # (движение, stranded-проверка) НЕ завязана на видимость и продолжает
    # работать как обычно.
    var notifier = VisibleOnScreenNotifier2D.new()
    notifier.rect = Rect2(-FLAG_WIDTH / 2.0, -FLAG_HEIGHT / 2.0, FLAG_WIDTH, FLAG_HEIGHT)
    add_child(notifier)
    notifier.screen_entered.connect(func(): btn.mouse_filter = Control.MOUSE_FILTER_STOP)
    notifier.screen_exited.connect(func(): btn.mouse_filter = Control.MOUSE_FILTER_IGNORE)

func _process(delta: float) -> void:
    if is_moving:
        _process_movement(delta)
    elif province_id != -1:
        # Раз в секунду вместо каждого кадра — окружение армии (снабжение)
        # не меняется 60 раз в секунду.
        _stranded_check_accum += delta
        if _stranded_check_accum >= STRANDED_CHECK_INTERVAL:
            _stranded_check_accum = 0.0
            _check_if_stranded(province_id)
        # reposition_armies_in_province() убран отсюда — см. комментарий выше.
        # Он уже вызывается в _transfer_data_to / _arrive_at_destination /
        # _destroy_division ровно тогда, когда состав армий в провинции
        # действительно меняется.

func select() -> void:
    is_selected = true
    $Button.add_theme_color_override("icon_normal_color", COLOR_SELECTED)

func deselect() -> void:
    is_selected = false
    $Button.add_theme_color_override("icon_normal_color", COLOR_NORMAL)

## Выделение дивизии серым как цели ракеты (режим MissileMenu).
func select_missile_target() -> void:
    is_missile_target = true
    $Button.add_theme_color_override("icon_normal_color", COLOR_MISSILE_TARGET)

func deselect_missile_target() -> void:
    is_missile_target = false
    $Button.add_theme_color_override("icon_normal_color", COLOR_NORMAL)

func _on_button_pressed() -> void:
    if map_node.missile_mode:
        get_node("/root/Game/CanvasLayer/MissileMenu").on_division_clicked(self)
        return
    SelectionManager.on_division_clicked(self)

# ─── ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДОСТУПА ──────────────────────────────────────────

func _has_control_access(target_owner: String) -> bool:
    if target_owner == "" or target_owner == division_owner:
        return true
    var my_ctrl = ProvinceRegistry.countries_data.get(division_owner, {}).get("control", [])
    var their_ctrl = ProvinceRegistry.countries_data.get(target_owner, {}).get("control", [])
    return target_owner in my_ctrl or division_owner in their_ctrl

func _can_enter_territory(target_owner: String) -> bool:
    if target_owner == "" or target_owner == division_owner or target_owner == ProvinceRegistry.SEA_OWNER:
        return true
    return ProvinceRegistry.is_at_war(division_owner, target_owner) or _has_control_access(target_owner)

# ─── ДИНАМИЧЕСКОЕ ДВИЖЕНИЕ И ТРАНЗИТ ДАННЫХ ─────────────────────────────────

func start_movement_to(target_province_id: int, target_pos: Vector2) -> void:
    if province_id == target_province_id and not is_moving:
        return
    
    if CombatManager.active_battles.has(province_id) and CombatManager.active_battles[province_id]["sides"].has(division_owner):
        return
        
    if is_moving:
        _stop_current_movement()

    var current_p_id = _get_province_under_feet()
    var provinces_path: Array = PathCache.find_path_cached(current_p_id, target_province_id, division_owner)

    # Откат цели
    while provinces_path.size() > 0:
        var check_p_id = provinces_path[-1]
        var p_owner = ProvinceRegistry.province_data.get(check_p_id, {}).get("owner", "")
        
        if _can_enter_territory(p_owner):
            break
        provinces_path.pop_back()

    # Если легального пути нет вообще
    if provinces_path.is_empty():
        print(army_name, ": легальный путь не найден.")
        var current_owner = ProvinceRegistry.province_data.get(current_p_id, {}).get("owner", "")
        
        if not _can_enter_territory(current_owner):
            _destroy_division()
        return

    var final_target_id = provinces_path[-1]
    if final_target_id != target_province_id:
        target_province_id = final_target_id
        target_pos = settings.province_centers.get(final_target_id, position)
        print(army_name, ": маршрут скорректирован до доступной провинции ", target_province_id)

    current_target_province_id = target_province_id
    target_owner = ProvinceRegistry.province_data.get(target_province_id, {}).get("owner", "")
    ProvinceRegistry.province_army_changed.emit(province_id, self)

    var points: Array[Vector2] = [position]
    for i in range(1, provinces_path.size() - 1):
        points.append(settings.province_centers.get(provinces_path[i], Vector2.ZERO))
    
    if provinces_path.size() > 1 or position.distance_to(target_pos) > 5.0:
        points.append(target_pos)

    if points.size() < 2: return

    var curve = Curve2D.new()
    for i in range(points.size()):
        var p = points[i]
        var tangent: Vector2
        if i == 0: tangent = (points[1] - points[0]) * 0.3
        elif i == points.size() - 1: tangent = (points[-1] - points[-2]) * 0.3
        else: tangent = (points[i + 1] - points[i - 1]) * 0.3
        curve.add_point(p, -tangent, tangent)

    current_path_node = Path2D.new()
    current_path_node.curve = curve
    map_node.add_child(current_path_node)
    current_baked_points = curve.get_baked_points()
    _cached_path_length = curve.get_baked_length()

    var line = Line2D.new()
    line.width = 2.0
    line.default_color = Color.CYAN
    line.points = []  
    current_path_node.add_child(line)
    
    current_line_node = line
    current_curve = curve
    current_movement_offset = 0.0
    target_destination_pos = target_pos
    line_growth = 0.0  
    is_moving = true

func _process_movement(delta: float) -> void:
    if not is_instance_valid(current_curve):
        _stop_current_movement()
        return

    var game_speed = 150.0 * GameClock.SPEEDS[GameClock.speed_index] if not GameClock.paused else 0.0
    var move_step  = game_speed * delta

    current_movement_offset += move_step
    distance_since_last_check += move_step

    var total_length := _cached_path_length  # кэшированная длина (O(1))
    position = current_curve.sample_baked(current_movement_offset)

    # ── Обновление линии хвоста ─────────────────────────────────────────────
    if is_instance_valid(current_line_node) and current_baked_points.size() > 1:
        var t            = clamp(current_movement_offset / total_length, 0.0, 1.0)
        var closest_index = clamp(
            int(t * (current_baked_points.size() - 1)),
            0, current_baked_points.size() - 1
        )

        if total_length > 0:
            var growth_per_second = (1000.0 * GameClock.SPEEDS[GameClock.speed_index]) / total_length
            line_growth = min(line_growth + growth_per_second * delta, 1.0)

        var end_index = clamp(
            int(current_baked_points.size() * line_growth),
            closest_index,
            current_baked_points.size()
        )
        var remaining_points := current_baked_points.slice(closest_index, end_index)

        if remaining_points.size() > 0:
            remaining_points[0] = position
        else:
            remaining_points = PackedVector2Array([position])
        current_line_node.points = remaining_points

    # ── Проверка смены провинции ─────────────────────────────────────────────
    if not GameClock.paused and distance_since_last_check >= 10.0:
        distance_since_last_check = 0.0
        var ground_p_id  := _get_province_under_feet()
        var ground_owner = ProvinceRegistry.province_data.get(ground_p_id, {}).get("owner", "")

        if current_target_province_id != -1:
            var current_t_owner = ProvinceRegistry.province_data.get(
                current_target_province_id, {}
            ).get("owner", "")
            if not _can_enter_territory(current_t_owner):
                start_movement_to(current_target_province_id, target_destination_pos)
                return

        if ground_p_id != province_id and not ground_p_id in map_node.IGNORE_IDS:
            if _can_enter_territory(ground_owner):
                var has_access       := _has_control_access(ground_owner)
                var enemies_in_province := false
                for c in DivisionManager.armies.get(ground_p_id, []):
                    if is_instance_valid(c) and ProvinceRegistry.is_at_war(division_owner, c.division_owner) and not has_access:
                        enemies_in_province = true
                        break

                if not enemies_in_province:
                    if ground_owner != "" and ground_owner != division_owner and ground_owner != ProvinceRegistry.SEA_OWNER and not has_access:
                        ProvinceRegistry.occupy_province(ground_p_id, division_owner)
                        ProvinceRegistry.province_army_changed.emit(ground_p_id)

                _transfer_data_to(ground_p_id)
                province_id = ground_p_id

                if CombatManager.active_battles.has(ground_p_id):
                    _stop_current_movement()
                    # ФИКС БАГА 1: Репозиционируем дивизии в провинции начала боя
                    DivisionManager.reposition_armies_in_province(province_id)
                    return
            else:
                # Дивизия просто транзитом идёт/плывёт над чужой провинцией,
                # с которой нет войны и нет прав контроля — это не повод
                # останавливаться и телепортироваться назад в предыдущую
                # провинцию. Продолжаем движение по пути дальше, но сама эта
                # провинция за дивизией НЕ засчитывается: province_id не
                # меняем, _transfer_data_to() не вызываем, оккупацию не
                # запускаем — просто идём дальше.
                pass

    if current_movement_offset >= total_length:
        _arrive_at_destination(target_destination_pos)

func _get_province_under_feet() -> int:
    var img_size = map_node.tech_image.get_size()
    var local_pos = position
    if map_node.centered: local_pos += Vector2(img_size) / 2.0
    var coords = Vector2i(local_pos).clamp(Vector2i.ZERO, img_size - Vector2i(1, 1))
    var px = map_node.tech_image.get_pixelv(coords)
    var p_id = map_node._px_to_id(px)
    return province_id if p_id in map_node.IGNORE_IDS else p_id

func _transfer_data_to(new_p_id: int) -> void:
    var old_key = province_id
    var new_key = new_p_id

    if not ProvinceRegistry.province_data.has(old_key) or not ProvinceRegistry.province_data.has(new_key): return

    var old_data = ProvinceRegistry.province_data[old_key]
    var new_data = ProvinceRegistry.province_data[new_key]

    if not new_data.has("army"): new_data["army"] = {"land": 0, "uav": 0, "air": 0}

    if old_data.has("army") and old_data["army"].has("land"):
        old_data["army"]["land"] = max(0, old_data["army"]["land"] - soldiers)

    new_data["army"]["land"] += soldiers

    if DivisionManager.armies.has(province_id):
        DivisionManager.armies[province_id].erase(self)
        if DivisionManager.armies[province_id].is_empty(): DivisionManager.armies.erase(province_id)
        
    if not DivisionManager.armies.has(new_p_id): DivisionManager.armies[new_p_id] = []
    DivisionManager.armies[new_p_id].append(self)
    
    DivisionManager.reposition_armies_in_province(province_id)
    ProvinceRegistry.province_army_changed.emit(province_id, self)
    ProvinceRegistry.province_army_changed.emit(new_p_id, self)

    CombatManager.check_for_battle(self, province_id)
    CombatManager.check_for_battle(self, new_p_id)

func _stop_current_movement() -> void:
    if is_instance_valid(current_path_node): current_path_node.queue_free()
    current_line_node = null
    current_curve = null
    current_target_province_id = -1
    is_moving = false
    _cached_path_length = 0.0

func _arrive_at_destination(target_pos: Vector2) -> void:
    is_moving = false
    position = target_pos 
    if is_instance_valid(current_path_node): current_path_node.queue_free()
    current_line_node = null
    current_curve = null
    current_target_province_id = -1

    DivisionManager.reposition_armies_in_province(province_id)
    CombatManager.check_for_battle(self, province_id)
    print(army_name, " прибыла! Солдат внутри: ", soldiers)

# ─── ЛОГИКА ОКРУЖЕНИЯ И УНИЧТОЖЕНИЯ ─────────────────────────────────────────

func _check_if_stranded(check_p_id: int) -> void:
    var p_owner = ProvinceRegistry.province_data.get(check_p_id, {}).get("owner", "")
    if not _can_enter_territory(p_owner):
        _destroy_division()

func _destroy_division() -> void:
    print(army_name, ": осталась без снабжения и уничтожена в окружении!")
    
    var current_key = province_id
    if ProvinceRegistry.province_data.has(current_key):
        var data = ProvinceRegistry.province_data[current_key]
        if data.has("army") and data["army"].has("land"):
            data["army"]["land"] = max(0, data["army"]["land"] - soldiers)
                
    if DivisionManager.armies.has(province_id):
        DivisionManager.armies[province_id].erase(self)
        if DivisionManager.armies[province_id].is_empty(): DivisionManager.armies.erase(province_id)
            
    ProvinceRegistry.province_army_changed.emit(province_id, self)
    _stop_current_movement()
    queue_free()

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if is_instance_valid(current_path_node): current_path_node.queue_free()
