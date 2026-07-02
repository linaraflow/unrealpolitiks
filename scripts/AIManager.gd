# =============================================================================
# AIManager.gd
# Управляет поведением всех стран кроме активной.
#
# СТРУКТУРА:
#   1. Константы и состояние
#   2. Инициализация и тики
#   3. ЭКОНОМИКА  — строительство фабрик
#   4. ВОЕНКА     — найм войск и движение армий (ежедневно)
#   5. ДИПЛОМАТИЯ — объявление войн, мир, санкции, дрейф отношений (ежемесячно)
#   6. НАСЕЛЕНИЕ  — рост, потери, беженцы
#   7. ТОРГОВЛЯ   — продажа накопленных товаров
#   8. Вспомогательные функции
# =============================================================================

extends Node

var settings = preload("res://new_resource.tres")

@onready var balance_label = get_node_or_null(
    "/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel"
)

# -----------------------------------------------------------------------------
# 1. СОСТОЯНИЕ И КОНСТАНТЫ
# -----------------------------------------------------------------------------

## Кулдаун строительства фабрик: country -> дней до следующего строительства
var factory_cooldowns: Dictionary = {}

## Кулдаун найма войск: country -> дней до следующего найма
var recruitment_cooldowns: Dictionary = {}

# Минимальный баланс-резерв, который ИИ НЕ тратит на фабрики (чтобы не уходить в ноль)
const RESERVE_RATIO        = 0.05   # 5% резерва сверх стоимости
const FACTORY_COOLDOWN_DAYS = 30    # раз в 30 дней строим завод
const RECRUIT_COOLDOWN_DAYS = 5     # раз в 5 дней нанимаем войска
const MIN_RECRUIT_SIZE      = 50    # минимальный размер призыва
const RECRUIT_BUDGET_FRACTION = 0.3 # тратим на армию 30% текущего баланса

# -----------------------------------------------------------------------------
# 2. ИНИЦИАЛИЗАЦИЯ И ТИКИ
# -----------------------------------------------------------------------------

func _ready() -> void:
    GameClock.on_day_passed.connect(_on_day_passed)
    GameClock.on_month_passed.connect(_on_month_passed)

    # Считаем доход при старте, не ждём первого месяца
    for country in ProvinceRegistry.countries_data.keys():
        _update_monthly_income(country)

func _process(delta: float) -> void:
    if GameClock.paused:
        return
    _tick_income(delta)

