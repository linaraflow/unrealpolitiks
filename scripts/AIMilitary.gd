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

static func tick_fortification_cooldown(country: String) -> void:
    if AIManager.fortification_cooldowns.has(country):
        AIManager.fortification_cooldowns[country] -= 1
        if AIManager.fortification_cooldowns[country] <= 0:
            AIManager.fortification_cooldowns.erase(country)

## ИИ строит укрепления в первую очередь на границе (с врагом — приоритет,
## иначе с любой другой страной), чтобы усилить оборону самых уязвимых
## провинций. Тратит с оглядкой на резерв баланса, не мешает найму/фабрикам.
static func process_fortifications(country: String) -> void:
    if AIManager.fortification_cooldowns.has(country):
        return

    var c_data  = ProvinceRegistry.countries_data[country]
    var balance = c_data.get("balance", 0.0)

    var cost = ProvinceRegistry.get_fortification_cost(country)
    var required = cost * (1.0 + AIManager.RESERVE_RATIO)
    if balance < required:
        return

    var target_p = get_best_fortification_province(country)
    if target_p == -1:
        return

    # Шанс постройки 25%, если страна не воюет. Во время войны укрепления
    # нужны немедленно, поэтому шанс отключается — строим всегда.
    var is_at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()
    if not is_at_war and randf() >= 0.05:
        return

    if ProvinceRegistry.start_fortification_construction(target_p, country):
        AIManager.fortification_cooldowns[country] = AIManager.FORTIFICATION_COOLDOWN_DAYS

