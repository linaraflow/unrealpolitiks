extends Node2D

const RADIUS = 10.0
const COLOR_NORMAL   = Color(0.2,   0.8,   0.2,   1.0)
const COLOR_SELECTED = Color(0.119, 0.362, 0.12,  1.0)
const COLOR_HOVER    = Color(0.15,  0.6,   0.15,  1.0)

var province_id: int  = -1
var is_selected: bool = false
var army_name:  String = ""
var soldiers: int = 0
var division_owner: String = ""

var style_normal:   StyleBoxFlat
var style_selected: StyleBoxFlat
var style_hover:    StyleBoxFlat

# ПЕРЕМЕННЫЕ ДЛЯ ОБНОВЛЕННОЙ СИСТЕМЫ ДВИЖЕНИЯ
var current_path_node: Path2D = null
var current_line_node: Line2D = null   
var is_moving: bool = false

var current_curve: Curve2D = null
var current_baked_points: PackedVector2Array
var current_movement_offset: float = 0.0
var line_growth: float = 0.0  # Отвечает за независимую анимацию появления линии
var target_destination_pos: Vector2 = Vector2.ZERO
var current_target_province_id: int = -1 # Хранит ID финальной подтвержденной провинции
var distance_since_last_check: float = 0.0
var target_owner: String = ""

var settings = preload("res://new_resource.tres")
@onready var map_node = get_node("/root/Game/Map")

func _make_circle_style(color: Color) -> StyleBoxFlat:
    var s = StyleBoxFlat.new()
    s.bg_color = color
    s.set_corner_radius_all(RADIUS)
    return s

func setup(p_id: int, name: String = "") -> void:
    province_id = p_id
    army_name   = name
    division_owner = ProvinceRegistry.province_data[str(p_id)].get("owner", "")

func _ready() -> void:
    z_index = 1 
    add_to_group("army_circles")
    
    style_normal   = _make_circle_style(COLOR_NORMAL)
    style_selected = _make_circle_style(COLOR_SELECTED)
    style_hover    = _make_circle_style(COLOR_HOVER)

    var btn      = $Button
    var diameter = RADIUS * 2
    btn.size     = Vector2(diameter, diameter)
    btn.position = Vector2(-RADIUS, -RADIUS)
    btn.text     = ""

    btn.add_theme_stylebox_override("normal",  style_normal)
    btn.add_theme_stylebox_override("hover",   style_hover)
    btn.add_theme_stylebox_override("pressed", style_hover)

    # ОПТИМИЗАЦИЯ КАМЕРЫ
    var cam = get_viewport().get_camera_2d()
    if cam:
        scale = Vector2.ONE / cam.zoom
        if cam.has_signal("zoom_changed"):
            cam.zoom_changed.connect(func(new_zoom): scale = Vector2.ONE / new_zoom)

func _process(delta: float) -> void:
    if is_moving:
        _process_movement(delta)
    elif province_id != -1:
        # Проверяем окружение, пока стоим на месте (например, если мир заключили внезапно)
        _check_if_stranded(province_id)
        if not is_queued_for_deletion():
            DivisionManager.reposition_armies_in_province(province_id)

func select() -> void:
    is_selected = true
    $Button.add_theme_stylebox_override("normal", style_selected)

func deselect() -> void:
    is_selected = false
    $Button.add_theme_stylebox_override("normal", style_normal)

func _on_button_pressed() -> void:
    SelectionManager.on_division_clicked(self)

# ─── ДИНАМИЧЕСКОЕ ДВИЖЕНИЕ И ТРАНЗИТ ДАННЫХ ────────────────────────────────────────

