# =============================================================================
# AIMilitary.gd
# ИИ: найм войск и движение армий (бывший раздел 4 AIManager.gd).
#
# Класс не хранит состояния — читает/пишет его через синглтон AIManager.
# =============================================================================
class_name AIMilitary
extends RefCounted

static func tick_recruitment_cooldown(country: String) -> void:
    if AIManager.recruitment_cooldowns.has(country):
        AIManager.recruitment_cooldowns[country] -= 1
        if AIManager.recruitment_cooldowns[country] <= 0:
            AIManager.recruitment_cooldowns.erase(country)

static func process_recruitment(country: String) -> void:
    # 1. Проверка кулдауна
    if AIManager.recruitment_cooldowns.has(country):
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var ideology = c_data.get("ideology", "liberalism")
    var mil_mult = DiplomacyManager.IDEOLOGIES[ideology]["mil"]
    var balance  = c_data.get("balance", 0.0)

    # 2. Расчёт лимита армии (снимается во время войны)
    var total_soldiers = AIManager.get_country_total_soldiers(country)
    var is_at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()
    var army_limit = 1e9 if is_at_war else get_army_limit(country)

    if total_soldiers >= army_limit:
        return

    # 3. Поиск лучшей провинции для найма
    var best_p_id = get_best_recruitment_province(country)
    if best_p_id == -1:
        return

    var p_data = ProvinceRegistry.province_data[best_p_id]
    var pop    = p_data.get("population", 0)
    var province_happiness = float(p_data.get("happiness", 50.0))

    # 4. Расчёт желаемого количества (1% населения, но не менее MIN_RECRUIT_SIZE)
    var desired_amount = max(AIManager.MIN_RECRUIT_SIZE, int(pop * 0.01))
    desired_amount = min(desired_amount, int(army_limit - total_soldiers))
    if desired_amount < AIManager.MIN_RECRUIT_SIZE:
        return

    var cost_per_unit = AIManager.settings.COST_PER_SOLDIER * mil_mult

    # 5. Тратим только часть текущего баланса
    var available_for_recruitment = balance * AIManager.RECRUIT_BUDGET_FRACTION
    var affordable_amount = int(available_for_recruitment / cost_per_unit)
    var recruit_amount = min(desired_amount, affordable_amount)

    if recruit_amount < AIManager.MIN_RECRUIT_SIZE:
        return

    # 7. Списываем деньги и вызываем DivisionManager
    var cost = recruit_amount * cost_per_unit
    c_data["balance"] -= cost
    var local_pos = AIManager.settings.province_centers.get(best_p_id, Vector2.ZERO)
    DivisionManager.recruit(best_p_id, local_pos, recruit_amount)

    # 8. Призыв истощает счастье провинции
    var happiness_drain = (float(recruit_amount) / 1000.0) * AIManager.HAPPINESS_DRAIN_PER_1K_RECRUITS
    p_data["happiness"] = max(0.0, province_happiness - happiness_drain)

    AIManager.recruitment_cooldowns[country] = AIManager.RECRUIT_COOLDOWN_DAYS

## Провинция с максимальным населением (без боёв, оккупации и просевшего счастья)
static func get_best_recruitment_province(country: String) -> int:
    var best_id  = -1
    var best_pop = -1
    var country_happiness = ProvinceRegistry.get_country_happiness(country)

    for p_id in AIManager.get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue

        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        var province_happiness = float(p_data.get("happiness", 50.0))

        if country_happiness - province_happiness >= 10.0:
            continue

        var pop = p_data.get("population", 0)
        if pop > best_pop:
            best_pop = pop
            best_id  = p_id

    return best_id

