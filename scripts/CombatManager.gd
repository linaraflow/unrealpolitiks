extends Node

# ──────────────────────────────────────────────────────────────────────────────
# CombatManager — Боевая система
#
# Как подключить:
#   Project → Project Settings → Autoload → добавить этот файл как "CombatManager"
#
# Зависимости (тоже должны быть в Autoload): ProvinceRegistry, DivisionManager, GameClock
# ──────────────────────────────────────────────────────────────────────────────

signal battle_started(province_id: int, sides: Dictionary)
signal battle_tick(province_id: int, sides: Dictionary)
signal battle_ended(province_id: int, winner: String)

## Эмитится каждый раз, когда сторона теряет солдат в бою (для StatsManager).
## country — та сторона, которая понесла потери, amount — сколько людей потеряно за этот тик.
signal casualties_inflicted(country: String, amount: int)

# ═══ ИЗМЕНЕНО ═══════════════════════════════════════════════════════════════
# Урон зависит от численности армии:
#   урон стороны за тик = (сумма солдат всех её кружков) × DAMAGE_PER_SOLDIER
# При DAMAGE_PER_SOLDIER = 1.0: 5000 войск → 5000 урона, 100000 войск → 100000 урона.
# Хочешь более долгие бои — поставь, например, 0.1 (5000 войск → 500 урона за тик).
const DAMAGE_PER_SOLDIER := 0.5
# ════════════════════════════════════════════════════════════════════════════
const TICK_INTERVAL  := 0.5       # секунды между тиками боя (реального времени)
const WAR_EXHAUSTION_PER_TICK := 0.1  # усталость, начисляемая стороне за каждый боевой тик, в котором она участвует

# Активные бои: province_id -> { "sides": { "CountryA": {...}, "CountryB": {...} }, "timer": float }
# Структура стороны: { "countries": [str], "circles": [ArmyCircle], "hp": int }
var active_battles: Dictionary = {}

func _process(delta: float) -> void:
    if GameClock.paused:
        return
    _process_all_battles(delta)

# ─── ПУБЛИЧНЫЙ API ────────────────────────────────────────────────────────────

## Вызывается когда дивизия входит в провинцию — проверяем нужен ли бой
func check_for_battle(division, province_id: int) -> void:
    var circles: Array = DivisionManager.armies.get(province_id, [])
    if circles.is_empty():
        return
        
    # Собираем уникальные страны в этой провинции
    var countries_present: Dictionary = {}   # country -> [circle, ...]
    for circle in circles:
        if not is_instance_valid(circle):
            continue
        var c = circle.division_owner
        if not countries_present.has(c):
            countries_present[c] = []
        countries_present[c].append(circle)
        
    if countries_present.size() < 2:
        _maybe_end_battle(province_id)
        return

    # ВАЖНО: убираем страны, которые физически стоят в провинции, но ни с кем
    # из присутствующих не воюют (например, недобитый гарнизон после белого мира).
    # Иначе они "зависают" в сторонах боя и ломают определение победителя.
    var all_countries = countries_present.keys()
    var belligerents: Dictionary = {}
    for country in all_countries:
        for other in all_countries:
            if other != country and ProvinceRegistry.is_at_war(country, other):
                belligerents[country] = countries_present[country]
                break
    countries_present = belligerents

    if countries_present.size() < 2:
        _maybe_end_battle(province_id)
        return
        
    # Проверяем: есть ли хоть одна пара врагов
    var country_list = countries_present.keys()
    var enemies_found := false
    for i in range(country_list.size()):
        for j in range(i + 1, country_list.size()):
            if ProvinceRegistry.is_at_war(country_list[i], country_list[j]):
                enemies_found = true
                break
        if enemies_found:
            break
        
    if not enemies_found:
        _maybe_end_battle(province_id)
        return
        
        # Если бой уже идёт — просто обновляем состав (дивизии могли подойти)
    if active_battles.has(province_id):
        _refresh_battle_sides(province_id, countries_present)
        return
        
    # Начинаем новый бой
    _start_battle(province_id, countries_present)

# ─── ВНУТРЕННЯЯ ЛОГИКА ───────────────────────────────────────────────────────

func _start_battle(province_id: int, countries_present: Dictionary) -> void:
    var sides = _build_sides(province_id, countries_present)
    if sides.size() < 2:
        return
    
    active_battles[province_id] = {
        "sides": sides,
        "timer": 0.0,   # свой таймер для каждого боя
    }
    
    var circles: Array = DivisionManager.armies.get(province_id, [])
    for circle in circles:
        circle._stop_current_movement()

    print("[Combat] Бой начался в провинции %d: %s" % [province_id, sides.keys()])
    battle_started.emit(province_id, sides)

