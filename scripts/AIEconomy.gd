# =============================================================================
# AIEconomy.gd
# ИИ: строительство фабрик (бывший раздел 3 AIManager.gd).
#
# Класс не хранит собственного состояния — все функции static и читают/пишут
# общие данные (кулдауны, settings, кэши провинций) через синглтон AIManager.
# =============================================================================
class_name AIEconomy
extends RefCounted

static func tick_factory_cooldown(country: String) -> void:
    if AIManager.factory_cooldowns.has(country):
        AIManager.factory_cooldowns[country] -= 1
        if AIManager.factory_cooldowns[country] <= 0:
            AIManager.factory_cooldowns.erase(country)

static func process_economy(country: String) -> void:
    # Во время войны все деньги идут на войска — фабрики не строим
    if not ProvinceRegistry.war_relations.get(country, []).is_empty():
        return

    # Ждём кулдауна
    if AIManager.factory_cooldowns.has(country):
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var balance  = c_data.get("balance", 0.0)

    var factory_cost = ProvinceRegistry.get_factory_cost(country)

    # Строим только если баланс перекрывает стоимость + резерв
    var required = factory_cost * (1.0 + AIManager.RESERVE_RATIO)
    if balance < required:
        return

    # Ищем подходящую провинцию
    var candidates = get_safe_buildable_provinces(country)
    if candidates.is_empty():
        return

    # Тратим на фабрики намного бОльшую часть баланса за раз — строим
    # столько фабрик, на сколько хватает FACTORY_BUDGET_FRACTION от баланса.
    # Очередь в одной провинции вмещает до 5 фабрик, поэтому распределяем
    # постройки round-robin по провинциям.
    var budget = balance * AIManager.FACTORY_BUDGET_FRACTION
    var affordable = max(1, int(budget / factory_cost))

    var queue_room: Dictionary = {}
    for p_id in candidates:
        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        queue_room[p_id] = AIManager.MAX_QUEUE_PER_PROVINCE - p_data.get("factory_queue", []).size()

    candidates.shuffle()

    var built = 0
    var idx = 0
    var stall = 0
    while built < affordable and stall < candidates.size():
        var target_p = candidates[idx % candidates.size()]
        idx += 1

        if queue_room.get(target_p, 0) <= 0:
            stall += 1
            continue

        if c_data.get("balance", 0.0) < required:
            break

        if ProvinceRegistry.start_factory_construction(target_p, country):
            queue_room[target_p] -= 1
            built += 1
            stall = 0
        else:
            # Провинция почему-то не приняла стройку — больше не пытаемся её использовать
            queue_room[target_p] = 0
            stall += 1

    if built > 0:
        AIManager.factory_cooldowns[country] = AIManager.FACTORY_COOLDOWN_DAYS

# Провинции без активных боёв, без оккупации, с очередью < 5
static func get_safe_buildable_provinces(country: String) -> Array:
    var result = []
    for p_id in AIManager.get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue
        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        if p_data.get("factory_queue", []).size() < 5:
            result.append(p_id)
    return result
