extends Node

var settings = preload("res://new_resource.tres")

@onready var BalanceLabel = get_node_or_null("/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel")
const ArmyScene = preload("res://ArmyCircle.tscn")

# Теперь структура СТРОГО: { province_id(int): [кружок1, кружок2, ...] }
var armies: Dictionary = {}
var army_counters: Dictionary = {}

var _cached_cam_factor: float = 1.0

# ФИКС БАГА 2: Автоматически подписываемся на камеру при инициализации карты
var map_node: Node2D = null:
    set(value):
        map_node = value
        if map_node:
            call_deferred("_connect_camera_signals")

func _connect_camera_signals() -> void:
    var cam = get_viewport().get_camera_2d()
    if cam:
        _cached_cam_factor = 1.0 / cam.zoom.x
        if cam.has_signal("zoom_changed"):
            if cam.zoom_changed.is_connected(_on_viewport_zoom_changed):
                cam.zoom_changed.disconnect(_on_viewport_zoom_changed)
            cam.zoom_changed.connect(_on_viewport_zoom_changed)

func _on_viewport_zoom_changed(new_zoom: Vector2) -> void:
    _cached_cam_factor = 1.0 / new_zoom.x
    reposition_all_armies()

# ФИКС БАГА 2: Масштабируем зазор между армиями на лету при изменении зума
func reposition_all_armies() -> void:
    if not is_instance_valid(map_node):
        return
    for p_id in armies:
        reposition_armies_in_province(p_id, _cached_cam_factor)

func recruit(province_id: int, local_pos: Vector2, recruit_amount: int):
    var p_data = ProvinceRegistry.province_data[province_id]
    var owner_id = p_data.get("owner", "")
    
    if p_data.get("against_occupation", "") != "":
        return
    
    if recruit_amount < 100:
        return
    
    if not p_data.has("army"):
        p_data["army"] = {"land": 0, "uav": 0, "air": 0}
        
    p_data["population"] -= recruit_amount
    p_data["army"]["land"] += recruit_amount

    # Содержание новобранцев сразу ложится на месячный доход страны (O(1))
    ProvinceRegistry.adjust_monthly_income_for_troops(owner_id, recruit_amount)

    if not armies.has(province_id):
        armies[province_id] = []

    var my_circle = null
    for circle in armies[province_id]:
        if is_instance_valid(circle) and circle.division_owner == owner_id:
            my_circle = circle
            break

    if my_circle != null:
        my_circle.soldiers += recruit_amount
        if CombatManager.active_battles.has(province_id):
            var sides = CombatManager.active_battles[province_id]["sides"]
            if sides.has(owner_id):
                _refresh_combat_hp_manually(province_id, owner_id)
    else:
        army_counters[owner_id] = army_counters.get(owner_id, 0) + 1
        var army_name = str(army_counters[owner_id]) + " " + str(owner_id) + " army"
        
        var army = ArmyScene.instantiate()
        map_node.add_child(army)
        army.position = local_pos
        army.soldiers = recruit_amount
        
        armies[province_id].append(army)
        army.setup(province_id, army_name)

    ProvinceRegistry.province_army_changed.emit(province_id)
    reposition_armies_in_province(province_id)

func _refresh_combat_hp_manually(province_id: int, owner_id: String):
    var battle = CombatManager.active_battles[province_id]
    var total_soldiers = 0
    for circle in armies[province_id]:
        if is_instance_valid(circle) and circle.division_owner == owner_id:
            total_soldiers += circle.soldiers
    battle["sides"][owner_id]["hp"] = total_soldiers
    if total_soldiers > battle["sides"][owner_id]["max_hp"]:
        battle["sides"][owner_id]["max_hp"] = total_soldiers

# Объединяет все дивизии одного владельца в провинции в одну (первую) дивизию.
# Остальные дивизии удаляются, все солдаты переносятся в первую.
func merge_divisions(province_id: int) -> void:
    if not armies.has(province_id):
        return

    var province_armies = armies[province_id]

    # Группируем валидные (не уничтоженные, не в движении) дивизии по владельцу
    var groups: Dictionary = {} # owner_id -> Array[circle]
    for circle in province_armies:
        if not is_instance_valid(circle):
            continue
        if circle.is_moving:
            continue # не трогаем дивизии, которые сейчас в пути

        var owner_id = circle.division_owner
        if not groups.has(owner_id):
            groups[owner_id] = []
        groups[owner_id].append(circle)

    var affected_owners: Array = []

    for owner_id in groups:
        var group: Array = groups[owner_id]
        if group.size() <= 1:
            continue # объединять нечего

        var main_circle = group[0]
        var total_soldiers = 0
        for circle in group:
            total_soldiers += circle.soldiers

        main_circle.soldiers = total_soldiers

        # Удаляем все остальные дивизии этого владельца
        for i in range(1, group.size()):
            var circle_to_remove = group[i]
            province_armies.erase(circle_to_remove)
            if is_instance_valid(circle_to_remove.current_path_node):
                circle_to_remove._stop_current_movement()
            circle_to_remove.queue_free()

        affected_owners.append(owner_id)

    if affected_owners.is_empty():
        return

    for owner_id in affected_owners:
        if CombatManager.active_battles.has(province_id):
            var sides = CombatManager.active_battles[province_id]["sides"]
            if sides.has(owner_id):
                _refresh_combat_hp_manually(province_id, owner_id)

    ProvinceRegistry.province_army_changed.emit(province_id)
    reposition_armies_in_province(province_id)
    
