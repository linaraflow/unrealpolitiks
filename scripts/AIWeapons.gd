# =============================================================================
# AIWeapons.gd
# ИИ: БПЛА и ракетные программы (бывшие разделы 3.5 и 3.6 AIManager.gd).
# Резервы, закупка компаний/боеприпасов и удары по врагу.
#
# Класс не хранит состояния — читает/пишет его через синглтон AIManager.
# =============================================================================
class_name AIWeapons
extends RefCounted

# -----------------------------------------------------------------------------
# Кулдауны
# -----------------------------------------------------------------------------

static func tick_uav_launch_cooldown(country: String) -> void:
    if AIManager.uav_launch_cooldowns.has(country):
        AIManager.uav_launch_cooldowns[country] -= 1
        if AIManager.uav_launch_cooldowns[country] <= 0:
            AIManager.uav_launch_cooldowns.erase(country)

static func tick_missile_launch_cooldown(country: String) -> void:
    if AIManager.missile_launch_cooldowns.has(country):
        AIManager.missile_launch_cooldowns[country] -= 1
        if AIManager.missile_launch_cooldowns[country] <= 0:
            AIManager.missile_launch_cooldowns.erase(country)

# -----------------------------------------------------------------------------
# Резервы под БПЛА и ракеты (считаются вместе, за один проход по "products")
# -----------------------------------------------------------------------------

