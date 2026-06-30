extends Node

@onready var BalanceLabel = get_node("/root/Game/CanvasLayer/BalanceMenu/Panel/BalanceLabel")
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
    
    # Эти строки нужно удалить/заменить, так как amount теперь приходит извне:
    # var current_pop = p_data.get("population", 0) 
    # var recruit_amount = int(current_pop * 0.01)
    
    if recruit_amount < 100:
        return
        
    # 2. Высчитываем цену (например, 0.5 монет за 1 человека)
    var cost_per_soldier = 0.5
    var total_cost = int(recruit_amount * cost_per_soldier)
    
    # 3. Проверяем баланс по новой цене
    if ProvinceRegistry.countries_data[owner_id]["balance"] < total_cost:
        return
    
    if not p_data.has("army"):
        p_data["army"] = {"land": 0, "uav": 0, "air": 0}
        
    if owner_id in ProvinceRegistry.countries_data:
        # 4. Списываем точную сумму
        ProvinceRegistry.countries_data[owner_id]["balance"] -= total_cost
        BalanceLabel.balance_update()
        
        p_data["population"] -= recruit_amount
        
    p_data["army"]["land"] += recruit_amount

    if not armies.has(province_id):
        armies[province_id] = []

    # Ищем кружок, который принадлежит именно НАМ
    var my_circle = null
    for circle in armies[province_id]:
        if is_instance_valid(circle) and circle.division_owner == owner_id:
            my_circle = circle
            break

    if my_circle != null:
        # Свой кружок найден — кидаем людей туда
        my_circle.soldiers += recruit_amount
        
        # ВАЖНО: Если идёт бой, обновляем HP стороны в CombatManager на основе новых солдат
        if CombatManager.active_battles.has(province_id):
            var sides = CombatManager.active_battles[province_id]["sides"]
            if sides.has(owner_id):
                # Так как урон теперь идет в людей, HP стороны — это просто сумма солдат
                _refresh_combat_hp_manually(province_id, owner_id)
    else:
        # Нашего кружка нет — создаем новый
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
    if not armies.has(p_id) or armies[p_id].is_empty(): 
        return
        
    var province_armies = armies[p_id]
    var count = province_armies.size()
    
    var center_pos = map_node.settings.province_centers.get(p_id, Vector2.ZERO)
    
    # 1. Получаем текущий зум камеры, прямо как в _process кружка
    var cam_factor = 1.0
    var cam = get_viewport().get_camera_2d()
    if cam:
        cam_factor = 1.0 / cam.zoom.x # Узнаем, во сколько раз увеличился визуальный размер кружка
    
    # 2. Базовый зазор между центрами (диаметр кружка 20 + 2 пикселя микро-зазора = 22)
    var base_spacing = 22.0 
    
    # 3. Умножаем зазор на cam_factor! 
    # Теперь расстояние между точками на карте будет увеличиваться ровно пропорционально росту кружков
    var spacing = base_spacing * cam_factor
    
    var total_width = (count - 1) * spacing
    var start_x = center_pos.x - (total_width / 2.0)
    
    for i in range(count):
        var army = province_armies[i]
        if not is_instance_valid(army) or army.is_moving: 
            continue
        
        var target_x = start_x + (i * spacing)
        var new_pos = Vector2(target_x, center_pos.y)
        
        # Если игра только запустилась или изменился зум, мы можем двигать кружки 
        # Но если мы используем Tween во время изменения зума, анимация будет дергаться.
        # Поэтому, если они не двигаются глобально, лучше ставить позицию мгновенно или через очень быстрый Tween.
        army.position = new_pos
        
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
