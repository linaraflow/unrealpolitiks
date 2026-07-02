extends Node

var settings = preload("res://new_resource.tres")

@onready var BalanceLabel = get_node_or_null("/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel")
const ArmyScene = preload("res://ArmyCircle.tscn")

# Теперь структура СТРОГО: { province_id(int): [кружок1, кружок2, ...] }
var armies: Dictionary = {}
var map_node: Node2D = null
var army_counters: Dictionary = {}

func recruit(province_id: int, local_pos: Vector2, recruit_amount: int):
    var p_data = ProvinceRegistry.province_data[str(province_id)]
    var owner_id = p_data.get("owner", "")
    
    if p_data.get("against_occupation", "") != "":
        return
    
    if recruit_amount < 100:
        return
        
    # УДАЛЯЕМ проверку и списание баланса
    # var cost_per_soldier = settings.COST_PER_SOLDIER
    # var total_cost = int(recruit_amount * cost_per_soldier)
    # if ProvinceRegistry.countries_data[owner_id]["balance"] < total_cost:
    #     return
    # ProvinceRegistry.countries_data[owner_id]["balance"] -= total_cost
    
    if not p_data.has("army"):
        p_data["army"] = {"land": 0, "uav": 0, "air": 0}
        
    p_data["population"] -= recruit_amount
    p_data["army"]["land"] += recruit_amount

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
        var army_name = str(army_counters[owner_id]) + " " + owner_id + " army"
        
        var army = ArmyScene.instantiate()
        map_node.add_child(army)
        army.position = local_pos
        army.soldiers = recruit_amount
        
        armies[province_id].append(army)
        army.setup(province_id, army_name)

    ProvinceRegistry.province_army_changed.emit(province_id)
    reposition_armies_in_province(province_id)

# Вспомогательный метод для быстрого обновления здоровья в бою при призыве
func _refresh_combat_hp_manually(province_id: int, owner_id: String):
    var battle = CombatManager.active_battles[province_id]
    var total_soldiers = 0
    for circle in armies[province_id]:
        if is_instance_valid(circle) and circle.division_owner == owner_id:
            total_soldiers += circle.soldiers
    battle["sides"][owner_id]["hp"] = total_soldiers
    if total_soldiers > battle["sides"][owner_id]["max_hp"]:
        battle["sides"][owner_id]["max_hp"] = total_soldiers

# Шеренга работает моментально, потому что массив под рукой!
func reposition_armies_in_province(p_id: int) -> void:
    var center_pos = map_node.settings.province_centers.get(p_id, Vector2.ZERO)
    var cam_factor = 1.0
    var cam = get_viewport().get_camera_2d()
    if cam:
        cam_factor = 1.0 / cam.zoom.x
    
    var base_spacing = 22.0
    var spacing = base_spacing * cam_factor
    
    # Позиционируем только армии (логика заводов полностью удалена)
    if armies.has(p_id) and not armies[p_id].is_empty():
        var province_armies = armies[p_id]
        var total_width = (province_armies.size() - 1) * spacing
        var start_x = center_pos.x - (total_width / 2.0)
        
        for i in range(province_armies.size()):
            var army = province_armies[i]
            if is_instance_valid(army) and not army.is_moving:
                army.position = Vector2(start_x + (i * spacing), center_pos.y)
        
        
## Скрывает/показывает дивизии в зависимости от режима переговоров.
## countries — массив из двух стран-участников, например ["Germany", "France"].
## Передай пустой массив [] чтобы показать всех обратно.
func set_negotiation_visibility(countries: Array) -> void:
    for p_id in armies:
        # Чья земля эта провинция?
        var province_owner = ProvinceRegistry.province_data.get(str(p_id), {}).get("owner", "")
        var on_negotiation_territory = countries.size() > 0 and (province_owner in countries)

        for circle in armies[p_id]:
            if not is_instance_valid(circle):
                continue

            circle.visible = not on_negotiation_territory

            if is_instance_valid(circle.current_path_node):
                circle.current_path_node.visible = not on_negotiation_territory