## Максимальный размер армии для страны (на основе ВВП и идеологии)
static func get_army_limit(country: String) -> int:
    var c_data = ProvinceRegistry.countries_data[country]
    var factories = c_data.get("factories", 0)
    var monthly_income = c_data.get("monthly_income", 0.0)
    var gdp = (factories * AIManager.settings.product_cost + monthly_income) * 12.0
    var ideology = c_data.get("ideology", "liberalism")
    var mil_mult = DiplomacyManager.IDEOLOGIES[ideology]["mil"]
    var limit_float = gdp * AIManager.ARMY_LIMIT_GDP_RATIO * mil_mult
    return int(limit_float)

## Движение армий во время войны (вызывается ежедневно)
static func process_military_movement(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    var own_provinces = get_allied_territory_provinces(country)
    var own_set: Dictionary = {}
    for p in own_provinces:
        own_set[p] = true

    var frontier_targets = get_frontier_enemy_provinces(enemies, own_set)

    # Если сухопутной границы нет, добавляем все провинции врагов для морских атак/высадок
    if frontier_targets.is_empty():
        for enemy in enemies:
            frontier_targets.append_array(AIManager.get_country_provinces(enemy))

        if frontier_targets.is_empty():
            return

    var provinces_with_armies: Dictionary = {}
    for p in own_provinces:
        provinces_with_armies[p] = true
    # ОПТИМИЗАЦИЯ: раньше здесь был двойной цикл по DivisionManager.armies.keys()
    # и по всем кружкам в каждой провинции — т.е. полный скан ВСЕХ армий на
    # карте ради поиска армий одной страны, повторяющийся для каждой страны
    # каждый день (O(countries * total_armies) синхронно в кадре смены дня).
    # Теперь используем инкрементальный индекс DivisionManager.armies_by_country — O(k).
    for p_id in DivisionManager.get_country_provinces_with_armies(country):
        provinces_with_armies[p_id] = true

    var assigned_count: Dictionary = {}

    for p_id in provinces_with_armies:
        if CombatManager.active_battles.has(p_id):
            continue

        var own_division_count = 0
        for army_check in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(army_check) and army_check.division_owner == country:
                own_division_count += 1
        if own_division_count > 4 and country != AIManager.settings.active_country:
            DivisionManager.merge_divisions(p_id)

        for army in DivisionManager.armies.get(p_id, []):
            if not is_instance_valid(army) or army.division_owner != country or army.is_moving:
                continue

            var adjacent_targets = []
            for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
                var t_id = int(adj_id)
                if frontier_targets.has(t_id):
                    adjacent_targets.append(t_id)

            var target_p_id = -1
            if not adjacent_targets.is_empty():
                target_p_id = pick_least_assigned_target(adjacent_targets, assigned_count)
            else:
                target_p_id = pick_least_assigned_target(frontier_targets, assigned_count)

            if target_p_id == -1:
                continue

            assigned_count[target_p_id] = assigned_count.get(target_p_id, 0) + 1

            var target_pos = AIManager.settings.province_centers.get(target_p_id, Vector2.ZERO)
            army.start_movement_to(target_p_id, target_pos)

## Провинции страны + провинции её контролёра (сюзерена) + провинции всех её марионеток.
static func get_allied_territory_provinces(country: String) -> Array:
    var result: Array = AIManager.get_country_provinces(country).duplicate()
    var seen: Dictionary = {}
    for p in result:
        seen[p] = true

    var c_data = ProvinceRegistry.countries_data.get(country, {})

    var controller = c_data.get("controller", "")
    if controller != "" and controller != country:
        for p in AIManager.get_country_provinces(controller):
            if not seen.has(p):
                seen[p] = true
                result.append(p)

    for puppet in c_data.get("control", []):
        if puppet == "" or puppet == country:
            continue
        for p in AIManager.get_country_provinces(puppet):
            if not seen.has(p):
                seen[p] = true
                result.append(p)

    return result

## Вражеские провинции, граничащие хотя бы с одной нашей провинцией
static func get_frontier_enemy_provinces(enemies: Array, own_set: Dictionary) -> Array:
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
static func pick_least_assigned_target(candidates: Array, assigned_count: Dictionary) -> int:
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
