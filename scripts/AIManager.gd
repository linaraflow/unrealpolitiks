extends Node

var settings = preload("res://new_resource.tres")

# Ссылка на интерфейс баланса (путь взят из твоего DivisionManager)
@onready var balance_label = get_node_or_null("/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel")

func _ready() -> void:
    # Военную логику (передвижение) оставляем раз в месяц, чтобы не спамить командами
    GameClock.on_month_passed.connect(_on_month_passed)
    
    GameClock.on_day_passed.connect(_on_day_passed_population)
    # Добавляем вызов найма для ИИ раз в день
    GameClock.on_day_passed.connect(_on_day_passed_ai_recruitment)
    # Добавляем продажу товаров для ИИ раз в день
    GameClock.on_day_passed.connect(_on_day_passed_ai_trading)

    # Сразу считаем monthly_income при старте игры, чтобы не ждать первого месяца
    for country in ProvinceRegistry.countries_data.keys():
        _update_monthly_income(country)

func _process(delta: float) -> void:
    if GameClock.paused:
        return

    _process_per_frame_economy(delta)

func _process_per_frame_economy(delta: float) -> void:
    # Считаем, сколько реальных секунд длится один игровой месяц
    var total_seconds_in_month = 30.0 * GameClock.SECONDS_PER_DAY
    var current_speed = GameClock.SPEEDS[GameClock.speed_index]

    for country in ProvinceRegistry.countries_data.keys():
        var c_data = ProvinceRegistry.countries_data[country]
        
        # Получаем месячный доход конкретной страны (по умолчанию берем 100000, если ключа нет)
        var country_monthly = c_data.get("monthly_income", 100000.0)
        
        # Вычисляем доход за одну секунду, а затем умножаем на delta и скорость
        var income_per_second = country_monthly / total_seconds_in_month
        var c_income = income_per_second * delta * current_speed
        
        c_data["balance"] = c_data.get("balance", 0.0) + c_income
        
        # _process_ai_recruitment убрано отсюда, чтобы не спамить проверками каждый кадр

    if is_instance_valid(balance_label) and settings.can_draw:
        balance_label.balance_update()