## Уничтожает kill_ratio (0..1) личного состава ВСЕХ дивизий в провинции
## (используется ракетным ударом: kill_ratio = 0.9 → уничтожает 90% людей).
## Дивизии, у которых солдат осталось <= 0, удаляются полностью.
func kill_percent_in_province(province_id: int, kill_ratio: float) -> void:
    if not armies.has(province_id):
        return

    var province_armies = armies[province_id]
    var owners_lost: Dictionary = {} # owner_id -> total_lost

    for circle in province_armies.duplicate():
        if not is_instance_valid(circle):
            continue

        var lost = int(round(circle.soldiers * kill_ratio))
        if lost <= 0:
            continue

        circle.soldiers -= lost
        owners_lost[circle.division_owner] = owners_lost.get(circle.division_owner, 0) + lost

        if circle.soldiers <= 0:
            province_armies.erase(circle)
            if is_instance_valid(circle.current_path_node):
                circle._stop_current_movement()
            circle.queue_free()

    if owners_lost.is_empty():
        return

    var p_data = ProvinceRegistry.province_data.get(province_id, {})
    if p_data.has("army"):
        var total_lost = 0
        for owner_id in owners_lost:
            total_lost += owners_lost[owner_id]
        p_data["army"]["land"] = max(0, p_data["army"].get("land", 0) - total_lost)

    for owner_id in owners_lost:
        ProvinceRegistry.adjust_monthly_income_for_troops(owner_id, -owners_lost[owner_id])

    for owner_id in owners_lost:
        if CombatManager.active_battles.has(province_id):
            var sides = CombatManager.active_battles[province_id]["sides"]
            if sides.has(owner_id):
                _refresh_combat_hp_manually(province_id, owner_id)

    ProvinceRegistry.province_army_changed.emit(province_id)
    reposition_armies_in_province(province_id)
    print("[DivisionManager] Ракетный удар: потери личного состава в провинции ", province_id, " -> ", owners_lost)

# ФИКС БАГА 2: Оптимизированное позиционирование с использованием кэшированного cam_factor
func reposition_armies_in_province(p_id: int, cam_factor: float = -1.0) -> void:
    if not is_instance_valid(map_node):
        return

    var center_pos = map_node.settings.province_centers.get(p_id, Vector2.ZERO)
    
    if cam_factor < 0.0:
        if _cached_cam_factor == 1.0:
            var cam = get_viewport().get_camera_2d()
            if cam:
                _cached_cam_factor = 1.0 / cam.zoom.x
        cam_factor = _cached_cam_factor
    
    var base_spacing = 22.0
    var spacing = base_spacing * cam_factor
    
    if armies.has(p_id) and not armies[p_id].is_empty():
        var province_armies = armies[p_id]
        var total_width = (province_armies.size() - 1) * spacing
        var start_x = center_pos.x - (total_width / 2.0)
        
        for i in range(province_armies.size()):
            var army = province_armies[i]
            if is_instance_valid(army) and not army.is_moving:
                army.position = Vector2(start_x + (i * spacing), center_pos.y)
        
func set_negotiation_visibility(countries: Array) -> void:
    for p_id in armies:
        var province_owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")
        var on_negotiation_territory = countries.size() > 0 and (province_owner in countries)

        for circle in armies[p_id]:
            if not is_instance_valid(circle):
                continue

            circle.visible = not on_negotiation_territory

            if is_instance_valid(circle.current_path_node):
                circle.current_path_node.visible = not on_negotiation_territory




## RESET
## Удаляет все дивизии со сцены (в т.ч. те, что сейчас в движении между провинциями)
func reset() -> void:
    for p_id in armies:
        for circle in armies[p_id]:
            if is_instance_valid(circle):
                if is_instance_valid(circle.current_path_node):
                    circle._stop_current_movement()
                circle.queue_free()
    armies = {}
    army_counters = {}