## Выбирает лучшую провинцию под укрепление: свою, без активного боя и без
## оккупации, без уже построенного/строящегося укрепления — из них берём
## провинцию с наибольшим числом фабрик (ключевой промышленный центр, который
## важнее всего защитить). При равенстве фабрик — большее население.
static func get_best_fortification_province(country: String) -> int:
    var best_id       = -1
    var best_factories = -1
    var best_pop       = -1

    for p_id in AIManager.get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue

        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        if p_data.get("fortification", false):
            continue
        if ProvinceRegistry.active_fortification_constructions.has(p_id):
            continue

        var factories = int(p_data.get("factories", 0))
        var pop = p_data.get("population", 0)

        if factories > best_factories or (factories == best_factories and pop > best_pop):
            best_factories = factories
            best_pop = pop
            best_id = p_id

    return best_id

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
##
## ПЕРЕПИСАНО ПОЛНОСТЬЮ: раньше (два предыдущих захода на оптимизацию) мы
## считали ФРОНТ ВСЕЙ СТРАНЫ (get_allied_territory_provinces +
## get_frontier_enemy_provinces / волна от фронта вглубь территории) — то
## есть O(вся_территория_страны) операций каждый день, даже если реальных
## армий у страны было 5-6 штук из 2265 провинций. Кэш "по количеству своих
## провинций" не спасал, потому что в активной войне территория меняется
## буквально каждый день (см. профилирование — Россия теряла/приобретала
## по 4-6 провинций ежедневно), так что кэш почти всегда промахивался.
##
## ПРАВИЛЬНЫЙ ПОДХОД: армий мало — значит вместо "просканировать всю страну,
## чтобы понять, где фронт" делаем BFS НАРУЖУ от каждой конкретной провинции
## С АРМИЕЙ, пока не наткнёмся на ближайшую вражескую провинцию, и сразу же
## останавливаемся. Стоимость — O(расстояние_до_фронта), не O(размер_страны).
## Работает одинаково для суши и "нет прямой границы" (высадка через море) —
## просто BFS идёт на несколько шагов дальше, никакого отдельного фолбэка
## на "все провинции врагов" больше не нужно.
static func process_military_movement(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    # ОПТИМИЗАЦИЯ: если враг формально ещё "в войне" (мир не заключён), но
    # у него уже 0 провинций (полностью оккупирован/разгромлен), то ниже
    # find_nearest_enemy_province() НИКОГДА не найдёт вражескую провинцию —
    # BFS каждый раз доходит до MAX_BFS_NODES и завершается впустую. Раньше
    # это повторялось КАЖДЫЙ ДЕНЬ для каждой простаивающей армии такой
    # страны бесконечно (до заключения мира), что и давало устойчивый лаг
    # даже "без войн" по ощущениям игрока. Отфильтровываем таких врагов
    # заранее — O(k) проверка по готовому кэшу вместо BFS по всей карте.
    var enemy_set: Dictionary = {}
    for e in enemies:
        if not AIManager.get_country_provinces(e).is_empty():
            enemy_set[e] = true

    if enemy_set.is_empty():
        return  # все враги уже без территории — двигать войска некуда

    var provinces_with_armies: Dictionary = {}
    for p_id in DivisionManager.get_country_provinces_with_armies(country):
        provinces_with_armies[p_id] = true

    if provinces_with_armies.is_empty():
        return

    for p_id in provinces_with_armies:
        if CombatManager.active_battles.has(p_id):
            continue

        # ОПТИМИЗАЦИЯ: если для этой провинции вчера уже выяснили, что враг
        # недостижим (BFS дошёл до MAX_BFS_NODES и вернул -1), не гоняем
        # полный BFS заново каждый день — ждём STUCK_ARMY_RETRY_DAYS дней.
        # См. AIManager.stuck_army_cooldowns.
        if AIManager.stuck_army_cooldowns.has(p_id):
            AIManager.stuck_army_cooldowns[p_id] -= 1
            if AIManager.stuck_army_cooldowns[p_id] > 0:
                continue
            AIManager.stuck_army_cooldowns.erase(p_id)

        # ОПТИМИЗАЦИЯ: раньше по армиям в этой провинции проходили ДВАЖДЫ
        # (один раз — посчитать own_division_count для слияния, второй раз —
        # для движения). Теперь считаем и собираем "подвижные" армии за один
        # проход; повторный проход нужен только ПОСЛЕ реального слияния,
        # т.к. merge_divisions() меняет список армий в провинции.
        var own_division_count = 0
        var movable_armies: Array = []
        for army_check in DivisionManager.armies.get(p_id, []):
            if not is_instance_valid(army_check) or army_check.division_owner != country:
                continue
            own_division_count += 1
            if not army_check.is_moving:
                movable_armies.append(army_check)

        if own_division_count > 4 and country != AIManager.settings.active_country:
            DivisionManager.merge_divisions(p_id)
            movable_armies.clear()
            for army_check in DivisionManager.armies.get(p_id, []):
                if is_instance_valid(army_check) and army_check.division_owner == country and not army_check.is_moving:
                    movable_armies.append(army_check)

        if movable_armies.is_empty():
            continue

        # ВАЖНО: передаём именно КОНЕЧНУЮ вражескую провинцию, а не первого
        # соседа по маршруту. start_movement_to() сам строит через PathCache
        # ПОЛНЫЙ путь и плавно ведёт армию по всем провинциям без остановок —
        # если отдавать только "следующий сосед", армия останавливается на
        # каждом шаге и ждёт СЛЕДУЮЩЕГО ДНЕВНОГО ТИКА, чтобы получить
        # следующего соседа — отсюда "рывки" по одной провинции в день,
        # особенно заметные на море, где останавливаться незачем вовсе.
        var target_p_id: int = find_nearest_enemy_province(country, p_id, enemy_set)
        if target_p_id == -1:
            # Враг не найден за MAX_BFS_NODES — не долбим BFS каждый день,
            # ставим кулдаун и вернёмся к этой провинции позже.
            AIManager.stuck_army_cooldowns[p_id] = AIManager.STUCK_ARMY_RETRY_DAYS
            continue  # нет достижимого врага из этой провинции

        var target_pos = AIManager.settings.province_centers.get(target_p_id, Vector2.ZERO)
        for army in movable_armies:
            army.start_movement_to(target_p_id, target_pos)

## Ограничение на размер BFS в find_nearest_enemy_province(): если враг не
## найден в пределах этого числа посещённых провинций — считаем, что он
## недостижим/слишком далеко, и НЕ продолжаем поиск. Без этого лимита BFS
## в наземно-непроходимых/морских войнах (когда ближайший враг далеко или
## недостижим вовсе) обходил бы ОГРОМНЫЙ кусок связанной морской сети карты.
##
## Раньше (когда AI пересчитывал маршрут КАЖДЫЙ ДЕНЬ для каждой стоящей
## армии, отдавая только следующего соседа) лимит держали низким (250),
## чтобы не тратить кадр на ежедневный пересчёт. Теперь start_movement_to()
## получает сразу конечную вражескую провинцию и армия идёт до неё одним
## непрерывным маршем (см. process_military_movement) — значит этот поиск
## выполняется один раз на весь марш-бросок, а не каждый день, и лимит
## можно держать значительно выше без риска деградации производительности.
const MAX_BFS_NODES := 4000

## BFS НАРУЖУ от start_p, пока не найдём province, принадлежащую врагу из
## enemy_set — возвращает САМУ вражескую провинцию (конечную цель марша),
## а не промежуточный шаг: armee движется до неё одним непрерывным путём
## через PathCache/start_movement_to. -1, если врагов не нашли вовсе
## (например, страна отрезана от всех врагов чужой территорией без доступа)
## ИЛИ ближайший враг дальше MAX_BFS_NODES провинций (см. пояснение выше).
static func find_nearest_enemy_province(country: String, start_p: int, enemy_set: Dictionary) -> int:
    var start_owner = ProvinceRegistry.province_data.get(start_p, {}).get("owner", "")
    if enemy_set.has(start_owner):
        return -1  # уже стоим на вражеской земле — двигаться дальше некуда

    var visited: Dictionary = {start_p: true}
    var queue: Array = [start_p]
    var q_idx := 0

    while q_idx < queue.size():
        if visited.size() > MAX_BFS_NODES:
            return -1  # враг слишком далеко/недостижим — не тратим на поиск весь кадр

        var current: int = queue[q_idx]
        q_idx += 1
        for adj_id in ProvinceRegistry.province_adjacency.get(current, []):
            var n: int = int(adj_id)
            if visited.has(n):
                continue

            var n_owner = ProvinceRegistry.province_data.get(n, {}).get("owner", "")
            if enemy_set.has(n_owner):
                return n  # нашли ближайшую вражескую провинцию — это и есть цель марша

            if not _is_passable_for_movement(country, n):
                continue

            visited[n] = true
            queue.append(n)

    return -1

## Проходимость провинции для сухопутного/морского марша армии этой страны —
## те же правила, что _can_enter_territory()/Pathfinder.find_path(): свои,
## ничейные/морские, вражеские (война есть — идём напролом) и подконтрольные.
static func _is_passable_for_movement(country: String, p_id: int) -> bool:
    var owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")
    if owner == "" or owner == ProvinceRegistry.SEA_OWNER or owner == country:
        return true
    if not ProvinceRegistry.countries_data.has(owner) or not ProvinceRegistry.countries_data.has(country):
        return false
    if ProvinceRegistry.is_at_war(country, owner):
        return true
    var my_ctrl = ProvinceRegistry.countries_data[country].get("control", [])
    var their_ctrl = ProvinceRegistry.countries_data[owner].get("control", [])
    return owner in my_ctrl or country in their_ctrl
