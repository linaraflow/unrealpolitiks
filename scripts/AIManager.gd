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

# -----------------------------------------------------------------------------
# ОПТИМИЗАЦИЯ: ежедневные кэши
# -----------------------------------------------------------------------------
# ПРОБЛЕМА: _get_country_provinces() раньше сканировал ВЕСЬ province_data
# (сейчас ~10000 записей) на каждый вызов, а вызывается он по 3-5 раз на
# КАЖДУЮ страну КАЖДЫЙ день (экономика, рекрутинг, армия, движение войск,
# поиск соседей). Итого O(countries * provinces) вместо O(provinces).
# При 300 провинциях это было незаметно, при 10000 — фризы каждый тик.
#
# РЕШЕНИЕ: один раз в день (O(provinces)) строим индекс "страна -> её
# провинции" и множество "безопасных" провинций (без боёв/оккупации),
# дальше весь день читаем из кэша за O(1)/O(k).

## country -> Array[int] провинций страны. Пересобирается в _rebuild_daily_caches().
var country_provinces_cache: Dictionary = {}

# Переменные для разделения нагрузки обсчета населения (чангинг)
var pop_chunks: Array = []
var pop_chunk_index: int = 0
const POP_CHUNKS_COUNT = 10

## p_id(int) -> true для провинций без активных боёв и без оккупации.
## Используется для быстрого поиска "безопасной" провинции беженцами.
var safe_provinces_cache: Dictionary = {}

## Плоский список ключей safe_provinces_cache — для быстрого pick_random()
## без BFS, когда рядом безопасной провинции не нашлось.
var safe_provinces_list: Array = []

# Минимальный баланс-резерв, который ИИ НЕ тратит на фабрики (чтобы не уходить в ноль)
const RESERVE_RATIO        = 0.05   # 5% резерва сверх стоимости
const FACTORY_COOLDOWN_DAYS = 30    # раз в 30 дней строим завод
const RECRUIT_COOLDOWN_DAYS = 5     # раз в 5 дней нанимаем войска
const MIN_RECRUIT_SIZE      = 50    # минимальный размер призыва
const RECRUIT_BUDGET_FRACTION = 0.3 # тратим на армию 30% текущего баланса

# УСТАРЕЛО: лимит зависел от счастья, теперь рассчитывается от ВВП
# const AI_ARMY_CAP_MIN = 500000
# const AI_ARMY_CAP_MAX = 1000000

# На сколько падает счастье провинции за каждую 1000 набранных солдат
const HAPPINESS_DRAIN_PER_1K_RECRUITS = 0.1

# --- НОВЫЙ ЛИМИТ АРМИИ НА ОСНОВЕ ВВП ---
# Коэффициент пересчёта ВВП в лимит армии (1 солдат на ~14 000 ВВП)
const ARMY_LIMIT_GDP_RATIO = 0.0000714

# -----------------------------------------------------------------------------
# 2. ИНИЦИАЛИЗАЦИЯ И ТИКИ
# -----------------------------------------------------------------------------

func _ready() -> void:
    GameClock.on_day_passed.connect(_on_day_passed)
    GameClock.on_month_passed.connect(_on_month_passed)
    
    # Следим за захватом провинций, чтобы сразу обновлять кэш, а не пересчитывать его с нуля
    ProvinceRegistry.province_captured.connect(_on_province_captured)

    # Строим стартовый кэш провинций для ИИ
    _build_initial_country_cache()

    # Разбиваем массив провинций на 10 частей для оптимизации населения
    for i in range(POP_CHUNKS_COUNT):
        pop_chunks.append([])
    
    var idx = 0
    for p_id_str in ProvinceRegistry.province_data:
        pop_chunks[idx % POP_CHUNKS_COUNT].append(p_id_str)
        idx += 1

    # Считаем доход при старте
    for country in ProvinceRegistry.countries_data:
        _update_monthly_income(country)

func _process(delta: float) -> void:
    if GameClock.paused:
        return
    _tick_income(delta)

