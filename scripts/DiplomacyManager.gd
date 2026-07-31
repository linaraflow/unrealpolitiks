extends Node

var settings = preload("res://new_resource.tres")

signal sanctions_imposed(attacker: String, target: String)
signal sanctions_removed(attacker: String, target: String)

## Эмитится при свержении режима ЛЮБОЙ страны (и ИИ, и игрока — одинаково).
## Слушайте этот сигнал в UI, чтобы показать ивент/уведомление "режим пал".
signal regime_collapsed(country: String, old_ideology: String, new_ideology: String)

## Эмитится ТОЛЬКО если рухнувшая страна — игрок.
## Повесьте на этот сигнал экран game over в GameManager/UI.
signal player_regime_collapsed(country: String, old_ideology: String, new_ideology: String)

const IDEOLOGIES = {
    "liberalism": {"tax": 1.0, "war": 0.5, "peace": 1.5, "mil": 0.8, "eco": 1.2},
    "parliamentary_republic": {"tax": 1.1, "war": 0.6, "peace": 1.3, "mil": 0.9, "eco": 1.1},
    "monarchy": {"tax": 1.2, "war": 1.2, "peace": 0.8, "mil": 1.1, "eco": 0.9},
    "neo_nazism": {"tax": 1.3, "war": 2.0, "peace": 0.2, "mil": 1.5, "eco": 0.5},
    "fascism": {"tax": 1.4, "war": 1.8, "peace": 0.3, "mil": 1.4, "eco": 0.6},
    "socialism": {"tax": 0.9, "war": 0.7, "peace": 1.2, "mil": 1.0, "eco": 1.3},
    "communism": {"tax": 0.8, "war": 1.5, "peace": 0.5, "mil": 1.3, "eco": 1.1},
    "dictatorship": {"tax": 1.5, "war": 1.6, "peace": 0.4, "mil": 1.3, "eco": 0.7},
    "islamic_republic": {"tax": 1.1, "war": 1.1, "peace": 0.9, "mil": 1.2, "eco": 0.8},
    "military_junta": {"tax": 1.2, "war": 1.9, "peace": 0.3, "mil": 1.6, "eco": 0.4},
    "oligarchy": {"tax": 1.6, "war": 0.8, "peace": 1.1, "mil": 0.7, "eco": 1.5}
}

# Хранит активные процессы: "sender_target" -> {"sender": String, "target": String, "days_left": int, "type": String}
var active_processes: Dictionary = {}

# ─── СВЕРЖЕНИЕ РЕЖИМА ──────────────────────────────────────────────────────────

## Пороги устойчивости режима по идеологиям.
## exhaustion_threshold — усталость от войны (0..100), начиная с которой копится риск.
## happiness_threshold  — счастье страны (0..100); риск копится, если счастье НИЖЕ этого значения.
## Авторитарные режимы подавляют недовольство и держатся дольше (высокий exhaustion_threshold,
## низкий happiness_threshold), демократии зависят от общественного мнения и падают раньше.
const REGIME_STABILITY = {
    "liberalism":             {"exhaustion_threshold": 65.0, "happiness_threshold": 35.0},
    "parliamentary_republic": {"exhaustion_threshold": 65.0, "happiness_threshold": 35.0},
    "oligarchy":               {"exhaustion_threshold": 70.0, "happiness_threshold": 32.0},
    "monarchy":                {"exhaustion_threshold": 75.0, "happiness_threshold": 30.0},
    "socialism":               {"exhaustion_threshold": 78.0, "happiness_threshold": 28.0},
    "islamic_republic":        {"exhaustion_threshold": 80.0, "happiness_threshold": 25.0},
    "communism":               {"exhaustion_threshold": 88.0, "happiness_threshold": 20.0},
    "fascism":                 {"exhaustion_threshold": 90.0, "happiness_threshold": 18.0},
    "dictatorship":            {"exhaustion_threshold": 90.0, "happiness_threshold": 15.0},
    "neo_nazism":              {"exhaustion_threshold": 92.0, "happiness_threshold": 15.0},
    "military_junta":          {"exhaustion_threshold": 92.0, "happiness_threshold": 15.0},
}

## Пороги по умолчанию для идеологий, которых почему-то нет в REGIME_STABILITY.
const REGIME_STABILITY_DEFAULT = {"exhaustion_threshold": 80.0, "happiness_threshold": 25.0}

## Базовый и максимальный шанс свержения В ДЕНЬ, когда показатель находится
## ровно на пороге / в самой критической точке (усталость=100 или счастье=0).
const REGIME_COLLAPSE_BASE_CHANCE := 0.02
const REGIME_COLLAPSE_MAX_CHANCE := 0.15