func start_movement_to(target_province_id: int, target_pos: Vector2) -> void:
    if province_id == target_province_id and not is_moving:
        return

    # Нельзя отступать из боя
    if CombatManager.active_battles.has(province_id):
        if CombatManager.active_battles[province_id]["sides"].has(division_owner):
            return
        
    if is_moving:
        _stop_current_movement()

    var current_p_id = _get_province_under_feet()
    
    # 1. Получаем кэшированный путь от провинции под ногами
    var provinces_path: Array = PathCache.find_path_cached(current_p_id, target_province_id, division_owner)

    # 2. ОТКАТ ЦЕЛИ: Проверяем маршрут с конца на доступность (мир/война)
    while provinces_path.size() > 0:
        var check_p_id = provinces_path[-1]
        var data = ProvinceRegistry.province_data.get(str(check_p_id), {})
        var p_owner = data.get("owner", "")
        
        # Можем зайти, если провинция: ничья, наша или врага, с которым воюем
        var can_enter = (p_owner == "" or p_owner == division_owner or ProvinceRegistry.is_at_war(division_owner, p_owner))
        
        if can_enter:
            break # Нашли ближайшую легальную цель
        else:
            provinces_path.pop_back() # Шаг назад по цепочке

    # Если легального пути нет вообще
    if provinces_path.is_empty():
        print(army_name, ": легальный путь не найден.")
        
        # Проверяем, безопасна ли провинция, в которой мы стоим сейчас
        var current_p_data = ProvinceRegistry.province_data.get(str(current_p_id), {})
        var current_owner = current_p_data.get("owner", "")
        var is_safe_here = (current_owner == "" or current_owner == division_owner or ProvinceRegistry.is_at_war(division_owner, current_owner))
        
        # Если стоим на чужой земле и идти некуда — дивизия уничтожается в окружении
        if not is_safe_here:
            _destroy_division()
        return

    # Корректируем координаты финиша, если конечная цель изменилась из-за отката
    var final_target_id = provinces_path[-1]
    if final_target_id != target_province_id:
        target_province_id = final_target_id
        target_pos = settings.province_centers.get(final_target_id, position)
        print(army_name, ": маршрут скорректирован до доступной провинции ", target_province_id)

    current_target_province_id = target_province_id
    
    var final_data = ProvinceRegistry.province_data.get(str(target_province_id), {})
    target_owner = final_data.get("owner", "")

    ProvinceRegistry.province_army_changed.emit(province_id, self)

    # 3. СТРОИМ ТОЧКИ ДЛЯ КРИВОЙ
    var points: Array[Vector2] = []
    
    # Путь ВСЕГДА начинается строго с текущей позиции кружка на карте
    points.append(position)

    # Добавляем центры промежуточных провинций
    for i in range(1, provinces_path.size() - 1):
        points.append(settings.province_centers.get(provinces_path[i], Vector2.ZERO))

    # Добавляем финальную позицию
    if provinces_path.size() > 1 or position.distance_to(target_pos) > 5.0:
        points.append(target_pos)

    if points.size() < 2:
        return

    # Генерация сплайна
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

    # 1. ДВИЖЕНИЕ КРУЖКА (зависит от паузы)
    var game_speed = 0.0
    if not GameClock.paused:
        game_speed = 150.0 * GameClock.SPEEDS[GameClock.speed_index]
    
    var move_step = game_speed * delta
    current_movement_offset += move_step
    distance_since_last_check += move_step

    var total_length = current_curve.get_baked_length()
    position = current_curve.sample_baked(current_movement_offset)

    # 2. ОТРИСОВКА ЛИНИИ (работает ВСЕГДА, даже на паузе)
    if is_instance_valid(current_line_node) and current_baked_points.size() > 1:
        var closest_index = 0
        var min_dist = INF
        for i in range(current_baked_points.size()):
            var dist = position.distance_to(current_baked_points[i])
            if dist < min_dist:
                min_dist = dist
                closest_index = i
        
        var line_draw_speed = 500.0  
        
        if total_length > 0:
            var current_speed_factor = GameClock.SPEEDS[GameClock.speed_index]
            var dynamic_line_speed = line_draw_speed * current_speed_factor
            var growth_per_second = dynamic_line_speed / total_length
            line_growth = min(line_growth + growth_per_second * delta, 1.0)
        
        var end_index = int(current_baked_points.size() * line_growth)
        end_index = clamp(end_index, closest_index, current_baked_points.size())

        var remaining_points = current_baked_points.slice(closest_index, end_index)
        
        if remaining_points.size() > 0:
            remaining_points[0] = position
        else:
            remaining_points = PackedVector2Array([position])
            
        current_line_node.points = remaining_points

    # 3. ЛОГИКА ПРОВИНЦИЙ И ФИНИША (только если игра НЕ на паузе)
    # 3. ЛОГИКА ПРОВИНЦИЙ И ФИНИША (только если игра НЕ на паузе)
    if not GameClock.paused and distance_since_last_check >= 10.0:
        distance_since_last_check = 0.0

        # ДИНАМИЧЕСКИЙ ПЕРЕРАСЧЕТ НА ХОДУ
        if current_target_province_id != -1:
            var current_t_data = ProvinceRegistry.province_data.get(str(current_target_province_id), {})
            var current_t_owner = current_t_data.get("owner", "")
            if current_t_owner != "" and current_t_owner != division_owner and not ProvinceRegistry.is_at_war(division_owner, current_t_owner):
                print(army_name, ": цель заблокирована нейтралом. Перестраиваем маршрут на лету...")
                start_movement_to(current_target_province_id, target_destination_pos)
                return

        var ground_p_id = _get_province_under_feet()
        
        if ground_p_id == province_id or ground_p_id in map_node.IGNORE_IDS:
            pass # Никаких изменений province_id и никакого ТП
            
        else:
            # 2. Оказались над полноценной ДРУГОЙ провинцией
            var ground_data = ProvinceRegistry.province_data.get(str(ground_p_id), {})
            var ground_owner = ground_data.get("owner", "")
            var can_enter = (ground_owner == "" or ground_owner == division_owner or ProvinceRegistry.is_at_war(division_owner, ground_owner))
            
            if can_enter:
                # ЛЕГАЛЬНЫЙ ПЕРЕХОД
                var enemies_in_province = false
                var circles_in_new = DivisionManager.armies.get(ground_p_id, [])
                for c in circles_in_new:
                    if is_instance_valid(c) and ProvinceRegistry.is_at_war(division_owner, c.division_owner):
                        enemies_in_province = true
                        break
                
                if not enemies_in_province:
                    if ground_owner != "" and ground_owner != division_owner:
                        if ProvinceRegistry.is_at_war(division_owner, ground_owner):
                            ProvinceRegistry.occupy_province(ground_p_id, division_owner)
                            print(army_name, " оккупировал провинцию ", ground_p_id)
                            ProvinceRegistry.province_army_changed.emit(ground_p_id) 
                                        
                _transfer_data_to(ground_p_id)
                province_id = ground_p_id

                if CombatManager.active_battles.has(ground_p_id):
                    _stop_current_movement()
                    return
            else:
                # НЕЛЕГАЛЬНЫЙ ПЕРЕХОД (чужая земля) — вот теперь ТПхаем назад
                print(army_name, " зашел на чужую провинцию ", ground_p_id, ". ТП назад.")
                _stop_current_movement() # Твоя функция сброса движения / возврата в центр старой провинции
                return

    if current_movement_offset >= total_length:
        _arrive_at_destination(target_destination_pos)