# ── Ежедневный тик ────────────────────────────────────────────────────────────
func _on_day_passed(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data.keys():
        # Пропускаем игрока
        if country == settings.active_country:
            continue

        _tick_recruitment_cooldown(country)
        _tick_factory_cooldown(country)

        _process_trade(country)
        _process_economy(country)              # сначала строим фабрики
        _process_recruitment(country)          # потом нанимаем (30% бюджета)
        _process_military_movement(country)    # теперь – каждый день планируем наступление

    _process_population()

# ── Ежемесячный тик ───────────────────────────────────────────────────────────
func _on_month_passed(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data.keys():
        _update_monthly_income(country)

    for country in ProvinceRegistry.countries_data.keys():
        if country == settings.active_country:
            continue
        # Дипломатия и дрейф отношений – только раз в месяц
        _process_diplomacy(country)
        _process_relations_drift(country)

# -----------------------------------------------------------------------------
# 3. ЭКОНОМИКА — строительство фабрик
# -----------------------------------------------------------------------------

func _tick_factory_cooldown(country: String) -> void:
    if factory_cooldowns.has(country):
        factory_cooldowns[country] -= 1
        if factory_cooldowns[country] <= 0:
            factory_cooldowns.erase(country)

func _process_economy(country: String) -> void:
    # Ждём кулдауна
    if factory_cooldowns.has(country):
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var ideology = c_data.get("ideology", "liberalism")
    var eco_mult = DiplomacyManager.IDEOLOGIES[ideology]["eco"]
    var balance  = c_data.get("balance", 0.0)

    var factory_cost = settings.factory_cost * eco_mult

    # Строим только если баланс перекрывает стоимость + резерв
    var required = factory_cost * (1.0 + RESERVE_RATIO)
    if balance < required:
        return

    # Ищем подходящую провинцию
    var candidates = _get_safe_buildable_provinces(country)
    if candidates.is_empty():
        return

    var target_p = candidates.pick_random()
    if ProvinceRegistry.start_factory_construction(target_p, country):
        factory_cooldowns[country] = FACTORY_COOLDOWN_DAYS

# Провинции без активных боёв, без оккупации, с очередью < 5
func _get_safe_buildable_provinces(country: String) -> Array:
    var result = []
    for p_id in _get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue
        var p_data = ProvinceRegistry.province_data.get(str(p_id), {})
        if p_data.get("factory_queue", []).size() < 5:
            result.append(p_id)
    return result

# -----------------------------------------------------------------------------
# 4. ВОЕНКА — найм войск и движение армий
# -----------------------------------------------------------------------------

func _tick_recruitment_cooldown(country: String) -> void:
    if recruitment_cooldowns.has(country):
        recruitment_cooldowns[country] -= 1
        if recruitment_cooldowns[country] <= 0:
            recruitment_cooldowns.erase(country)

func _process_recruitment(country: String) -> void:
    # 1. Проверка кулдауна
    if recruitment_cooldowns.has(country):
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var ideology = c_data.get("ideology", "liberalism")
    var mil_mult = DiplomacyManager.IDEOLOGIES[ideology]["mil"]
    var balance  = c_data.get("balance", 0.0)

    # 2. Поиск лучшей провинции для найма
    var best_p_id = _get_best_recruitment_province(country)
    if best_p_id == -1:
        return

    var p_data = ProvinceRegistry.province_data[str(best_p_id)]
    var pop    = p_data.get("population", 0)

    # 3. Расчёт желаемого количества (1% населения, но не менее MIN_RECRUIT_SIZE)
    var desired_amount = max(MIN_RECRUIT_SIZE, int(pop * 0.01))
    var cost_per_unit  = settings.COST_PER_SOLDIER * mil_mult

    # 4. Тратим только 30% текущего баланса
    var available_for_recruitment = balance * RECRUIT_BUDGET_FRACTION
    var affordable_amount = int(available_for_recruitment / cost_per_unit)
    var recruit_amount = min(desired_amount, affordable_amount)

    # 5. Если получается меньше MIN_RECRUIT_SIZE — пропускаем найм
    if recruit_amount < MIN_RECRUIT_SIZE:
        return

    # 6. Списываем деньги и вызываем DivisionManager
    var cost = recruit_amount * cost_per_unit
    c_data["balance"] -= cost
    var local_pos = settings.province_centers.get(best_p_id, Vector2.ZERO)
    DivisionManager.recruit(best_p_id, local_pos, recruit_amount)

    # 7. Устанавливаем кулдаун
    recruitment_cooldowns[country] = RECRUIT_COOLDOWN_DAYS

## Провинция с максимальным населением (без боёв и оккупации)
func _get_best_recruitment_province(country: String) -> int:
    var best_id  = -1
    var best_pop = -1

    for p_id in _get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue
        var pop = ProvinceRegistry.province_data.get(str(p_id), {}).get("population", 0)
        if pop > best_pop:
            best_pop = pop
            best_id  = p_id

    return best_id

## Движение армий во время войны (теперь вызывается ежедневно)
func _process_military_movement(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    var enemy_provinces = []
    for e in enemies:
        enemy_provinces.append_array(_get_country_provinces(e))
    if enemy_provinces.is_empty():
        return

    for p_id in _get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        for army in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(army) and army.division_owner == country and not army.is_moving:
                var target_p_id = enemy_provinces.pick_random()
                var target_pos  = settings.province_centers.get(target_p_id, Vector2.ZERO)
                army.start_movement_to(target_p_id, target_pos)

# -----------------------------------------------------------------------------
# 5. ДИПЛОМАТИЯ
# -----------------------------------------------------------------------------

func _process_diplomacy(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var enemies = ProvinceRegistry.war_relations.get(country, [])

    _process_sanctions(country)

    if not enemies.is_empty():
        _try_make_peace(country, c_data, enemies)
        return  # воюем — новые войны не объявляем

    _try_declare_war(country, c_data)

func _try_make_peace(country: String, c_data: Dictionary, enemies: Array) -> void:
    var ideology    = c_data.get("ideology", "liberalism")
    var peace_mult  = DiplomacyManager.IDEOLOGIES[ideology]["peace"]

    if randf() < (0.10 * peace_mult):
        var target_enemy = enemies.pick_random()
        if target_enemy != settings.active_country:
            ProvinceRegistry.annex_all_occupied_by(country)
            ProvinceRegistry.annex_all_occupied_by(target_enemy)
            ProvinceRegistry.end_war(country, target_enemy)

func _try_declare_war(country: String, c_data: Dictionary) -> void:
    var ideology          = c_data.get("ideology", "liberalism")
    var war_mult          = DiplomacyManager.IDEOLOGIES[ideology]["war"]
    var neighbor          = _get_random_neighbor_country(country)

    if neighbor == "" or neighbor == country:
        return

    var relations         = DiplomacyManager.get_relation(country, neighbor)
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    # Расчёт базового шанса в зависимости от отношений
    var base_chance = 0.0
    if relations >= 0:
        base_chance = 0.0
    elif relations > -30:
        base_chance = 0.01
    elif relations > -70:
        base_chance = 0.05
    else:
        base_chance = 0.15

    var declare_chance = base_chance * war_mult

    if ideology == neighbor_ideology and relations >= -20.0:
        declare_chance *= 0.5

    if randf() < declare_chance:
        ProvinceRegistry.declare_war(country, neighbor)

## Ответные санкции
func _process_sanctions(country: String) -> void:
    var c_data       = ProvinceRegistry.countries_data[country]
    var sanctioned_by = c_data.get("sanctioned_by", {})
    if sanctioned_by.is_empty():
        return

    for attacker in sanctioned_by.keys():
        var attacker_data = ProvinceRegistry.countries_data.get(attacker, {})
        if not attacker_data.get("sanctioned_by", {}).has(country):
            var sanction_cost = 150000.0
            if c_data.get("balance", 0.0) >= sanction_cost * (1.0 + RESERVE_RATIO):
                DiplomacyManager.toggle_sanctions(country, attacker, sanction_cost)

## Ежемесячный дрейф отношений
func _process_relations_drift(country: String) -> void:
    var neighbor = _get_random_neighbor_country(country)
    if neighbor == "" or neighbor == country:
        return

    var ideology          = ProvinceRegistry.countries_data[country].get("ideology", "liberalism")
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    var drift: float = randf_range(-2.0, 3.0) if ideology == neighbor_ideology else randf_range(-5.0, 2.0)

    DiplomacyManager.change_relation(country, neighbor, drift)

# -----------------------------------------------------------------------------
# 6. НАСЕЛЕНИЕ — рост, потери, беженцы
# -----------------------------------------------------------------------------

func _process_population() -> void:
    var migration: Dictionary = {}

    for p_id_str in ProvinceRegistry.province_data.keys():
        var p_id      = int(p_id_str)
        var p_data    = ProvinceRegistry.province_data[p_id_str]
        var current   = int(p_data.get("population", 0))
        if current <= 0:
            continue

        if CombatManager.active_battles.has(p_id):
            var loss = int(current * 0.005)
            if loss > 0:
                migration[p_id] = migration.get(p_id, 0) - loss
                _distribute_refugees(p_id, loss, migration)

        elif ProvinceRegistry.is_occupied(p_id):
            var loss = int(current * 0.0003)
            if loss > 0:
                migration[p_id] = migration.get(p_id, 0) - loss
                _distribute_refugees(p_id, loss, migration)

        else:
            var growth = int(current * 0.0001)
            if growth > 0:
                migration[p_id] = migration.get(p_id, 0) + growth

    for p_id in migration:
        var key = str(p_id)
        if ProvinceRegistry.province_data.has(key):
            var new_pop = int(ProvinceRegistry.province_data[key].get("population", 0)) \
                        + migration[p_id]
            ProvinceRegistry.province_data[key]["population"] = max(0, new_pop)

    ProvinceRegistry._recalculate_all_populations()

func _distribute_refugees(from_p_id: int, amount: int, migration_dict: Dictionary) -> void:
    var safe_p_id = _find_nearest_safe_province(from_p_id)
    if safe_p_id != -1:
        migration_dict[safe_p_id] = migration_dict.get(safe_p_id, 0) + amount

func _find_nearest_safe_province(start_p_id: int) -> int:
    var queue   = [start_p_id]
    var visited = { start_p_id: true }

    while not queue.is_empty():
        var current_id = queue.pop_front()
        if current_id != start_p_id:
            if not CombatManager.active_battles.has(current_id) \
            and not ProvinceRegistry.is_occupied(current_id):
                return current_id

        for adj_id in ProvinceRegistry.province_adjacency.get(str(current_id), []):
            var next_id = int(adj_id)
            if not visited.has(next_id):
                visited[next_id] = true
                queue.append(next_id)

    return -1

# -----------------------------------------------------------------------------
# 7. ТОРГОВЛЯ — продажа накопленных товаров
# -----------------------------------------------------------------------------

func _process_trade(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var stock   = c_data.get("products", 0.0)
    if stock <= 0.0:
        return

    var sanctions    = c_data.get("sanctions", 0.0)
    var actual_price = settings.product_cost * (1.0 - (sanctions / 100.0))

    c_data["products"] = 0.0
    c_data["balance"]  = c_data.get("balance", 0.0) + stock * actual_price

# -----------------------------------------------------------------------------
# 8. ДОХОД — начисление в реальном времени
# -----------------------------------------------------------------------------

func _tick_income(delta: float) -> void:
    var seconds_per_month = 30.0 * GameClock.SECONDS_PER_DAY
    var speed             = GameClock.SPEEDS[GameClock.speed_index]

    for country in ProvinceRegistry.countries_data.keys():
        var c_data  = ProvinceRegistry.countries_data[country]
        var monthly = c_data.get("monthly_income", 100000.0)
        c_data["balance"] = c_data.get("balance", 0.0) \
                          + (monthly / seconds_per_month) * delta * speed

    if is_instance_valid(balance_label) and settings.can_draw:
        balance_label.balance_update()

func _update_monthly_income(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    c_data["monthly_income"] = _calculate_monthly_income(country)

func _calculate_monthly_income(country: String) -> float:
    var total_pop = _get_country_population(country)
    var ideology  = ProvinceRegistry.countries_data[country].get("ideology", "liberalism")
    var tax_mult  = DiplomacyManager.IDEOLOGIES[ideology]["tax"]
    return float(total_pop) * 1.0 * tax_mult

# -----------------------------------------------------------------------------
# 8. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# -----------------------------------------------------------------------------

func _get_country_population(country: String) -> int:
    var total = 0
    for p_id in _get_country_provinces(country):
        total += int(ProvinceRegistry.province_data.get(str(p_id), {}).get("population", 0))
    return total

func _get_country_provinces(country: String) -> Array:
    var result = []
    for p_id in ProvinceRegistry.province_data.keys():
        if ProvinceRegistry.province_data[p_id].get("owner", "") == country:
            result.append(int(p_id))
    return result

func _get_random_neighbor_country(country: String) -> String:
    var neighbors = []
    for p_id in _get_country_provinces(country):
        for adj_id in ProvinceRegistry.province_adjacency.get(str(p_id), []):
            var clean_id = str(int(adj_id))
            var owner    = ProvinceRegistry.province_data.get(clean_id, {}).get("owner", "")
            if owner != "" and owner != country and not neighbors.has(owner):
                neighbors.append(owner)

    return "" if neighbors.is_empty() else neighbors.pick_random()