static func skim_production_reserves(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    var stock  = c_data.get("products", 0.0)
    if stock <= 0.0:
        return

    var is_at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()

    var uav_fraction     = AIManager.UAV_RESERVE_WARTIME if is_at_war else AIManager.UAV_RESERVE_PEACETIME
    var missile_fraction = AIManager.MISSILE_RESERVE_WARTIME if is_at_war else AIManager.MISSILE_RESERVE_PEACETIME

    var uav_skim     = stock * uav_fraction
    var missile_skim = stock * missile_fraction

    c_data["products"]        = stock - uav_skim - missile_skim
    c_data["uav_reserve"]     = c_data.get("uav_reserve", 0.0) + uav_skim
    c_data["missile_reserve"] = c_data.get("missile_reserve", 0.0) + missile_skim

# -----------------------------------------------------------------------------
# БПЛА
# -----------------------------------------------------------------------------

static func process_uav_program(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var balance = c_data.get("balance", 0.0)

    if not c_data.get("uav_company", false):
        var company_cost = AIManager.settings.UAV_COMPANY_COST
        if balance >= company_cost * (1.0 + AIManager.RESERVE_RATIO):
            c_data["balance"] -= company_cost
            c_data["uav_company"] = true
        return

    if ProvinceRegistry.has_active_uav_order(country):
        return

    var uav_cost: float = AIManager.settings.uav_cost
    if uav_cost <= 0.0:
        return

    var reserve = c_data.get("uav_reserve", 0.0)
    var amount = int(reserve / uav_cost)
    if amount <= 0:
        return

    var cost = amount * uav_cost

    # Резерв копится отдельно от products — на секунду возвращаем сумму в
    # products, иначе start_uav_order() провалит проверку платёжеспособности.
    c_data["products"] = c_data.get("products", 0.0) + cost

    if ProvinceRegistry.start_uav_order(country, amount):
        c_data["uav_reserve"] = reserve - cost
    else:
        c_data["products"] = c_data.get("products", 0.0) - cost

## Позиция запуска БПЛА/ракет — берём провинцию, которой страна владеет
## ПРЯМО СЕЙЧАС (не оккупирована). Если столица не оккупирована — стартуем
## из неё, иначе берём любую другую свою провинцию. Если своих провинций
## не осталось вообще (страна полностью оккупирована) — возвращаем null,
## удар не наносится.
static func _get_launch_start_pos(country: String, c_data: Dictionary):
    var owned: Array = AIManager.get_country_provinces(country)
    if owned.is_empty():
        return null

    var cap_id = int(c_data.get("capital", 0))
    var launch_id = cap_id if owned.has(cap_id) else owned[0]

    if not AIManager.settings.province_centers.has(launch_id):
        return null

    return AIManager.settings.province_centers[launch_id]

static func process_uav_strikes(country: String) -> void:
    if AIManager.uav_launch_cooldowns.has(country):
        return

    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var available = int(c_data.get("uav", 0))
    if available < AIManager.UAV_MIN_BATCH_PER_TARGET:
        return

    var targets = get_richest_enemy_factory_provinces(enemies, AIManager.UAV_MAX_TARGETS_PER_STRIKE)
    if targets.is_empty():
        return

    var drones_per_target = min(AIManager.UAV_MAX_PER_TARGET, available / targets.size())
    if drones_per_target < AIManager.UAV_MIN_BATCH_PER_TARGET:
        targets = [targets[0]]
        drones_per_target = min(AIManager.UAV_MAX_PER_TARGET, available)
        if drones_per_target < AIManager.UAV_MIN_BATCH_PER_TARGET:
            return

    var start_pos = _get_launch_start_pos(country, c_data)
    if start_pos == null:
        return

    var total_used = 0
    for target_id in targets:
        if not AIManager.settings.province_centers.has(target_id):
            continue
        launch_uav_wave(start_pos, target_id, drones_per_target, country)
        total_used += drones_per_target

    if total_used > 0:
        c_data["uav"] = available - total_used
        ProvinceRegistry.uav_order_changed.emit(country)
        AIManager.uav_launch_cooldowns[country] = AIManager.UAV_LAUNCH_COOLDOWN_DAYS

static func launch_uav_wave(start_pos: Vector2, target_id: int, amount: int, attacker_country: String = "") -> void:
    if not is_instance_valid(AIManager.Map):
        return

    var drone = Sprite2D.new()
    drone.set_script(AIManager.UAVDroneScript)
    drone.position    = start_pos
    drone.target_pos  = AIManager.settings.province_centers[target_id]
    drone.target_p_id = target_id
    drone.amount      = amount
    drone.attacker_country = attacker_country

    AIManager.Map.add_child(drone)

## Вражеские провинции (по всем врагам страны), отсортированные по убыванию
## количества фабрик. Используется и БПЛА, и ракетами — поэтому живёт здесь.
static func get_richest_enemy_factory_provinces(enemies: Array, max_count: int) -> Array:
    var candidates: Array = []

    for enemy in enemies:
        for p_id in AIManager.get_country_provinces(enemy):
            var p_data   = ProvinceRegistry.province_data.get(p_id, {})
            var factories = int(p_data.get("factories", 0))
            if factories > 0:
                candidates.append({"id": p_id, "factories": factories})

    candidates.sort_custom(func(a, b): return a["factories"] > b["factories"])

    var result: Array = []
    for entry in candidates:
        result.append(entry["id"])
        if result.size() >= max_count:
            break
    return result

# -----------------------------------------------------------------------------
# Ракеты
# -----------------------------------------------------------------------------

static func process_missile_program(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var balance = c_data.get("balance", 0.0)

    if not c_data.get("missile_company", false):
        var company_cost = AIManager.settings.MISSILE_COMPANY_COST
        if balance >= company_cost * (1.0 + AIManager.RESERVE_RATIO):
            c_data["balance"] -= company_cost
            c_data["missile_company"] = true
        return

    if ProvinceRegistry.has_active_missile_order(country):
        return

    var missile_cost: float = AIManager.settings.missile_cost
    if missile_cost <= 0.0:
        return

    var reserve = c_data.get("missile_reserve", 0.0)
    var amount = int(reserve / missile_cost)
    if amount <= 0:
        return

    var cost = amount * missile_cost

    c_data["products"] = c_data.get("products", 0.0) + cost

    if ProvinceRegistry.start_missile_order(country, amount):
        c_data["missile_reserve"] = reserve - cost
    else:
        c_data["products"] = c_data.get("products", 0.0) - cost

static func process_missile_strikes(country: String) -> void:
    if AIManager.missile_launch_cooldowns.has(country):
        return

    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var available = int(c_data.get("missile", 0))
    if available < 1:
        return

    var max_targets = min(AIManager.MISSILE_MAX_TARGETS_PER_STRIKE, available)
    var targets = get_richest_enemy_factory_provinces(enemies, max_targets)
    if targets.is_empty():
        return

    var start_pos = _get_launch_start_pos(country, c_data)
    if start_pos == null:
        return

    var total_used = 0
    for target_id in targets:
        if not AIManager.settings.province_centers.has(target_id):
            continue
        launch_missile_wave(start_pos, target_id, country)
        total_used += 1

    if total_used > 0:
        c_data["missile"] = available - total_used
        ProvinceRegistry.missile_order_changed.emit(country)
        AIManager.missile_launch_cooldowns[country] = AIManager.MISSILE_STRIKE_COOLDOWN_DAYS

static func launch_missile_wave(start_pos: Vector2, target_id: int, attacker_country: String = "") -> void:
    if not is_instance_valid(AIManager.Map):
        return

    var target_pos: Vector2 = AIManager.settings.province_centers[target_id]

    var missile = Sprite2D.new()
    missile.set_script(AIManager.MissileScript)
    missile.start_pos    = start_pos
    missile.target_pos   = target_pos
    missile.control_pos  = MissileLinesLayer.compute_arc_control(start_pos, target_pos)
    missile.target_p_id  = target_id
    missile.attacker_country = attacker_country

    AIManager.Map.add_child(missile)