func _get_province_under_feet() -> int:
    var img_size = map_node.tech_image.get_size()
    var local_pos = position
    if map_node.centered:
        local_pos += Vector2(img_size) / 2.0
    var coords = Vector2i(local_pos).clamp(Vector2i.ZERO, img_size - Vector2i(1, 1))
    var px = map_node.tech_image.get_pixelv(coords)
    if map_node._px_to_id(px) in map_node.IGNORE_IDS:
        return province_id
    else:
        return map_node._px_to_id(px)

func _transfer_data_to(new_p_id: int) -> void:
    var old_key = str(province_id)
    var new_key = str(new_p_id)

    if not ProvinceRegistry.province_data.has(old_key) or not ProvinceRegistry.province_data.has(new_key):
        return

    var old_data = ProvinceRegistry.province_data[old_key]
    var new_data = ProvinceRegistry.province_data[new_key]

    if not new_data.has("army"):
        new_data["army"] = {"land": 0, "uav": 0, "air": 0}

    if old_data.has("army") and old_data["army"].has("land"):
        old_data["army"]["land"] -= soldiers
        if old_data["army"]["land"] < 0:
            old_data["army"]["land"] = 0

    new_data["army"]["land"] += soldiers

    if DivisionManager.armies.has(province_id):
        DivisionManager.armies[province_id].erase(self)
        if DivisionManager.armies[province_id].is_empty():
            DivisionManager.armies.erase(province_id)
            
    if not DivisionManager.armies.has(new_p_id):
        DivisionManager.armies[new_p_id] = []
        
    DivisionManager.armies[new_p_id].append(self)
    
    DivisionManager.reposition_armies_in_province(province_id)

    ProvinceRegistry.province_army_changed.emit(province_id, self)
    ProvinceRegistry.province_army_changed.emit(new_p_id, self)

    CombatManager.check_for_battle(self, province_id)
    CombatManager.check_for_battle(self, new_p_id)