# ── Ежедневный тик (Максимально разгруженный) ──────────────────────────────────
func _on_day_passed(_date: Dictionary) -> void:
    # Принудительно приводим день к int
    var current_day: int = int(_date.get("day", 1))

    for country in ProvinceRegistry.countries_data:
        if country == settings.active_country:
            continue
            
        var c_data = ProvinceRegistry.countries_data[country]
        
        # 0. Начисляем дневной доход ИИ
        var monthly = c_data.get("monthly_income", 100000.0)
        c_data["balance"] = c_data.get("balance", 0.0) + (monthly / 30.0)

        # Принудительно приводим индекс страны к int, даже если он прилетел как float
        var country_index: int = int(ProvinceRegistry.country_index.get(country, 0))
        
        # 1. Быстрые кулдауны и торговля
        _tick_recruitment_cooldown(country)
        _tick_factory_cooldown(country)
        _process_trade(country)

        # 2. Экономика — раз в 5 дней
        if (current_day + country_index) % 5 == 0:
            _process_economy(country)              

        # 3. Рекрутинг — раз в 3 дня
        if (current_day + country_index) % 3 == 0:
            _process_recruitment(country)          

        # 4. ДВИЖЕНИЕ ВОЙСК — раз в 4 дня
        if (current_day + country_index) % 4 == 0:
            _process_military_movement(country)    

    # 5. Обсчет населения
    _process_population()