## Перестраивает стороны боя без сброса HP (при подходе подкреплений)
func _refresh_battle_sides(province_id: int, countries_present: Dictionary) -> void:
    var battle = active_battles[province_id]
    
    # Для каждой известной страны обновляем список кружков
    for country in countries_present:
        var circles = countries_present[country]
        
        # Если страна уже в бою — ищем новеньких и добавляем их HP
        if battle["sides"].has(country):
            var side = battle["sides"][country]
            var existing_circles = side["circles"]
            
            var new_hp_to_add = 0
            for c in circles:
                # Если этого кружка раньше не было в массиве боя
                if not existing_circles.has(c) and is_instance_valid(c):
                    new_hp_to_add += c.soldiers
            
            # Честно вливаем полное здоровье подкрепления
            if new_hp_to_add > 0:
                side["hp"] += new_hp_to_add
                side["max_hp"] += new_hp_to_add
                print("[Combat] Провинция %d | Подкрепление принесло %s: +%d HP" % [province_id, country, new_hp_to_add])
            
            # Обновляем массив кружков на актуальный
            side["circles"] = circles
        else:
            # Новая страна вошла в провинцию во время боя — добавляем сторону
            var is_enemy_of_existing := false
            for existing_country in battle["sides"].keys():
                if ProvinceRegistry.is_at_war(country, existing_country):
                    is_enemy_of_existing = true
                    break
            
            if is_enemy_of_existing:
                var max_hp = _calc_side_max_hp(circles)
                battle["sides"][country] = {
                    "circles": circles,
                    "hp": max_hp,
                    "max_hp": max_hp,
                }
                print("[Combat] Подкрепление вошло в бой в провинции %d: %s" % [province_id, country])

func _build_sides(province_id: int, countries_present: Dictionary) -> Dictionary:
    # Группируем страны по воюющим коалициям (упрощённо: две стороны)
    # Первая страна — сторона А, все враги первой — сторона Б
    var sides: Dictionary = {}
    
    for country in countries_present:
        var circles = countries_present[country]
        var max_hp = _calc_side_max_hp(circles)
        sides[country] = {
            "circles": circles,
            "hp": max_hp,
            "max_hp": max_hp,
        }
    
    return sides

## Суммарное число солдат стороны.
## Используется и для HP, и для расчёта урона (урон = численность × DAMAGE_PER_SOLDIER).
func _calc_side_max_hp(circles: Array) -> int:
    var total_soldiers := 0
    for circle in circles:
        if is_instance_valid(circle):
            total_soldiers += circle.soldiers # Считаем людей, а не абстрактные HP
    return total_soldiers

func _process_all_battles(delta: float) -> void:
    var ended: Array = []
    
    for province_id in active_battles:
        var battle = active_battles[province_id]
        battle["timer"] += delta * GameClock.SPEEDS[GameClock.speed_index]
        if battle["timer"] >= TICK_INTERVAL:
            battle["timer"] = 0.0
            var finished = _process_battle_tick(province_id)
            if finished:
                ended.append(province_id)
    
    for province_id in ended:
        active_battles.erase(province_id)

