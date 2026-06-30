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

const BASE_DAMAGE   := 10000        # фиксированный урон от всей стороны (коалиции) за один тик
const TICK_INTERVAL  := 0.5       # секунды между тиками боя (реального времени)

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
    var side_keys = sides.keys()
    
    # Убираем стороны у которых больше нет кружков в провинции
    var to_remove: Array = []
    for country in side_keys:
        var valid_circles := _get_valid_circles(sides[country]["circles"], province_id, country)
        sides[country]["circles"] = valid_circles
        if valid_circles.is_empty():
            to_remove.append(country)
    
    for country in to_remove:
        sides.erase(country)
    
    if sides.size() < 2:
        # Бой завершён — победитель тот кто остался
        var winner = sides.keys()[0] if not sides.is_empty() else ""
        print("[Combat] Бой в провинции %d завершён. Победитель: %s" % [province_id, winner])
        battle_ended.emit(province_id, winner)
        return true
    
    # ── Рассчитываем урон (ФИКСИРОВАННЫЙ НА ВСЮ СТОРОНУ) ─────────────────────
    var damage_dealt: Dictionary = {}   # country -> damage
    
    for country in sides:
        # Урон не зависит от количества кружков — вся армия страны в этой провинции наносит ровно BASE_DAMAGE.
        damage_dealt[country] = BASE_DAMAGE
    
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
        
        var dmg_per_enemy = BASE_DAMAGE
        
        if not enemies[0] in hit:
            sides[enemies[0]]["hp"] -= dmg_per_enemy
            print("[Combat] Провинция %d | %s → %s: -%d HP (осталось %d)" % [
                province_id, attacker, enemies[0], dmg_per_enemy, sides[enemies[0]]["hp"]
            ])
            hit.append(enemies[0])
    
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
    
    # Если осталась одна или ноль сторон — бой окончен
    if sides.size() < 2:
        var winner = sides.keys()[0] if not sides.is_empty() else ""
        print("[Combat] Бой в провинции %d завершён. Победитель: %s" % [province_id, winner])
        battle_ended.emit(province_id, winner)
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
    var p_data = ProvinceRegistry.province_data.get(str(p_id), {})
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