# ── Ежемесячный тик ───────────────────────────────────────────────────────────
func _on_month_passed(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data:
        _update_monthly_income(country)

    for country in ProvinceRegistry.countries_data:
        if country == settings.active_country:
            continue
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
        var p_data = ProvinceRegistry.province_data.get(p_id, {})
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

    # 2. Расчёт лимита армии (снимается во время войны)
    var total_soldiers = _get_country_total_soldiers(country)
    var is_at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()
    var army_limit = 1e9 if is_at_war else _get_army_limit(country)   # огромное число во время войны

    if total_soldiers >= army_limit:
        return

    # 3. Поиск лучшей провинции для найма
    var best_p_id = _get_best_recruitment_province(country)
    if best_p_id == -1:
        return

    var p_data = ProvinceRegistry.province_data[best_p_id]
    var pop    = p_data.get("population", 0)
    var province_happiness = float(p_data.get("happiness", 50.0))

    # 4. Расчёт желаемого количества (1% населения, но не менее MIN_RECRUIT_SIZE),
    #    урезаем так, чтобы не пробить потолок армии страны
    var desired_amount = max(MIN_RECRUIT_SIZE, int(pop * 0.01))
    desired_amount = min(desired_amount, int(army_limit - total_soldiers))
    if desired_amount < MIN_RECRUIT_SIZE:
        return

    var cost_per_unit = settings.COST_PER_SOLDIER * mil_mult

    # 5. Тратим только 30% текущего баланса
    var available_for_recruitment = balance * RECRUIT_BUDGET_FRACTION
    var affordable_amount = int(available_for_recruitment / cost_per_unit)
    var recruit_amount = min(desired_amount, affordable_amount)

    # 6. Если получается меньше MIN_RECRUIT_SIZE — пропускаем найм
    if recruit_amount < MIN_RECRUIT_SIZE:
        return

    # 7. Списываем деньги и вызываем DivisionManager
    var cost = recruit_amount * cost_per_unit
    c_data["balance"] -= cost
    var local_pos = settings.province_centers.get(best_p_id, Vector2.ZERO)
    DivisionManager.recruit(best_p_id, local_pos, recruit_amount)

    # 8. Призыв истощает счастье провинции
    var happiness_drain = (float(recruit_amount) / 1000.0) * HAPPINESS_DRAIN_PER_1K_RECRUITS
    p_data["happiness"] = max(0.0, province_happiness - happiness_drain)

    # 9. Устанавливаем кулдаун
    recruitment_cooldowns[country] = RECRUIT_COOLDOWN_DAYS

## Провинция с максимальным населением (без боёв, оккупации и сильно просевшего счастья)
func _get_best_recruitment_province(country: String) -> int:
    var best_id  = -1
    var best_pop = -1
    var country_happiness = ProvinceRegistry.get_country_happiness(country)

    for p_id in _get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue

        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        var province_happiness = float(p_data.get("happiness", 50.0))

        # Если счастье провинции отстаёт от среднего по стране на 10+ - она больше не "лучшая",
        # идём дальше перебирать остальные провинции
        if country_happiness - province_happiness >= 10.0:
            continue

        var pop = p_data.get("population", 0)
        if pop > best_pop:
            best_pop = pop
            best_id  = p_id

    return best_id

## Максимальный размер армии для страны (на основе ВВП и идеологии)
func _get_army_limit(country: String) -> int:
    var c_data = ProvinceRegistry.countries_data[country]
    var factories = c_data.get("factories", 0)
    var monthly_income = c_data.get("monthly_income", 0.0)
    var gdp = (factories * settings.product_cost + monthly_income) * 12.0
    var ideology = c_data.get("ideology", "liberalism")
    var mil_mult = DiplomacyManager.IDEOLOGIES[ideology]["mil"]
    var limit_float = gdp * ARMY_LIMIT_GDP_RATIO * mil_mult
    return int(limit_float)

## Движение армий во время войны (теперь вызывается ежедневно)
## Атакуем только пограничные провинции врага (соседствующие с нашей территорией)
## и равномерно распределяем удары по всей линии фронта, чтобы наступление
## продвигалось не в одну точку, а по всему фронту сразу.
func _process_military_movement(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    # "Своя" территория для военных целей = собственные провинции + провинции
    # контролёра (сюзерена) + провинции марионеток. Благодаря этому армии могут
    # стоять и перемещаться в т.ч. с территории контролирующей/подконтрольной страны.
    var own_provinces = _get_allied_territory_provinces(country)
    var own_set: Dictionary = {}
    for p in own_provinces:
        own_set[p] = true

    # Линия фронта: вражеские провинции, граничащие с нашей территорией
    # (включая территорию контролёра/марионеток)
    var frontier_targets = _get_frontier_enemy_provinces(enemies, own_set)

    # Резервный вариант (старое поведение) — если фронта нет вообще
    # (например, армия оказалась в анклаве без прямых соседей-врагов)
    var fallback_targets = []
    if frontier_targets.is_empty():
        for e in enemies:
            fallback_targets.append_array(_get_country_provinces(e))
        if fallback_targets.is_empty():
            return

    # Счётчик уже назначенных в этом тике целей — для равномерного распределения удара
    var assigned_count: Dictionary = {}

    for p_id in own_provinces:
        if CombatManager.active_battles.has(p_id):
            continue

        # Если в провинции скопилось слишком много дивизий страны — объединяем их
        # в одну, чтобы не таскать по фронту толпу мелких армий
        var own_division_count = 0
        for army_check in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(army_check) and army_check.division_owner == country:
                own_division_count += 1
        if own_division_count > 4:
            DivisionManager.merge_divisions(p_id)

        # Двигаем именно армии страны country — они могут физически находиться
        # на территории своего контролёра или марионетки, а не только "дома"
        for army in DivisionManager.armies.get(p_id, []):
            if not is_instance_valid(army) or army.division_owner != country or army.is_moving:
                continue

            var target_p_id = -1

            if not frontier_targets.is_empty():
                # Приграничные вражеские провинции, соседствующие именно с этой армией
                var adjacent_targets = []
                for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
                    var t_id = int(adj_id)
                    if frontier_targets.has(t_id):
                        adjacent_targets.append(t_id)

                if not adjacent_targets.is_empty():
                    target_p_id = _pick_least_assigned_target(adjacent_targets, assigned_count)
                else:
                    # Армия в тылу — направляем её на самый "слабоатакуемый" участок фронта,
                    # чтобы наступление подтягивалось равномерно по всей линии
                    target_p_id = _pick_least_assigned_target(frontier_targets, assigned_count)
            else:
                target_p_id = fallback_targets.pick_random()

            if target_p_id == -1:
                continue

            assigned_count[target_p_id] = assigned_count.get(target_p_id, 0) + 1

            var target_pos = settings.province_centers.get(target_p_id, Vector2.ZERO)
            army.start_movement_to(target_p_id, target_pos)

## Провинции страны + провинции её контролёра (сюзерена) + провинции всех её
## марионеток. Используется для военных передвижений: армии могут находиться
## и перемещаться по территории обеих сторон вассальных отношений.
func _get_allied_territory_provinces(country: String) -> Array:
    var result: Array = _get_country_provinces(country).duplicate()
    var seen: Dictionary = {}
    for p in result:
        seen[p] = true

    var c_data = ProvinceRegistry.countries_data.get(country, {})

    var controller = c_data.get("controller", "")
    if controller != "" and controller != country:
        for p in _get_country_provinces(controller):
            if not seen.has(p):
                seen[p] = true
                result.append(p)

    for puppet in c_data.get("control", []):
        if puppet == "" or puppet == country:
            continue
        for p in _get_country_provinces(puppet):
            if not seen.has(p):
                seen[p] = true
                result.append(p)

    return result

## Вражеские провинции, граничащие хотя бы с одной нашей провинцией
func _get_frontier_enemy_provinces(enemies: Array, own_set: Dictionary) -> Array:
    # enemies.has(owner) внутри цикла по всем соседям всех своих провинций
    # был O(n) поиском по массиву — при многосторонних войнах заметно.
    # Множество на Dictionary даёт O(1) проверку.
    var enemy_set: Dictionary = {}
    for e in enemies:
        enemy_set[e] = true

    var result = []
    var seen: Dictionary = {}
    for p_id in own_set:
        for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
            var t_id = int(adj_id)
            if seen.has(t_id):
                continue
            var owner = ProvinceRegistry.province_data.get(t_id, {}).get("owner", "")
            if owner != "" and owner != ProvinceRegistry.SEA_OWNER and enemy_set.has(owner):
                seen[t_id] = true
                result.append(t_id)
    return result

## Выбирает цель с наименьшим числом уже направленных на неё армий в этом тике
## (перемешиваем, чтобы при равенстве счёта не всегда выбирать одну и ту же провинцию)
func _pick_least_assigned_target(candidates: Array, assigned_count: Dictionary) -> int:
    var shuffled = candidates.duplicate()
    shuffled.shuffle()

    var best_id    = -1
    var best_count = INF
    for t_id in shuffled:
        var c = assigned_count.get(t_id, 0)
        if c < best_count:
            best_count = c
            best_id    = t_id
    return best_id

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

    for attacker in sanctioned_by:
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
# 6. НАСЕЛЕНИЕ — рост, потери, беженцы (Оптимизация чанками)
# -----------------------------------------------------------------------------

func _process_population() -> void:
    var chunk = pop_chunks[pop_chunk_index]
    pop_chunk_index = (pop_chunk_index + 1) % POP_CHUNKS_COUNT
    
    var migration: Dictionary = {}

    for p_id_str in chunk:
        var p_id = int(p_id_str)
        var p_data = ProvinceRegistry.province_data[p_id_str]
        var current = int(p_data.get("population", 0))
        
        if current > 0:
            if CombatManager.active_battles.has(p_id):
                # Коэффициент увеличен, так как провинция обсчитывается раз в 10 дней
                var loss = int(current * 0.05) 
                if loss > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) - loss
                    _distribute_refugees(p_id, loss, migration)
            elif ProvinceRegistry.is_occupied(p_id):
                var loss = int(current * 0.003)
                if loss > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) - loss
                    _distribute_refugees(p_id, loss, migration)
            else:
                var growth = int(current * 0.001)
                if growth > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) + growth

    # Применяем изменения населения только для выбранного чанка
    for p_id_str in migration:
        if ProvinceRegistry.province_data.has(p_id_str):
            var new_pop = int(ProvinceRegistry.province_data[p_id_str].get("population", 0)) + migration[p_id_str]
            ProvinceRegistry.province_data[p_id_str]["population"] = max(0, new_pop)