# --- НОВЫЙ МЕТОД ---
# Ежедневная проверка возможности найма войск для ботов
func _on_day_passed_ai_recruitment(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data.keys():
        if country != settings.active_country:
            _process_ai_recruitment(country)
            _process_ai_economy(country)

func _process_ai_recruitment(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    var my_provinces = _get_country_provinces(country)
    if my_provinces.is_empty(): 
        return
        
    var target_p_id = my_provinces.pick_random()
    var p_data = ProvinceRegistry.province_data[str(target_p_id)]
    
    # Бот рассчитывает 1% от населения провинции
    var pop = p_data.get("population", 0)
    var recruit_amount = int(pop * 0.01)
    
    # Если рекрутов меньше 100, призыв не происходит
    if recruit_amount < 100:
        return
        
    # Считаем стоимость (0.5 за солдата)
    var cost = recruit_amount * settings.COST_PER_SOLDIER

    # Если у бота хватает денег, он мгновенно нанимает войска
    if c_data.get("balance", 0.0) >= cost:
        # Списываем деньги у бота перед наймом (ВАЖНО! Ранее этого не было в твоем коде)
        c_data["balance"] -= cost 
        
        var local_pos = settings.province_centers.get(target_p_id, Vector2.ZERO)
        # Передаем amount третьим аргументом
        DivisionManager.recruit(target_p_id, local_pos, recruit_amount)

# --- НОВЫЙ МЕТОД ---
# Ежедневная проверка возможности продать накопленные товары для ботов
func _on_day_passed_ai_trading(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data.keys():
        if country != settings.active_country:
            _process_ai_trade(country)

func _process_ai_trade(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    var current_stock = c_data.get("products", 0.0)

    if current_stock <= 0:
        return

    # Бот продаёт весь накопленный запас товаров по текущей цене
    var revenue = current_stock * settings.product_cost

    c_data["products"] = 0.0
    c_data["balance"] = c_data.get("balance", 0.0) + revenue

func _on_month_passed(date: Dictionary) -> void:
    # Пересчитываем месячный доход (налоги) для ВСЕХ стран, включая игрока
    for country in ProvinceRegistry.countries_data.keys():
        _update_monthly_income(country)

    for country in ProvinceRegistry.countries_data.keys():
        if country == settings.active_country:
            continue
        _process_ai_military(country)
        _process_ai_diplomacy(country)

# --- НОВЫЙ МЕТОД ---
# Считает и записывает monthly_income страны по формуле: население * 100 (налоги)
func _update_monthly_income(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    var income = _calculate_monthly_income(country)
    c_data["monthly_income"] = income

func _calculate_monthly_income(country: String) -> float:
    var total_population = _get_country_population(country)
    return float(total_population) * 1.0

func _get_country_population(country: String) -> int:
    var total_population = 0
    for p_id in _get_country_provinces(country):
        var p_data = ProvinceRegistry.province_data.get(str(p_id), {})
        total_population += int(p_data.get("population", 0))
    return total_population

func _process_ai_military(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return
        
    var my_provinces = _get_country_provinces(country)
    var enemy_provinces = []
    
    for e in enemies:
        enemy_provinces.append_array(_get_country_provinces(e))
        
    if enemy_provinces.is_empty(): 
        return
    
    # Обычная атака, если паники нет
    for p_id in my_provinces:
        if CombatManager.active_battles.has(p_id):
            continue
        var province_armies = DivisionManager.armies.get(p_id, [])
        for army in province_armies:
            if is_instance_valid(army) and army.division_owner == country and not army.is_moving:
                var target_enemy_p_id = enemy_provinces.pick_random()
                var target_pos = settings.province_centers.get(target_enemy_p_id, Vector2.ZERO)
                army.start_movement_to(target_enemy_p_id, target_pos)
                
func _process_ai_diplomacy(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    
    # 1. Шанс заключить мир (если бот уже с кем-то воюет)
    if not enemies.is_empty():
        # Например, 10% шанс на перемирие каждый игровой месяц
        if randf() < 0.10: 
            var target_enemy = enemies.pick_random()
            # Чтобы бот не мирился с игроком сам по себе, можно добавить проверку:
            if target_enemy != settings.active_country:
                ProvinceRegistry.end_war(country, target_enemy)
        return # Если воюем, новые войны пока не начинаем (чтобы бот не воевал со всем миром)

    # 2. Шанс объявить войну (если бот сейчас ни с кем не воюет)
    if enemies.is_empty():
        # Например, 3% шанс напасть на соседа в этом месяце
        if randf() < 0.03: 
            var neighbor = _get_random_neighbor_country(country)
            print(country, " ищет жертву. Найден сосед: ", neighbor)
            if neighbor != "" and neighbor != country:
                ProvinceRegistry.declare_war(country, neighbor)

func _process_ai_economy(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    
    if c_data.get("balance", 0.0) >= settings.factory_cost + (settings.factory_cost / 2):
        var my_provinces = _get_country_provinces(country)
        var safe_provinces = []
        
        for p_id in my_provinces:
            var p_data = ProvinceRegistry.province_data.get(str(p_id), {})
            # Бот проверяет: провинция не в бою, не оккупирована, и очередь заводов МЕНЬШЕ 5
            if not CombatManager.active_battles.has(p_id) and not ProvinceRegistry.is_occupied(p_id):
                if p_data.get("factory_queue", []).size() < 5:
                    safe_provinces.append(p_id)
                
        if not safe_provinces.is_empty():
            var target_p = safe_provinces.pick_random()
            ProvinceRegistry.start_factory_construction(target_p, country)

func _on_day_passed_population(_date: Dictionary) -> void:
    var population_migration: Dictionary = {}

    for p_id_str in ProvinceRegistry.province_data.keys():
        var p_id = int(p_id_str)
        var p_data = ProvinceRegistry.province_data[p_id_str]
        var current_pop = int(p_data.get("population", 0))
        
        if current_pop <= 0:
            continue
            
        if CombatManager.active_battles.has(p_id):
            var loss = int(current_pop * 0.005)
            if loss > 0:
                population_migration[p_id] = population_migration.get(p_id, 0) - loss
                _distribute_refugees(p_id, loss, population_migration)
        elif ProvinceRegistry.is_occupied(p_id):
            var loss = int(current_pop * 0.0003)
            if loss > 0:
                population_migration[p_id] = population_migration.get(p_id, 0) - loss
                _distribute_refugees(p_id, loss, population_migration)
        else:
            var growth = int(current_pop * 0.0001)
            if growth > 0:
                population_migration[p_id] = population_migration.get(p_id, 0) + growth

    # Применяем изменения
    for p_id in population_migration:
        var key = str(p_id)
        if ProvinceRegistry.province_data.has(key):
            var new_pop = int(ProvinceRegistry.province_data[key].get("population", 0)) + population_migration[p_id]
            ProvinceRegistry.province_data[key]["population"] = max(0, new_pop)
            
    ProvinceRegistry._recalculate_all_populations()


func _get_random_neighbor_country(country: String) -> String:
    var neighbors = []
    var my_provinces = _get_country_provinces(country)
    
    for p_id in my_provinces:
        var adjacencies = ProvinceRegistry.province_adjacency.get(str(p_id), [])
        
        for adj_id in adjacencies:
            # Превращаем 27.0 -> 27 -> "27"
            var clean_id = str(int(adj_id)) 
            var p_data = ProvinceRegistry.province_data.get(clean_id, {})
            var owner = p_data.get("owner", "")
            
            if owner != "" and owner != country and not neighbors.has(owner):
                neighbors.append(owner)
                
    if neighbors.is_empty():
        return ""
        
    return neighbors.pick_random()

func _get_country_provinces(country: String) -> Array:
    var result = []
    for p_id in ProvinceRegistry.province_data.keys():
        if ProvinceRegistry.province_data[p_id].get("owner", "") == country:
            result.append(int(p_id))
    return result
    
func _find_nearest_safe_province(start_p_id: int) -> int:
    var queue = [start_p_id]
    var visited = {start_p_id: true}
    
    while not queue.is_empty():
        var current_id = queue.pop_front()
        
        # Если это не стартовая провинция и она безопасна — нашли
        if current_id != start_p_id:
            var is_battle = CombatManager.active_battles.has(current_id)
            var is_occupied = ProvinceRegistry.is_occupied(current_id)
            if not is_battle and not is_occupied:
                return current_id
        
        # Смотрим соседей (с кастом из JSON, как в твоем _get_random_neighbor_country)
        var adjacencies = ProvinceRegistry.province_adjacency.get(str(current_id), [])
        for adj_id in adjacencies:
            var next_id = int(adj_id)
            if not visited.has(next_id):
                visited[next_id] = true
                queue.append(next_id)
                
    return -1 # Если всё вокруг в огне, беженцы гибнут
    
func _distribute_refugees(from_p_id: int, amount: int, migration_dict: Dictionary) -> void:
    var safe_p_id = _find_nearest_safe_province(from_p_id)
    if safe_p_id != -1:
        migration_dict[safe_p_id] = migration_dict.get(safe_p_id, 0) + amount