func _stop_current_movement() -> void:
    if is_instance_valid(current_path_node):
        current_path_node.queue_free()
    current_line_node = null
    current_curve = null
    current_target_province_id = -1
    is_moving = false

func _arrive_at_destination(target_pos: Vector2) -> void:
    is_moving = false
    position = target_pos 
    
    if is_instance_valid(current_path_node):
        current_path_node.queue_free()
    current_line_node = null
    current_curve = null
    current_target_province_id = -1

    DivisionManager.reposition_armies_in_province(province_id)
    CombatManager.check_for_battle(self, province_id)
    print(army_name, " прибыла! Солдат внутри: ", soldiers)

# ─── ЛОГИКА ОКРУЖЕНИЯ И ХАРДКОРНОГО УНИЧТОЖЕНИЯ ───────────────────────────────────

# Метод проверки легальности нахождения в конкретной провинции
func _check_if_stranded(check_p_id: int) -> void:
    var p_data = ProvinceRegistry.province_data.get(str(check_p_id), {})
    var p_owner = p_data.get("owner", "")
    
    # Если провинция принадлежит чужой стране и войны с ней нет — это котел
    if p_owner != "" and p_owner != division_owner and not ProvinceRegistry.is_at_war(division_owner, p_owner):
        _destroy_division()

# Полная очистка данных и уничтожение дивизии без снабжения
func _destroy_division() -> void:
    print(army_name, ": осталась без снабжения и уничтожена в окружении!")
    
    # Отнимаем войска из текущей провинции в реестре данных
    var current_key = str(province_id)
    if ProvinceRegistry.province_data.has(current_key):
        var data = ProvinceRegistry.province_data[current_key]
        if data.has("army") and data["army"].has("land"):
            data["army"]["land"] -= soldiers
            if data["army"]["land"] < 0:
                data["army"]["land"] = 0
                
    # Удаляем объект из менеджера армий
    if DivisionManager.armies.has(province_id):
        DivisionManager.armies[province_id].erase(self)
        if DivisionManager.armies[province_id].is_empty():
            DivisionManager.armies.erase(province_id)
            
    # Сообщаем UI об изменениях
    ProvinceRegistry.province_army_changed.emit(province_id, self)
    
    # Чистим ноды путей и удаляем сам объект дивизии
    _stop_current_movement()
    queue_free()

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if is_instance_valid(current_path_node):
            current_path_node.queue_free()