func _process_battle_tick(province_id: int) -> bool:
    var battle = active_battles[province_id]
    var sides: Dictionary = battle["sides"]
    
    # Убираем стороны у которых больше нет кружков в провинции
    var to_remove: Array = []
    for country in sides.keys():
        var valid_circles := _get_valid_circles(sides[country]["circles"], province_id, country)
        sides[country]["circles"] = valid_circles
        if valid_circles.is_empty():
            to_remove.append(country)
    
    for country in to_remove:
        sides.erase(country)
    
    # ═══ ФИКС ═══ Список сторон берём ПОСЛЕ чистки (раньше использовался
    # side_keys, снятый до удаления сторон — был риск обращения к мёртвой стороне)
    var side_keys = sides.keys()
    
    # ═══ ФИКС ═══ Бой завершён, если осталась одна сторона ИЛИ оставшиеся
    # стороны больше ни с кем не воюют (A и B совместно добили общего врага C,
    # но друг с другом не воюют — раньше такой бой зависал навсегда).
    if side_keys.size() < 2 or not _has_enemies_pair(sides):
        var winner: String = side_keys[0] if side_keys.size() == 1 else ""
        print("[Combat] Бой в провинции %d завершён. Победитель: %s" % [province_id, winner])
        battle_ended.emit(province_id, winner)
        return true
    
    # ── Рассчитываем урон: ЗАВИСИТ ОТ ЧИСЛЕННОСТИ ────────────────────────────
    # Урон стороны = суммарные солдаты × DAMAGE_PER_SOLDIER × (1 - усталость/100).
    # Считаем ДО применения урона, чтобы все стороны били одновременно
    # по численности на начало тика.
    var damage_dealt: Dictionary = {}   # country -> damage
    
    for country in sides:
        var soldiers := _calc_side_max_hp(sides[country]["circles"])
        var fatigue := ProvinceRegistry.get_war_exhaustion(country)
        var dmg := int(soldiers * DAMAGE_PER_SOLDIER * (1.0 - fatigue / 100.0))
        damage_dealt[country] = max(dmg, 0)
    
    # Применяем урон (все стороны бьют одновременно)
    var to_eliminate: Array = []
    # Те, кто уже были пробиты
    var hit: Array = []
    
    for i in range(side_keys.size()):
        var attacker = side_keys[i]
        
        var enemies: Array = []
        for j in range(side_keys.size()):
            if i != j and ProvinceRegistry.is_at_war(attacker, side_keys[j]):
                enemies.append(side_keys[j])
        
        if enemies.is_empty():
            continue
        
        var dmg_per_enemy: int = damage_dealt[attacker]
        
        if not enemies[0] in hit:
            var hp_before = sides[enemies[0]]["hp"]
            sides[enemies[0]]["hp"] -= dmg_per_enemy
            # Реальные потери не могут быть больше, чем оставалось HP (иначе статистика "перевыполняется")
            var real_loss = min(dmg_per_enemy, hp_before)
            if real_loss > 0:
                casualties_inflicted.emit(enemies[0], real_loss)
                ProvinceRegistry.adjust_monthly_income_for_troops(enemies[0], -real_loss)
            print("[Combat] Провинция %d | %s (численность: %d) → %s: -%d HP (осталось %d) [усталость атакующего: %.2f%%]" % [
                province_id, attacker, _calc_side_max_hp(sides[attacker]["circles"]), enemies[0],
                dmg_per_enemy, sides[enemies[0]]["hp"], ProvinceRegistry.get_war_exhaustion(attacker)
            ])
            hit.append(enemies[0])
        
        # Атакующая сторона получает усталость от войны за участие в этом тике боя.
        ProvinceRegistry.add_war_exhaustion(attacker, WAR_EXHAUSTION_PER_TICK)
    
    # ── Синхронизируем солдат кружков с текущим HP ───────────────────────────
    for country in sides:
        var side = sides[country]
        if side["hp"] <= 0:
            to_eliminate.append(country)
            continue
        _sync_divisions_to_hp(side["circles"], side["hp"])
    
    # Уничтожаем проигравших
    for country in to_eliminate:
        _eliminate_side(province_id, country, sides[country]["circles"])
        sides.erase(country)
        print("[Combat] %s полностью разгромлен в провинции %d!" % [country, province_id])
    
    battle_tick.emit(province_id, sides)
    
    # ═══ ФИКС ═══ Та же проверка после уничтожения проигравших:
    # если оставшиеся стороны не воюют между собой — бой окончен.
    var remaining_keys = sides.keys()
    if remaining_keys.size() < 2 or not _has_enemies_pair(sides):
        var winner: String = remaining_keys[0] if remaining_keys.size() == 1 else ""
        print("[Combat] Бой в провинции %d завершён. Победитель: %s" % [province_id, winner])
        battle_ended.emit(province_id, winner)
        return true
    
    return false

## Есть ли среди оставшихся сторон боя хотя бы одна враждующая пара.
## Если нет — бой считается завершённым (совместная победа / все враги выбиты).
func _has_enemies_pair(sides: Dictionary) -> bool:
    var keys = sides.keys()
    for i in range(keys.size()):
        for j in range(i + 1, keys.size()):
            if ProvinceRegistry.is_at_war(keys[i], keys[j]):
                return true
    return false