## Сколько усталости "сбрасывается" новому режиму после свержения (переходный период).
const REGIME_COLLAPSE_EXHAUSTION_RESET := 40.0

## Сколько дней после свержения новый режим "неприкасаем" — не может рухнуть снова
## (ни от усталости/счастья, ни от разрушенных фабрик). Без этого разрушенные
## фабрики никуда не деваются и режим будет валиться каждый день подряд.
const REGIME_COLLAPSE_IMMUNITY_DAYS := 60

func _ready() -> void:
    GameClock.on_day_passed.connect(_on_day_passed_diplomacy)
    # НЕ подключать country_lost_all_provinces сюда напрямую на trigger_regime_collapse:
    # у trigger_regime_collapse обязательный параметр cause, которого сигнал не передаёт.
    # Слушайте country_lost_all_provinces отдельно (например, в GameManager) для game over.

func _on_day_passed_diplomacy(_date: Dictionary) -> void:
    var completed: Array = []
    for key in active_processes.keys():
        active_processes[key]["days_left"] -= 1
        if active_processes[key]["days_left"] <= 0:
            completed.append(key)
            
    for key in completed:
        var proc = active_processes[key]
        if proc["type"] == "improve":
            change_relation(proc["sender"], proc["target"], 15.0)
        elif proc["type"] == "worsen":
            change_relation(proc["sender"], proc["target"], -15.0)
        active_processes.erase(key)

    _tick_regime_immunity()
    _check_regime_collapses()

## Раз в день уменьшаем счётчик "неприкасаемости" новых режимов.
func _tick_regime_immunity() -> void:
    var c_data = ProvinceRegistry.countries_data
    for country in c_data.keys():
        var immunity: int = int(c_data[country].get("regime_collapse_immunity_days", 0))
        if immunity > 0:
            c_data[country]["regime_collapse_immunity_days"] = immunity - 1

## Пороги устойчивости конкретной страны исходя из её текущей идеологии.
func get_regime_stability(country: String) -> Dictionary:
    var c_data = ProvinceRegistry.countries_data
    var ideology: String = c_data.get(country, {}).get("ideology", "")
    return REGIME_STABILITY.get(ideology, REGIME_STABILITY_DEFAULT)

## Доля уничтоженных фабрик (от довоенного количества), при превышении которой
## режим падает гарантированно (это не шанс/день, а прямой триггер, как потеря столицы).
const REGIME_COLLAPSE_FACTORY_DESTRUCTION_RATIO := 0.5

## Раз в день проверяем всех воюющих стран на риск свержения режима.
## У каждой идеологии свой предел усталости и свой предел счастья (см. REGIME_STABILITY).
## Риск копится, если превышен ХОТЯ БЫ ОДИН из двух порогов — берём худший случай.
## Отдельно: если с начала войны уничтожено больше половины довоенных фабрик —
## режим падает гарантированно, независимо от усталости/счастья.
func _check_regime_collapses() -> void:
    var c_data = ProvinceRegistry.countries_data
    for country in c_data.keys():
        var at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()
        if not at_war:
            continue

        if int(c_data[country].get("regime_collapse_immunity_days", 0)) > 0:
            continue

        if ProvinceRegistry.get_factory_destruction_ratio(country) >= REGIME_COLLAPSE_FACTORY_DESTRUCTION_RATIO:
            trigger_regime_collapse(country, "Economic collapse")
            continue

        var stability = get_regime_stability(country)
        var exhaustion_threshold: float = stability["exhaustion_threshold"]
        var happiness_threshold: float = stability["happiness_threshold"]

        var exhaustion: float = ProvinceRegistry.get_war_exhaustion(country)
        var happiness: float = float(c_data[country].get("happiness", 50.0))

        # Насколько мы за порогом усталости (0..1, 0 = на пороге, 1 = максимум усталости)
        var t_exhaustion: float = 0.0
        if exhaustion >= exhaustion_threshold:
            t_exhaustion = clamp((exhaustion - exhaustion_threshold) / max(100.0 - exhaustion_threshold, 0.001), 0.0, 1.0)

        # Насколько мы ниже порога счастья (0..1, 0 = на пороге, 1 = счастье == 0)
        var t_happiness: float = 0.0
        if happiness <= happiness_threshold:
            t_happiness = clamp((happiness_threshold - happiness) / max(happiness_threshold, 0.001), 0.0, 1.0)

        var t = max(t_exhaustion, t_happiness)
        if t <= 0.0:
            continue

        var chance = lerp(REGIME_COLLAPSE_BASE_CHANCE, REGIME_COLLAPSE_MAX_CHANCE, t)

        if randf() < chance:
            var cause: String = "Military collapse" if t_exhaustion >= t_happiness else "Social collapse"
            trigger_regime_collapse(country, cause)