func _distribute_refugees(from_p_id: int, amount: int, migration_dict: Dictionary) -> void:
    var safe_p_id = _find_nearest_safe_province(from_p_id)
    if safe_p_id != -1:
        var safe_key = safe_p_id
        migration_dict[safe_key] = migration_dict.get(safe_key, 0) + amount

func _is_province_safe(p_id: int) -> bool:
    return not CombatManager.active_battles.has(p_id) and not ProvinceRegistry.is_occupied(p_id)

const MAX_REFUGEE_SEARCH_HOPS = 3

func _find_nearest_safe_province(start_p_id: int) -> int:
    var queue = [start_p_id]
    var visited = { start_p_id: true }
    var hops = 0
    var q_idx = 0

    while q_idx < queue.size() and hops < MAX_REFUGEE_SEARCH_HOPS:
        var level_size = queue.size() - q_idx
        for i in range(level_size):
            var current_id = queue[q_idx]
            q_idx += 1

            if current_id != start_p_id and _is_province_safe(current_id):
                return current_id

            for adj_id in ProvinceRegistry.province_adjacency.get(current_id, []):
                var next_id = int(adj_id)
                if not visited.has(next_id):
                    visited[next_id] = true
                    queue.append(next_id)
        hops += 1

    # Если рядом безопасной провинции нет, ищем её рандомом (максимум 15 попыток)
    var all_keys = ProvinceRegistry.province_data.keys()  # ← Array, а не Dictionary
    if all_keys.is_empty():
        return -1

    for i in range(15):
        var rand_key = all_keys.pick_random()             # ← теперь pick_random() работает
        var rand_id = int(rand_key)
        if _is_province_safe(rand_id):
            return rand_id

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
    var speed = GameClock.SPEEDS[GameClock.speed_index]
    var inc = (delta * speed) / seconds_per_month

    # Плавный доход только для игрока
    var active = settings.active_country
    if ProvinceRegistry.countries_data.has(active):
        var c_data = ProvinceRegistry.countries_data[active]
        var monthly = c_data.get("monthly_income", 100000.0)
        c_data["balance"] = c_data.get("balance", 0.0) + (monthly * inc)

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
        total += int(ProvinceRegistry.province_data.get(p_id, {}).get("population", 0))
    return total