## Синхронизирует солдат кружков с текущим HP стороны
func _sync_divisions_to_hp(circles: Array, hp: int) -> void:
    if circles.is_empty():
        return
    
    var remaining_hp_pool = hp
    
    # Проходим по кружкам и распределяем оставшихся солдат стороны
    for circle in circles:
        if not is_instance_valid(circle):
            continue
            
        if remaining_hp_pool <= 0:
            _destroy_circle(circle)
            continue
            
        # Если у кружка было, например, 15000 солдат, а в пуле осталось 5000, 
        # значит этот кружок забирает остаток.
        if circle.soldiers > remaining_hp_pool:
            circle.soldiers = remaining_hp_pool
            remaining_hp_pool = 0
        else:
            # Кружок сохраняет своих солдат, вычитаем их из пула распределения
            remaining_hp_pool -= circle.soldiers
            
        if circle.soldiers <= 0:
            _destroy_circle(circle)
            
    _sync_province_land(circles[0].province_id if not circles.is_empty() and is_instance_valid(circles[0]) else 0)

## Уничтожает все кружки проигравшей стороны
func _eliminate_side(province_id: int, country: String, circles: Array) -> void:
    for circle in circles:
        if is_instance_valid(circle):
            _destroy_circle(circle)

## Корректно удаляет кружок из всех систем
func _destroy_circle(circle: Node) -> void:
    if not is_instance_valid(circle):
        return
    
    var p_id = circle.province_id
    
    # Убираем кружок из выделения если он там был
    if SelectionManager.selected_divisions.has(circle):
        circle.deselect()
        SelectionManager.selected_divisions.erase(circle)
    
    # Удаляем из DivisionManager.armies
    if DivisionManager.armies.has(p_id):
        DivisionManager.armies[p_id].erase(circle)
        if DivisionManager.armies[p_id].is_empty():
            DivisionManager.armies.erase(p_id)
    
    circle.queue_free()
    
    # Пересчитываем land по оставшимся живым кружкам и уведомляем UI
    _sync_province_land(p_id)
    DivisionManager.reposition_armies_in_province(p_id)

## Пересчитывает province_data["army"]["land"] по реальным кружкам в DivisionManager
func _sync_province_land(p_id: int) -> void:
    var p_data = ProvinceRegistry.province_data.get(p_id, {})
    if not p_data.has("army"):
        return
    var total := 0
    for circle in DivisionManager.armies.get(p_id, []):
        if is_instance_valid(circle):
            total += circle.soldiers
    p_data["army"]["land"] = total
    ProvinceRegistry.province_army_changed.emit(p_id)

## Фильтрует только валидные кружки которые находятся в нужной провинции и принадлежат стране
func _get_valid_circles(circles: Array, province_id: int, country: String) -> Array:
    var result: Array = []
    for circle in circles:
        if is_instance_valid(circle) and circle.province_id == province_id and circle.division_owner == country:
            result.append(circle)
    return result

## Проверяет нужно ли завершить бой (если остались только союзники)
func _maybe_end_battle(province_id: int) -> void:
    if not active_battles.has(province_id):
        return
    active_battles.erase(province_id)
    print("[Combat] Бой в провинции %d завершён (враги ушли или уничтожены)" % province_id)

## Принудительно останавливает бои между двумя странами — вызывается при мире.
## Логика: если в бою кроме country_a/country_b больше никто ни с кем не воюет,
## бой завершается полностью, без урона и без "победителя" (мирное завершение).
## Если же в этом же бою участвует ещё и коалиция (например, третья страна,
## которая всё ещё воюет с одной из сторон) — сам бой продолжается, просто
## country_a и country_b перестают наносить урон друг другу (это уже гарантирует
## проверка is_at_war в _process_battle_tick).
func end_battles_between(country_a: String, country_b: String) -> void:
    var provinces_to_check: Array = active_battles.keys().duplicate()

    for province_id in provinces_to_check:
        if not active_battles.has(province_id):
            continue

        var battle = active_battles[province_id]
        var sides: Dictionary = battle["sides"]

        if not (sides.has(country_a) and sides.has(country_b)):
            continue

        if _battle_has_other_conflicts(sides, country_a, country_b):
            continue

        active_battles.erase(province_id)
        print("[Combat] Бой в провинции %d остановлен: %s и %s заключили мир" % [province_id, country_a, country_b])
        battle_ended.emit(province_id, "")

## Есть ли в бою враждующая пара, не считая саму пару country_a/country_b
func _battle_has_other_conflicts(sides: Dictionary, country_a: String, country_b: String) -> bool:
    var keys = sides.keys()
    for i in range(keys.size()):
        for j in range(i + 1, keys.size()):
            var ca = keys[i]
            var cb = keys[j]
            var is_the_peace_pair = (ca == country_a and cb == country_b) or (ca == country_b and cb == country_a)
            if is_the_peace_pair:
                continue
            if ProvinceRegistry.is_at_war(ca, cb):
                return true
    return false