## Определяет, является ли страна игроком.
func _is_player_country(country: String) -> bool:
    return settings.active_country == country

## ГЛАВНАЯ ФУНКЦИЯ: свергает режим страны.
## - Меняет идеологию на новую (случайную, если forced_ideology не задан).
## - Отдаёт все провинции, которые country удерживает оккупацией, их законным владельцам.
## - Все провинции самой country, которые на момент свержения оккупированы врагом,
##   окончательно переходят оккупанту (аннексируются).
## - Если страна — игрок, эмитит player_regime_collapsed (вешайте на это game over).
## - Если ИИ — просто меняет идеологию и территории, война продолжается.
func trigger_regime_collapse(country: String, cause: String, forced_ideology: String = "") -> void:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(country):
        return

    var old_ideology: String = c_data[country].get("ideology", "")

    var new_ideology: String = forced_ideology
    if new_ideology == "" or not IDEOLOGIES.has(new_ideology):
        new_ideology = _pick_random_ideology(old_ideology)

    c_data[country]["ideology"] = new_ideology

    # Переходный период: новый режим ещё не консолидировал власть, но усталость
    # частично снимается — иначе страна тут же рухнет второй раз подряд.
    c_data[country]["war_exhaustion"] = min(
        ProvinceRegistry.get_war_exhaustion(country),
        REGIME_COLLAPSE_EXHAUSTION_RESET
    )

    c_data[country]["regime_collapse_immunity_days"] = REGIME_COLLAPSE_IMMUNITY_DAYS

    _resolve_regime_collapse_territories(country)

    # Если после передела территорий у страны не осталось ни одной провинции
    # (ни своей, ни оккупированной) — она физически перестала существовать,
    # даже если официальный мир так и не заключён. Вычёркиваем её полностью,
    # иначе она будет бесконечно "менять идеологию" без единого клочка земли.
    if ProvinceRegistry.owner_province_count.get(country, 0) <= 0:
        print("[Diplomacy] %s потеряла все территории после свержения — страна уничтожена" % country)
        ProvinceRegistry._eliminate_country(country)
        return

    print("[Diplomacy] РЕЖИМ СВЕРГНУТ: %s (%s -> %s)" % [country, old_ideology, new_ideology])
    regime_collapsed.emit(country, old_ideology, new_ideology)

    if _is_player_country(country):
        player_regime_collapsed.emit(country, old_ideology, new_ideology, cause)

## Случайная идеология, отличная от текущей.
func _pick_random_ideology(exclude: String) -> String:
    var options: Array = []
    for id in IDEOLOGIES.keys():
        if id != exclude:
            options.append(id)
    if options.is_empty():
        return exclude
    return options[randi() % options.size()]

## Территориальные последствия свержения режима:
## 1) провинции, которые country держит оккупацией (её войска стоят на чужой земле) —
##    возвращаются их истинным владельцам ("фронт сыпется").
## 2) провинции самой country, которые на данный момент оккупированы врагом —
##    окончательно закрепляются за оккупантом ("центр больше не может их удержать").
func _resolve_regime_collapse_territories(country: String) -> void:
    var province_data = ProvinceRegistry.province_data
    var province_occupants = ProvinceRegistry.province_occupants

    var to_liberate: Array = []   # провинции, оккупированные country -> вернуть core_owner'у
    var to_annex: Array = []      # провинции country, оккупированные врагом -> закрепить за оккупантом

    for p_id in province_data.keys():
        var p = province_data[p_id]
        var owner: String = p.get("owner", "")
        var core_owner: String = p.get("core_owner", owner)

        if owner == country and core_owner != country and core_owner != "":
            # country удерживает чужую провинцию оккупацией
            to_liberate.append(p_id)
        elif core_owner == country and owner != country and owner != "" and owner != ProvinceRegistry.SEA_OWNER:
            # чужая страна удерживает провинцию country
            to_annex.append(p_id)

    for p_id in to_liberate:
        var core_owner: String = province_data[p_id].get("core_owner", "")
        province_data[p_id]["against_occupation"] = ""
        province_occupants.erase(p_id)
        ProvinceRegistry.capture_province(p_id, core_owner)
        ProvinceRegistry.province_occupied.emit(p_id, "")

    for p_id in to_annex:
        var occupier: String = province_data[p_id].get("owner", "")
        province_data[p_id]["against_occupation"] = ""
        province_data[p_id]["core_owner"] = occupier
        province_occupants.erase(p_id)
        ProvinceRegistry.province_occupied.emit(p_id, "")

    print("[Diplomacy] Территории после свержения %s: возвращено %d, аннексировано %d" % [
        country, to_liberate.size(), to_annex.size()
    ])