## Суммарная численность войск страны (по всем её провинциям)
func _get_country_total_soldiers(country: String) -> int:
    var total := 0
    for p_id in _get_country_provinces(country):
        for circle in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(circle) and circle.division_owner == country:
                total += circle.soldiers
    return total

## O(1) — читает готовый индекс, собранный в _rebuild_daily_caches().
func _get_country_provinces(country: String) -> Array:
    return country_provinces_cache.get(country, [])


## Собирает базовое распределение провинций при старте игры
func _build_initial_country_cache() -> void:
    country_provinces_cache.clear()
    for p_id_str in ProvinceRegistry.province_data:
        var p_id = int(p_id_str)
        var owner = ProvinceRegistry.province_data[p_id_str].get("owner", "")
        if owner != "" and owner != ProvinceRegistry.SEA_OWNER:
            if not country_provinces_cache.has(owner):
                country_provinces_cache[owner] = []
            country_provinces_cache[owner].append(p_id)

## Вызывается только когда провинция РЕАЛЬНО меняет владельца (быстродействие O(1))
func _on_province_captured(p_id: int, new_owner: String) -> void:
    # Убираем провинцию у старого хозяина
    for country in country_provinces_cache:
        country_provinces_cache[country].erase(p_id)
    
    # Добавляем новому
    if new_owner != "":
        if not country_provinces_cache.has(new_owner):
            country_provinces_cache[new_owner] = []
        country_provinces_cache[new_owner].append(p_id)

func _get_random_neighbor_country(country: String) -> String:
    var neighbors = []
    for p_id in _get_country_provinces(country):
        for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
            var clean_id = int(adj_id)
            var owner    = ProvinceRegistry.province_data.get(clean_id, {}).get("owner", "")
            # ВАЖНО: проверяем countries_data.has(owner), а не просто owner != "" —
            # иначе owner == "sea" (морские провинции) может попасть сюда как
            # "страна-сосед", а её нет в countries_data → падение при обращении
            # к ProvinceRegistry.countries_data[neighbor] в _try_declare_war/_process_relations_drift.
            if owner != "" and owner != country and ProvinceRegistry.countries_data.has(owner) and not neighbors.has(owner):
                neighbors.append(owner)

    return "" if neighbors.is_empty() else neighbors.pick_random()