func start_relations_process(sender: String, target: String, type: String) -> bool:
    var key = sender + "_" + target
    if active_processes.has(key):
        return false
    active_processes[key] = {
        "sender": sender,
        "target": target,
        "days_left": 30,
        "type": type
    }
    return true

func get_process_progress(sender: String, target: String) -> float:
    var key = sender + "_" + target
    if not active_processes.has(key):
        return 0.0
    return (30.0 - active_processes[key]["days_left"]) / 30.0

func get_relation(country_a: String, country_b: String) -> float:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(country_a) or not c_data[country_a].has("relations"): 
        return 0.0
    return c_data[country_a]["relations"].get(country_b, 0.0)

func change_relation(country_a: String, country_b: String, amount: float) -> void:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(country_a) or not c_data.has(country_b): 
        return
        
    var current = get_relation(country_a, country_b)
    # Округляем итоговое значение отношений
    var new_rel = round(clamp(current + amount, -100.0, 100.0))
    
    c_data[country_a]["relations"][country_b] = new_rel
    c_data[country_b]["relations"][country_a] = new_rel

func change_ideology(country: String, new_ideology: String, cost: float) -> bool:
    var c_data = ProvinceRegistry.countries_data[country]
    if c_data.get("balance", 0.0) >= cost and IDEOLOGIES.has(new_ideology):
        c_data["balance"] -= cost
        c_data["ideology"] = new_ideology
        return true
    return false

func get_gdp(country: String, product_cost: float) -> float:
    var c_data = ProvinceRegistry.countries_data[country]
    var monthly = c_data.get("monthly_income", 0.0)
    var factories = c_data.get("factories", 0)
    var sanctions = c_data.get("sanctions", 0.0)
    var actual_price = product_cost * (1.0 - (sanctions / 100.0))
    return (factories * actual_price + monthly) * 12.0

func toggle_sanctions(attacker: String, target: String, cost: float) -> bool:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(attacker) or not c_data.has(target):
        return false
        
    var target_data = c_data[target]
    if not target_data.has("sanctioned_by"):
        target_data["sanctioned_by"] = {}
        
    # ЕСЛИ САНКЦИИ УЖЕ ЕСТЬ -> ОТМЕНЯЕМ
    if target_data["sanctioned_by"].has(attacker):
        target_data["sanctioned_by"].erase(attacker)
        _recalculate_total_sanctions(target)
        change_relation(attacker, target, 15.0) 
        sanctions_removed.emit(attacker, target)
        return true
        
    # ЕСЛИ САНКЦИЙ НЕТ -> НАКЛАДЫВАЕМ
    if c_data[attacker].get("balance", 0.0) >= cost:
        c_data[attacker]["balance"] -= cost
        
        # Получаем ВВП атакующего и мировой ВВП (передаем актуальную цену продукта)
        var current_product_cost = 500000.0 # Желательно брать из settings.product_cost
        var attacker_gdp = get_gdp(attacker, current_product_cost)
        var world_gdp = get_world_gdp(current_product_cost)
        
        # Формула: доля ВВП страны от мирового ВВП
        var sanction_power = (attacker_gdp / world_gdp) * 100.0
        
        target_data["sanctioned_by"][attacker] = sanction_power
        _recalculate_total_sanctions(target)
        change_relation(attacker, target, -15.0)
        sanctions_imposed.emit(attacker, target)
        return true
        
    return false

func _recalculate_total_sanctions(country: String) -> void:
    var target_data = ProvinceRegistry.countries_data[country]
    var total_power: float = 0.0
    for attacker in target_data.get("sanctioned_by", {}):
        total_power += target_data["sanctioned_by"][attacker]
        
    # Округляем до целого числа через roundi
    target_data["sanctions"] = float(roundi(clamp(total_power, 0.0, 100.0)))

func get_world_gdp(product_cost: float) -> float:
    var total_gdp = 0.0
    for country in ProvinceRegistry.countries_data.keys():
        total_gdp += get_gdp(country, product_cost)
    return max(total_gdp, 1.0) # Защита от деления на ноль




## RESET
func reset() -> void:
    active_processes = {}
