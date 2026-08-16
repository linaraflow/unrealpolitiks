extends Node

var settings = preload("res://new_resource.tres")

signal province_captured(province_id: int, new_owner: String)
signal province_army_changed(p_id: int)

# НОВЫЙ СИГНАЛ: провинция оккупирована / снята с оккупации
signal province_occupied(province_id: int, occupier: String)   # occupier="" → снятие оккупации

signal war_declared(attacker: String, defender: String)
signal war_ended(country_a: String, country_b: String)

signal country_color_changed

## Эмитится при установке/переносе столицы страны.
## province_id == -1 значит "у страны больше нет провинций" (столицу ставить некуда).
signal capital_changed(country: String, province_id: int)
signal country_eliminated(country: String)
## Эмитится РОВНО ОДИН РАЗ в момент, когда owner_province_count страны падает до 0 —
## то есть не осталось НИ ОДНОЙ провинции с owner == country (все либо оккупированы,
## либо забраны навсегда). Не путать с country_eliminated: страна может быть ещё
## "жива" (у неё остались core-owned провинции, которые вернутся после мира), но
## текущей территории под контролем у неё уже нет — именно это отслеживает сигнал.
## Сбрасывается (можно словить снова), если страна отвоюет хоть одну провинцию обратно.
signal country_lost_all_provinces(country: String)
signal factory_built(province_id: int, country: String)
## Эмитится, когда в провинции достроено укрепление (fortification)
signal fortification_built(province_id: int, country: String)
## Эмитится, когда укрепление в провинции уничтожено (например ракетой)
signal fortification_destroyed(province_id: int)
## Эмитится, когда у страны уничтожены заводы (удар БПЛА или ракетой). amount — сколько именно уничтожено.
signal factory_destroyed(province_id: int, country: String, amount: int)

## Эмитится, когда БПЛА долетел и ударил по провинции
signal uav_strike_landed(province_id: int)

## Эмитится, когда ракета долетела и ударила по провинции
signal missile_strike_landed(province_id: int)

## Эмитится при старте заказа БПЛА, при ежедневном производстве и при завершении заказа
signal uav_order_changed(country: String)

## Эмитится при старте заказа ракет, при ежедневном производстве и при завершении заказа
signal missile_order_changed(country: String)

# province_id -> country_id (строка типа "Germany", "France")
var province_owners: Dictionary = {}

# province_id -> country_id (оккупант, "" если не оккупировано)
var province_occupants: Dictionary = {}

# country_id -> индекс в массиве цветов (0..255)
var country_index: Dictionary = {}
var country_colors: Array[Color] = []
var province_data: Dictionary = {}
var province_adjacency: Dictionary = {}
var owner_province_count: Dictionary = {}  # "Germany" -> 3
# Страны, для которых country_lost_all_provinces уже эмитился и ещё не сброшен
# (сбрасывается, когда страна снова получает хотя бы одну провинцию).
var _lost_provinces_notified: Dictionary = {}
# Словарь: "Страна" -> ["Враг1", "Враг2"]
var war_relations: Dictionary = {}

var countries_data: Dictionary = {}

# ─── ТУМАН ВОЙНЫ (Fog of War) ────────────────────────────────────────────────
# Если включён — дивизии, не удовлетворяющие ни одному из условий видимости,
# скрываются с карты (см. is_division_visible()). Переключается кнопкой Fog
# в opening.gd. По умолчанию включён (совпадает с исходным состоянием кнопки).
var fog_of_war_enabled: bool = true

## Видна ли дивизия страны division_owner, стоящая в провинции division_province_id,
## игроку (settings.active_country) при включённом тумане войны. Правила:
##   1) свои дивизии — всегда видны;
##   2) дивизии страны, с которой игрок воюет, — видны везде;
##   3) дивизии, стоящие в провинции игрока или в провинции, граничащей
##      с провинцией игрока, — видны;
##   4) дивизии, стоящие в той же провинции (в т.ч. морской зоне) или в
##      провинции, граничащей с ней, где физически стоит СВОЯ дивизия, —
##      видны. Это правило отдельно от (3), т.к. морские зоны не имеют
##      owner ("sea"), и без него свой флот в море не "рассекречивал"
##      вражеские дивизии рядом с собой.
## Если туман войны выключен (или игрок ещё не выбран) — видно всё.
func is_division_visible(division_owner: String, division_province_id: int) -> bool:
    if not fog_of_war_enabled:
        return true

    var player_country: String = settings.active_country
    if player_country == "":
        return true

    if division_owner == player_country:
        return true

    if is_at_war(player_country, division_owner):
        return true

    var p_owner: String = province_data.get(division_province_id, {}).get("owner", "")
    if p_owner == player_country:
        return true

    if _has_own_division_in(player_country, division_province_id):
        return true

    for neighbor_id in province_adjacency.get(division_province_id, []):
        if province_data.get(neighbor_id, {}).get("owner", "") == player_country:
            return true
        if _has_own_division_in(player_country, neighbor_id):
            return true

    return false

## true, если у страны country физически стоит хотя бы одна дивизия
## в провинции p_id (нужно для морских зон, у которых нет owner —
## их "разведанность" определяется присутствием своих кораблей).
func _has_own_division_in(country: String, p_id: int) -> bool:
    for c in DivisionManager.armies.get(p_id, []):
        if is_instance_valid(c) and c.division_owner == country:
            return true
    return false

# Зарезервированное значение owner для морских провинций.
# "sea" НЕ является страной и НЕ должно попадать в countries.json —
# это просто маркер, который код явно распознаёт и исключает
# из экономики/дипломатии/ИИ (см. _is_real_country_owner).
const SEA_OWNER := "sea"

## true, если owner принадлежит реальной играбельной стране
## (не пустой, не "sea", и присутствует в countries_data)
func _is_real_country_owner(owner: String) -> bool:
    return owner != "" and owner != SEA_OWNER

## Проверяет owner_province_count страны и эмитит country_lost_all_provinces РОВНО
## ОДИН РАЗ, когда счётчик падает до 0. Если страна потом отвоюет провинцию —
## флаг сбрасывается, и при повторной потере всех территорий сигнал сработает снова.
## Вызывать после ЛЮБОГО изменения owner_province_count[country].
func _check_province_loss(country: String) -> void:
    if not _is_real_country_owner(country):
        return
    if owner_province_count.get(country, 0) > 0:
        _lost_provinces_notified.erase(country)
        return
    if _lost_provinces_notified.has(country):
        return
    _lost_provinces_notified[country] = true
    country_lost_all_provinces.emit(country)

var _production_by_country: Dictionary = {}
var active_constructions: Dictionary = {}

# province_id -> true, пока идёт стройка укрепления (аналогично active_constructions для заводов)
var active_fortification_constructions: Dictionary = {}

# ─── ЗАКАЗ БПЛА ────────────────────────────────────────────────────────────────
# country -> {"total": int, "remaining": float, "per_day": float}
# "per_day" фиксируется в момент оформления заказа (скорость на основе ВВП на тот момент)
var active_uav_orders: Dictionary = {}

# Делитель ВВП для расчёта скорости производства БПЛА (БПЛА/день)
const UAV_SPEED_GDP_DIVISOR := 500_000_000.0

# ─── ЗАКАЗ РАКЕТ ────────────────────────────────────────────────────────────────
# country -> {"total": int, "remaining": float, "per_month": float, "per_day": float}
# "per_month"/"per_day" фиксируются в момент оформления заказа (скорость на основе ВВП на тот момент)
var active_missile_orders: Dictionary = {}

# Делитель ВВП для расчёта скорости производства ракет (ракет/МЕСЯЦ)
const MISSILE_SPEED_GDP_DIVISOR := 2_500_000_000.0

# Сколько игровых дней считаем за "месяц" при переводе скорости ракет из "в месяц" в "в день"
const MISSILE_DAYS_PER_MONTH := 30.0

var MISSILE_KILL_RATIO = settings.MISSILE_KILL_RATIO

# ─── УСТАЛОСТЬ ОТ ВОЙНЫ ────────────────────────────────────────────────────────
const WAR_EXHAUSTION_MAX          := 100.0
const WAR_EXHAUSTION_DECAY_PER_DAY := 1.0   # снижение в день, только если страна ни с кем не воюет

var days_in_power: int = 0

var DISCORD_ID: int = 1518316614397853736

func _ready():
    _load_countries()
    _load_province_data()
    _load_province_adjacency()
    GameClock.on_day_passed.connect(_on_day_passed)
    GameClock.on_month_passed.connect(_on_month_passed)
    # ВАЖНО: элиминация страны ВСЕГДА должна проходить через _eliminate_country(),
    # чтобы гарантированно чистились war_relations, capital и т.д. Раньше сигнал
    # country_lost_all_provinces просто эмитился, а элиминация страны при потере
    # последней провинции НЕ через аннексию (например, при белом мире в end_war())
    # нигде централизованно не обрабатывалась — из-за этого где-то во внешнем коде
    # страна могла "убиваться" по кустарному пути (например, просто erase из своего
    # кэша), не трогая countries_data/war_relations здесь, и потом другие места
    # (dev_menu, AI и т.п.) падали на "мёртвой" стране. Подключаем здесь напрямую.
    country_lost_all_provinces.connect(_on_country_lost_all_provinces)
    _recalculate_all_populations()
    _recalculate_all_happiness()
    _recalculate_all_factories() # Первичный расчет фабрик при старте игры
    
    # ==== DISCORD ====
    DiscordRPC.app_id = DISCORD_ID  # ваш Application ID
    # DiscordRPC.details = "Playing"
    # DiscordRPC.state = "Taking over the world"
    DiscordRPC.large_image = "logo_3"
    # DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system())
    # DiscordRPC.refresh()  # обязательно вызывать после каждого изменения полей
    
func _process(delta: float) -> void:
    DiscordRPC.run_callbacks()

func _on_day_passed(_date: Dictionary) -> void:
    _process_economy()
    _process_uav_orders()
    _process_missile_orders()
    _decay_war_exhaustion()
    days_in_power += 1
    
func _on_month_passed(_date: Dictionary) -> void:
    # Переносим сюда, чтобы фриз (если он останется) был только раз в месяц
    _recalculate_daily_stats()

## Получить текущую усталость страны от войны (0..100)
func get_war_exhaustion(country: String) -> float:
    return float(countries_data.get(country, {}).get("war_exhaustion", 0.0))

## Добавить (или отнять, если amount отрицательный) усталость от войны стране
func add_war_exhaustion(country: String, amount: float) -> void:
    if not countries_data.has(country):
        return
    var current = get_war_exhaustion(country)
    countries_data[country]["war_exhaustion"] = clamp(current + amount, 0.0, WAR_EXHAUSTION_MAX)

## Раз в игровой день: снижаем усталость странам, которые ни с кем не воюют (полный мир)
func _decay_war_exhaustion() -> void:
    for country in countries_data:
        var at_war = not war_relations.get(country, []).is_empty()
        if at_war:
            continue
        var current = get_war_exhaustion(country)
        if current > 0.0:
            countries_data[country]["war_exhaustion"] = max(0.0, current - WAR_EXHAUSTION_DECAY_PER_DAY)

## Пересчитывает население каждой страны как сумму населения её провинций
func _recalculate_all_populations() -> void:
    var totals: Dictionary = {}
    for key in province_data:
        var p = province_data[key]
        var owner = p.get("owner", "")
        if not _is_real_country_owner(owner):
            continue
        var pop = int(p.get("population", 0))
        totals[owner] = totals.get(owner, 0) + pop

    for country in countries_data:
        countries_data[country]["population"] = totals.get(country, 0)

## Пересчитывает фабрики каждой страны с нуля, обходя ВСЕ провинции.
## Фабрики провинции всегда засчитываются текущему владельцу поля "owner"
## (оккупант провинции — это и есть её owner, см. occupy_province).
## Это O(provinces) операция, нужна только на старте игры / reset() —
## во всех остальных случаях factories страны обновляются напрямую
## (country["factories"] += ...) в момент передачи провинции, стройки
## завода или его уничтожения, кэш пересчитывать не нужно.
func _recalculate_all_factories() -> void:
    for country in countries_data:
        countries_data[country]["factories"] = 0

    for key in province_data:
        var p = province_data[key]
        var owner = p.get("owner", "")
        if _is_real_country_owner(owner):
            var f_count = int(p.get("factories", 0))
            if countries_data.has(owner):
                countries_data[owner]["factories"] += f_count

## Пересчитывает счастье каждой страны как среднее арифметическое счастья её провинций
func _recalculate_all_happiness() -> void:
    var totals: Dictionary = {}
    var counts: Dictionary = {}
    for key in province_data:
        var p = province_data[key]
        var owner = p.get("owner", "")
        if not _is_real_country_owner(owner):
            continue
        var happ = float(p.get("happiness", 50.0))
        totals[owner] = totals.get(owner, 0.0) + happ
        counts[owner] = counts.get(owner, 0) + 1

    for country in countries_data:
        var cnt = counts.get(country, 0)
        countries_data[country]["happiness"] = (totals.get(country, 0.0) / cnt) if cnt > 0 else 0.0
        
func _recalculate_daily_stats() -> void:
    var pop_totals: Dictionary = {}
    var happ_totals: Dictionary = {}
    var happ_counts: Dictionary = {}

    for key in province_data:
        var p = province_data[key]
        var owner = p.get("owner", "")
        if not _is_real_country_owner(owner):
            continue
        
        pop_totals[owner] = pop_totals.get(owner, 0) + int(p.get("population", 0))
        happ_totals[owner] = happ_totals.get(owner, 0.0) + float(p.get("happiness", 50.0))
        happ_counts[owner] = happ_counts.get(owner, 0) + 1

    for country in countries_data:
        countries_data[country]["population"] = pop_totals.get(country, 0)
        var cnt = happ_counts.get(country, 0)
        countries_data[country]["happiness"] = (happ_totals.get(country, 0.0) / cnt) if cnt > 0 else 0.0

## Среднее счастье страны (0..100), уже посчитанное, обновляется раз в игровой день
func get_country_happiness(country: String) -> float:
    return float(countries_data.get(country, {}).get("happiness", 50.0))

## Население одной провинции
func get_province_population(province_id: int) -> int:
    return int(province_data.get(province_id, {}).get("population", 0))

## Население страны (уже посчитанное, обновляется раз в игровой день)
func get_country_population(country: String) -> int:
    return int(countries_data.get(country, {}).get("population", 0))
    
## Количество дней, которое игрок находится у власти
func get_days_in_power() -> String:
    return str(days_in_power)

func _load_province_data():
    if not FileAccess.file_exists("res://scripts/provinces.json"): 
        return
    var file = FileAccess.open("res://scripts/provinces.json", FileAccess.READ)
    var json = JSON.new()
    json.parse(file.get_as_text())
    
    province_data.clear()
    
    # Объединяем конвертацию ключей и поиск оккупации в один быстрый цикл
    for key_str in json.data:
        var p_id = int(key_str)
        var p_info = json.data[key_str]
        
        province_data[p_id] = p_info
        
        # Восстанавливаем оккупацию сразу же
        var occ = p_info.get("against_occupation", "")
        if occ != "":
            province_occupants[p_id] = occ
            
    settings.province_data = province_data
    _rebuild_count_cache()


func _load_province_adjacency():
    if not FileAccess.file_exists("res://scripts/province_adjacency.json"):
        return
    var file = FileAccess.open("res://scripts/province_adjacency.json", FileAccess.READ)
    var json = JSON.new()
    json.parse(file.get_as_text())
    
    province_adjacency.clear()
    
    # Конвертируем ключи в int, а массивы соседей в Array[int]
    for key_str in json.data:
        var p_id = int(key_str)
        var raw_neighbors = json.data[key_str]
        
        var neighbors: Array[int] = []
        for neighbor in raw_neighbors:
            neighbors.append(int(neighbor))
            
        province_adjacency[p_id] = neighbors
        
    settings.province_adjacency = province_adjacency

func _rebuild_count_cache():
    owner_province_count.clear()
    for key in province_data:
        var owner = province_data[key].get("owner", "")
        if owner == SEA_OWNER:
            continue
        owner_province_count[owner] = owner_province_count.get(owner, 0) + 1

func _load_countries():
    if not FileAccess.file_exists("res://scripts/countries.json"):
        return
    var file = FileAccess.open("res://scripts/countries.json", FileAccess.READ)
    var json = JSON.new()
    json.parse(file.get_as_text())
    countries_data = json.data

    for key in json.data:
        var entry = json.data[key]
        var i = entry["index"]
        country_index[key] = i
        var c = entry["color"]
        while country_colors.size() <= i:
            country_colors.append(Color())
        country_colors[i] = Color(c[0]/255.0, c[1]/255.0, c[2]/255.0)
        
        if not entry.has("relations"):
            entry["relations"] = {}
        if not entry.has("sanctions"):
            entry["sanctions"] = 0.0
        if not entry.has("war_exhaustion"):
            entry["war_exhaustion"] = 0.0
        if not entry.has("control"):
            entry["control"] = []
        if not entry.has("controller"):
            entry["controller"] = ""

# ─── ЗАХВАТ (полная передача владения) ────────────────────────────────────────

func capture(from_country: String, to_country: String) -> void:
    for p_id in province_owners.keys().duplicate():
        if province_owners[p_id] == from_country:
            capture_province(p_id, to_country)

func capture_province(province_id: int, new_owner: String) -> void:
    var old_owner = province_data[province_id].get("owner", "")
    if old_owner == SEA_OWNER:
        return

    if old_owner != "":
        owner_province_count[old_owner] = owner_province_count.get(old_owner, 1) - 1
        
        # Проверяем, не была ли захвачена столица
        _check_capital_transfer(province_id, old_owner)
        
    owner_province_count[new_owner] = owner_province_count.get(new_owner, 0) + 1
    _set_owner(province_id, new_owner)
    province_data[province_id]["owner"] = new_owner

    # Владелец провинции сменился (в т.ч. оккупация — оккупант становится owner'ом) —
    # передаём фабрики провинции напрямую новому владельцу, никакого кэша/пересчёта.
    var f_count = int(province_data[province_id].get("factories", 0))
    if f_count > 0:
        if _is_real_country_owner(old_owner) and countries_data.has(old_owner):
            countries_data[old_owner]["factories"] = max(0, countries_data[old_owner].get("factories", 0) - f_count)
        if _is_real_country_owner(new_owner) and countries_data.has(new_owner):
            countries_data[new_owner]["factories"] = countries_data[new_owner].get("factories", 0) + f_count

    # Население провинции точно так же переносим сразу, а не ждём ежемесячного
    # _recalculate_daily_stats(). Без этого, например, страна, возвращённая по миру
    # после полной оккупации, месяц показывает population == 0 (её провинции не
    # засчитывались владельцу, пока были оккупированы, а кэш population страны
    # обновляется только раз в игровой месяц).
    var p_count = int(province_data[province_id].get("population", 0))
    if p_count > 0:
        if _is_real_country_owner(old_owner) and countries_data.has(old_owner):
            countries_data[old_owner]["population"] = max(0, countries_data[old_owner].get("population", 0) - p_count)
        if _is_real_country_owner(new_owner) and countries_data.has(new_owner):
            countries_data[new_owner]["population"] = countries_data[new_owner].get("population", 0) + p_count


    # ВАЖНО: вызывать после того, как все поля выше уже обновлены — эмит сигнала
    # ниже может синхронно вызвать код, который что-то стирает из countries_data
    # (например, элиминацию страны), и делать это нужно только когда capture_province
    # уже полностью не зависит от собственных локальных переменных.
    if old_owner != "":
        _check_province_loss(old_owner)
    _check_province_loss(new_owner)

    # Владение провинцией изменилось — старые закэшированные пути через неё
    # (посчитанные для старого владельца) могут стать неверными.
    PathCache.invalidate_cache()

func _set_owner(p_id: int, new_owner: String) -> void:
    province_owners[p_id] = new_owner
    province_captured.emit(p_id, new_owner)

# ─── ОККУПАЦИЯ ────────────────────────────────────────────────────────────────

## Оккупировать провинцию
func occupy_province(province_id: int, occupier: String) -> void:
    var key = province_id
    if not province_data.has(key):
        return

    var current_owner = province_data[key].get("owner", "")
    if current_owner == occupier:
        return

    # Морские провинции никогда не оккупируются и не меняют владельца
    if current_owner == SEA_OWNER:
        return

    # Фиксируем истинного владельца ОДИН раз — при первом захвате провинции
    if not province_data[key].has("core_owner"):
        var existing_stripes = province_data[key].get("against_occupation", "")
        province_data[key]["core_owner"] = existing_stripes if existing_stripes != "" else current_owner

    var core_owner = province_data[key]["core_owner"]

    # ЗАЩИТА ОТ "ПРИЗРАЧНОГО" ВЛАДЕЛЬЦА: страна-core_owner уже могла быть
    # уничтожена _eliminate_country() РАНЬШЕ в этом же батче захвата (например,
    # когда последняя "живая" провинция страны берётся раньше, чем эта — та,
    # что оккупируется впервые только сейчас). В этом случае _check_province_loss
    # для неё больше не сработает (флаг _lost_provinces_notified уже стоит), и
    # провинция навсегда зависнет в province_occupants с owner'ом-призраком,
    # которого нет в countries_data — её нельзя будет ни аннексировать, ни
    # вернуть миром, потому что война уже завершена вместе со смертью страны.
    # Поэтому сразу закрепляем такую провинцию за захватчиком, как и в случае
    # с "третьей стороной" ниже.
    if not countries_data.has(core_owner):
        province_data[key]["core_owner"] = occupier
        province_data[key]["against_occupation"] = ""
        province_occupants.erase(province_id)
        capture_province(province_id, occupier)
        province_occupied.emit(province_id, "")
        #print("[Registry] Провинция %d: истинный владелец %s уже уничтожен, закреплена за %s" % [province_id, core_owner, occupier])
        return

    # Возврат провинции происходит только если оккупант — это ИСТИННЫЙ владелец
    if occupier == core_owner:
        province_data[key]["against_occupation"] = ""
        province_occupants.erase(province_id)
        capture_province(province_id, occupier)
        province_occupied.emit(province_id, "")
        #print("[Registry] Провинция %d освобождена и возвращена %s" % [province_id, occupier])
        return

    # НОВОЕ: провинция принадлежит ТРЕТЬЕЙ стороне (её true owner — не текущий
    # контролёр и не новый захватчик). Пример: Германия оккупировала провинцию
    # Нидерландов, а мы (Польша), воюя с Германией, отбиваем эту провинцию у неё.
    # Раньше такая провинция просто "наследовалась" новым захватчиком с полосами
    # третьей страны и потом навсегда зависала под его контролем — её нельзя было
    # ни забрать в мирном договоре (там сверяют полосы именно с врагом), ни вернуть
    # обратно. Теперь она сразу автоматически освобождается и возвращается
    # истинному владельцу, минуя нового захватчика.
    if core_owner != occupier and core_owner != current_owner:
        # Защита: если "истинный владелец" уже не существует (страна была
        # уничтожена, а по какой-то причине эта провинция не была почищена
        # в _eliminate_country — например, старое сохранение), возвращать
        # провинцию некому. Оставляем её текущему захватчику как обычную
        # оккупацию, а не создаём owner'а-призрака.
        if not countries_data.has(core_owner):
            province_data[key]["core_owner"] = occupier
            province_data[key]["against_occupation"] = ""
            province_occupants.erase(province_id)
            capture_province(province_id, occupier)
            province_occupied.emit(province_id, "")
            #print("[Registry] Провинция %d: истинный владелец %s не существует, закреплена за %s" % [province_id, core_owner, occupier])
            return

        province_data[key]["against_occupation"] = ""
        province_occupants.erase(province_id)
        capture_province(province_id, core_owner)
        province_occupied.emit(province_id, "")
        #print("[Registry] Провинция %d (третья сторона, истинный владелец %s) освобождена при захвате %s" % [province_id, core_owner, occupier])
        return

    # Полосы ВСЕГДА показывают истинного владельца, а не последнего контролёра
    province_data[key]["against_occupation"] = core_owner
    province_occupants[province_id] = core_owner
    capture_province(province_id, occupier)
    province_occupied.emit(province_id, core_owner)

    #print("[Registry] Провинция %d захвачена %s (полосы: %s)" % [province_id, occupier, core_owner])
    

## Снять оккупацию (например при освобождении провинции)
func liberate_province(province_id: int) -> void:
    var key = province_id
    if not province_data.has(key):
        return

    province_occupants.erase(province_id)
    province_data[key]["against_occupation"] = ""

    # owner провинции не меняется (это только снятие "полос") — на фабрики,
    # которые уже считаются за текущим owner'ом, это никак не влияет.

    #print("[Registry] Оккупация снята с провинции %d" % province_id)
    province_occupied.emit(province_id, "")

## Аннексировать все оккупированные провинции одной страны.
## Вызывать при мирном договоре или кнопкой в тестовом режиме.
##
## only_from — опционально ограничивает аннексию провинциями, чей core_owner
## именно эта страна. БЕЗ этого ограничения (only_from == "") occupier
## аннексирует ВСЁ, что он сейчас оккупирует, включая территории третьих
## стран, отжатые в других, не связанных с этим миром войнах — из-за чего
## заключение мира с одним врагом могло случайно "добить" (аннексировать
## последнюю провинцию и удалить из countries_data) совершенно постороннюю
## страну, парализуя её на карте (см. AIDiplomacy.try_make_peace).
func annex_all_occupied_by(occupier: String, only_from: String = "") -> void:
    #print("=== ANNEX === occupier:", occupier, " only_from:", only_from)
    #print("=== ANNEX === province_occupants:", province_occupants)
    
    var to_annex: Array[int] = []
    for p_id in province_occupants:
        if province_occupants[p_id] != "":
            var current_owner = province_data[p_id].get("owner", "")
            #print("p_id:", p_id, " owner:", current_owner)
            if current_owner == occupier:
                if only_from != "":
                    var core = province_data[p_id].get("core_owner", "")
                    if core != only_from:
                        continue
                to_annex.append(p_id)

    # Запоминаем, у кого именно аннексия отбирает провинции (core_owner ДО перезаписи),
    # чтобы после аннексии проверить — не остались ли эти страны совсем без земли.
    var affected_old_owners: Dictionary = {}
    for p_id in to_annex:
        var old_core = province_data[p_id].get("core_owner", "")
        if old_core != "" and old_core != occupier:
            affected_old_owners[old_core] = true

    for p_id in to_annex:
        province_data[p_id]["against_occupation"] = ""
        province_data[p_id]["core_owner"] = occupier   # аннексия узаконивает нового владельца
        province_occupants.erase(p_id)
        province_occupied.emit(p_id, "")

    # Аннексия только узаконивает уже существующего owner'а (occupier) и убирает
    # полосы — owner провинции при этом не меняется, значит и фабрики уже
    # засчитаны occupier'у (см. capture_province), пересчитывать нечего.

    #print("[Registry] Полосы убраны с %d провинций %s" % [to_annex.size(), occupier])

    # Аннексия могла лишить кого-то из прежних владельцев ПОСЛЕДНЕЙ провинции —
    # capture_province() тут не вызывается, поэтому _check_capital_transfer сам
    # не сработает. Проверяем это здесь явно.
    for old_owner in affected_old_owners:
        if not _has_any_province_left(old_owner):
            _eliminate_country(old_owner)

## Проверить — оккупирована ли провинция
func is_occupied(province_id: int) -> bool:
    return province_occupants.has(province_id) and province_occupants[province_id] != ""

## Получить оккупанта провинции (или "" если не оккупирована)
func get_occupant(province_id: int) -> String:
    return province_occupants.get(province_id, "")

# ─── ВОЙНА ────────────────────────────────────────────────────────────────────

func declare_war(attacker: String, defender: String):
    if not countries_data.has(attacker):
        push_error("declare_war: страна-агрессор '%s' отсутствует в countries_data" % attacker)
        return
    if not countries_data.has(defender):
        push_error("declare_war: страна-защитник '%s' отсутствует в countries_data" % defender)
        return

    # Снимок фабрик "на начало войны" — только когда страна входит в войну ИЗ МИРА
    # (0 активных войн). Пока страна не вернётся к 0 войнам, снимок не обновляется,
    # даже если по пути она объявит войну ещё кому-то или на неё нападут ещё раз.
    if war_relations.get(attacker, []).is_empty():
        countries_data[attacker]["prewar_factories"] = countries_data[attacker].get("factories", 0)
    if war_relations.get(defender, []).is_empty():
        countries_data[defender]["prewar_factories"] = countries_data[defender].get("factories", 0)

    if not war_relations.has(attacker):
        war_relations[attacker] = []
    if not war_relations.has(defender):
        war_relations[defender] = []

    if not defender in war_relations[attacker]:
        war_relations[attacker].append(defender)
    if not attacker in war_relations[defender]:
        war_relations[defender].append(attacker)

    countries_data[attacker]["is_at_war"] = true
    countries_data[defender]["is_at_war"] = true

    # Агрессор (тот, кто ИНИЦИИРОВАЛ войну) получает рост скрытой "агрессивности"
    # и мировые санкции. Работает одинаково и для ИИ, и для игрока.
    DiplomacyManager.register_aggression(attacker)

    #print("War: ", attacker, " vs ", defender)
    war_declared.emit(attacker, defender)

    # Проходимость чужой территории зависит от is_at_war() — начало войны
    # могло открыть новые пути, которые раньше считались недоступными.
    PathCache.invalidate_cache()

func is_at_war(country_a: String, country_b: String) -> bool:
    return war_relations.get(country_a, []).has(country_b)

## Доля фабрик, уничтоженных с начала текущей серии войн (0..1).
## Возвращает 0, если снимок "довоенных фабрик" ещё не сделан (страна не воевала)
## или довоенных фабрик было 0 (нечего разрушать в процентах).
func get_factory_destruction_ratio(country: String) -> float:
    if not countries_data.has(country):
        return 0.0
    var prewar: int = int(countries_data[country].get("prewar_factories", -1))
    if prewar <= 0:
        return 0.0
    var current: int = int(countries_data[country].get("factories", 0))
    return clamp(1.0 - (float(current) / float(prewar)), 0.0, 1.0)

## Снимает статус войны между двумя странами (флаги is_at_war, war_relations,
## остановка активных боёв) — БЕЗ передела территории ("белого мира").
## Вынесено отдельно от end_war(), чтобы _eliminate_country() могла снять
## войну с мёртвой страной, не запуская возврат ей провинций (см. end_war).
func _clear_war_state(country_a: String, country_b: String) -> void:
    if war_relations.has(country_a):
        war_relations[country_a].erase(country_b)
    if war_relations.has(country_b):
        war_relations[country_b].erase(country_a)

    if war_relations.get(country_a, []).is_empty():
        if countries_data.has(country_a):
            countries_data[country_a]["is_at_war"] = false
            countries_data[country_a]["prewar_factories"] = -1  # снимок устареет, обновится в следующей войне

    if war_relations.get(country_b, []).is_empty():
        if countries_data.has(country_b):
            countries_data[country_b]["is_at_war"] = false
            countries_data[country_b]["prewar_factories"] = -1

    # Останавливаем все текущие бои между этими двумя странами — иначе бой,
    # не имея урона (обе стороны больше не at_war), навсегда "зависает"
    # в active_battles, а армии не освобождаются.
    CombatManager.end_battles_between(country_a, country_b)

    # Окончание войны тоже меняет проходимость (мир может закрыть транзит
    # через территорию бывшего врага) — сбрасываем кэш путей.
    PathCache.invalidate_cache()

func end_war(country_a: String, country_b: String) -> void:
    _clear_war_state(country_a, country_b)

    # === Белый мир: провинции возвращаются своим корам ===
    var provinces_to_liberate = []
    for p_id in province_occupants.keys():
        var key = p_id
        var core = province_data[key].get("core_owner", province_occupants[p_id])
        var current_owner = province_data[key].get("owner", "")

        if current_owner == core:
            continue  # уже и так у себя дома, нечего освобождать

        var core_is_party = (core == country_a or core == country_b)
        var occupier_is_party = (current_owner == country_a or current_owner == country_b)

        # Освобождаем только те провинции, где ОБЕ стороны (кор-владелец и текущий
        # оккупант) относятся именно к этим двум странам — то есть провинция реально
        # является предметом ЭТОЙ войны. Иначе, например, при мире со страной B
        # возвращались бы и провинции, отнятые у страны C, с которой война всё ещё продолжается.
        if core_is_party and occupier_is_party:
            provinces_to_liberate.append(p_id)

    for p_id in provinces_to_liberate:
        var key = p_id
        var core = province_data[key].get("core_owner", "")

        province_data[key]["against_occupation"] = ""
        province_occupants.erase(p_id)
        capture_province(p_id, core)
        province_occupied.emit(p_id, "")

    #print("[Registry] Война завершена: %s и %s (возвращено провинций: %d)" % [country_a, country_b, provinces_to_liberate.size()])
    war_ended.emit(country_a, country_b)
    
## Установить столицу страны и сохранить ТОЛЬКО поле "capital" в countries.json
## (остальные данные в файле не трогаем — читаем файл заново перед записью,
## чтобы не затереть то, что могло измениться помимо памяти рантайма).
func set_capital(country: String, province_id: int) -> void:
    if country == "" or not countries_data.has(country):
        #print("[Registry] set_capital: нет такой страны: ", country)
        return

    countries_data[country]["capital"] = province_id
    #print("[Registry] Столица %s установлена вручную: %d" % [country, province_id])

    _save_capital_to_file(country, province_id)
    capital_changed.emit(country, province_id)


func _save_capital_to_file(country: String, province_id: int) -> void:
    var path = "res://scripts/countries.json"
    if not FileAccess.file_exists(path):
        #print("[Registry] _save_capital_to_file: файл не найден: ", path)
        return

    var read_file = FileAccess.open(path, FileAccess.READ)
    var json = JSON.new()
    var parse_err = json.parse(read_file.get_as_text())
    read_file.close()

    if parse_err != OK:
        #print("[Registry] _save_capital_to_file: ошибка парсинга JSON")
        return

    var data: Dictionary = json.data
    if not data.has(country):
        #print("[Registry] _save_capital_to_file: страны нет в файле: ", country)
        return

    # Меняем на диске ТОЛЬКО поле capital, всё остальное в файле остаётся как было
    data[country]["capital"] = province_id

    var write_file = FileAccess.open(path, FileAccess.WRITE)
    write_file.store_string(JSON.stringify(data, "\t"))
    write_file.close()

    #print("[Registry] countries.json обновлён: capital[%s] = %d" % [country, province_id])


## Есть ли у страны хоть одна провинция — своя (owner) или "по праву" (core_owner,
## временно оккупированная, но гарантированно вернётся после мира).
## ignore_p_id — опционально исключить одну провинцию из проверки (например,
## ту, что как раз в этот момент захватывается — до того как owner в ней сменился).
func _has_any_province_left(country: String, ignore_p_id: int = -1) -> bool:
    for p_id in province_data.keys():
        if int(p_id) == ignore_p_id:
            continue
        var p = province_data[p_id]
        if p.get("owner", "") == country:
            return true
        if p.get("core_owner", p.get("owner", "")) == country:
            return true
    return false

## Обработчик country_lost_all_provinces: у страны не осталось ни одной provinces с
## owner == country (owner_province_count упал до 0). Это ещё НЕ значит, что страна
## уничтожена — у неё могут оставаться core-owned провинции, которые она удерживает
## только оккупацией противника и которые гарантированно вернутся после заключения
## мира. В этом случае страна физически ещё жива, у неё просто нет территории под
## прямым контролем — правильная реакция игры на это: свержение режима (сдача/
## коллапс фронта), а НЕ полное уничтожение страны. Полностью уничтожаем страну
## только если у неё нет вообще никаких провинций — ни owner, ни core_owner.
func _on_country_lost_all_provinces(country: String) -> void:
    if _has_any_province_left(country):
        DiplomacyManager.trigger_regime_collapse(country, tr("CAUSE_TOTAL_OCCUPATION"))
        return
    _eliminate_country(country)

## Полное уничтожение страны: убираем столицу, снимаем войны, стираем из countries_data.
## Вызывать только когда точно установлено, что у страны не осталось НИ одной
## провинции (ни своей, ни core-owned).
func _eliminate_country(country: String) -> void:
    if not countries_data.has(country):
        return

    # Подстраховка: если страна дошла до полного уничтожения путём, который не
    # проходит через capture_province (аннексия при свержении режима и т.п.),
    # эмит через guard всё равно сработает (и не задублируется, если уже сработал).
    #
    # ВАЖНО: _check_province_loss() может СИНХРОННО заэмитить
    # country_lost_all_provinces, на который подписан
    # _on_country_lost_all_provinces() — а он, в свою очередь, может повторно
    # (реентерабельно) вызвать _eliminate_country(country) прямо сейчас, пока
    # мы ещё внутри этого, первого, вызова. Вложенный вызов дойдёт до конца
    # и сделает countries_data.erase(country) РАНЬШЕ, чем мы вернёмся сюда.
    # Поэтому после _check_province_loss нужно перепроверить, не стёрли ли
    # страну уже — иначе обращение к countries_data[country] ниже упадёт с
    # "Invalid access to property or key" (баг с Oman).
    _check_province_loss(country)
    if not countries_data.has(country):
        return

    #print("[Registry] Страна %s потеряла последнюю провинцию (столицу)" % country)
    # Сначала чистим поле в самих данных — чтобы к моменту сигнала
    # никто, читающий countries_data напрямую, не увидел старую столицу.
    countries_data[country]["capital"] = -1
    # Сигналим -1, чтобы карта убрала звёздочку столицы у уничтоженной страны
    capital_changed.emit(country, -1)

    # Снимаем со всех оставшихся врагов состояние "война" с мёртвой страной.
    # ВАЖНО: используем _clear_war_state(), а НЕ end_war() — end_war() запускает
    # "белый мир" и вернул бы уничтоженной стране (доля секунды до erase) все
    # провинции, которые враг успел у неё захватить, но ещё не аннексировал.
    # Это и было причиной бага "страна пропала, а её территория осталась
    # на карте, но не кликается и не управляется ИИ": провинции получали
    # owner = country прямо перед тем, как country стиралась из countries_data.
    for enemy in war_relations.get(country, []).duplicate():
        _clear_war_state(country, enemy)
    war_relations.erase(country)

    # КРИТИЧНО: провинции, которые ждали возврата ЭТОЙ стране как "истинному
    # владельцу" (core_owner == country, но сейчас оккупированы кем-то ещё),
    # больше не могут ей вернуться — страны больше нет. Если это не почистить,
    # occupy_province()/end_war() рано или поздно попробуют сделать
    # capture_province(p_id, country) для уже стёртой из countries_data страны —
    # провинция получит "призрачного" owner'а, которого нет в countries_data,
    # и это уронит любой код, читающий countries_data[owner] (dev_menu и т.п.).
    # Поэтому сразу закрепляем такие провинции за их текущим фактическим
    # владельцем (по сути — молчаливая аннексия) и убираем полосы оккупации.
    for p_id in province_data.keys():
        var p = province_data[p_id]
        if p.get("core_owner", "") == country:
            var current_owner = p.get("owner", "")
            p["core_owner"] = current_owner
            p["against_occupation"] = ""
            if province_occupants.has(p_id):
                province_occupants.erase(p_id)
                province_occupied.emit(p_id, "")

    country_eliminated.emit(country)
    countries_data.erase(country)

func _check_capital_transfer(captured_p_id: int, old_owner: String) -> void:
    if not countries_data.has(old_owner):
        return
        
    var current_capital = int(countries_data[old_owner].get("capital", 0))
    
    # Если захваченная провинция — это столица
    if current_capital == captured_p_id:
        # Провинции, которыми страна владеет ПРЯМО СЕЙЧАС (не оккупированы) —
        # в первую очередь переносим столицу туда.
        var owned_provinces: Array = []
        # Провинции, где страна остаётся ИСТИННЫМ (core) владельцем, но сейчас
        # оккупированы кем-то другим. Они гарантированно вернутся после мира —
        # поэтому из-за них страну считать уничтоженной НЕЛЬЗЯ.
        var core_provinces: Array = []

        for p_id in province_data.keys():
            var p = province_data[p_id]

            # "Владение" (owner) у захваченной провинции уже реально сменилось —
            # её исключаем из owned_provinces.
            if int(p_id) != captured_p_id and p.get("owner", "") == old_owner:
                owned_provinces.append(int(p_id))

            # А вот core_owner при обычной оккупации НЕ меняется (меняется только
            # при аннексии, см. annex_all_occupied_by) — поэтому захваченную
            # провинцию из этой проверки исключать нельзя: если она "core" страны,
            # страна формально всё ещё жива и продолжает воевать, даже будучи
            # оккупированной целиком.
            #
            # ВАЖНО: смотрим именно на явно выставленный ключ core_owner (его
            # ставит ТОЛЬКО occupy_province при военной оккупации), а не на
            # p.get("core_owner", p.get("owner", "")) с фолбэком на owner.
            # Если ключа core_owner нет — значит владение провинцией меняется
            # ОКОНЧАТЕЛЬНО (мирный договор "забрать все территории" / прямой
            # capture_province, минуя occupy_province), и на момент этой проверки
            # p["owner"] ещё не переписан на нового владельца (это происходит
            # чуть позже в capture_province) — поэтому фолбэк на owner ошибочно
            # засчитывал такую провинцию как "core" старой страны и не давал
            # её уничтожить, а столица навсегда "застревала" на уже полностью
            # чужой территории.
            if p.get("core_owner", "") == old_owner:
                core_provinces.append(int(p_id))

        # Есть куда перенести столицу среди своих (не оккупированных) провинций
        if not owned_provinces.is_empty():
            var new_capital = owned_provinces.pick_random()
            countries_data[old_owner]["capital"] = new_capital
            #print("[Registry] Столица %s перенесена в провинцию %d" % [old_owner, new_capital])
            capital_changed.emit(old_owner, new_capital)
            return

        # Своих (не оккупированных) провинций нет, но страна ещё жива —
        # у неё остались провинции, которые по праву принадлежат ей и вернутся
        # после заключения мира. Временно "паркуем" столицу на одной из них.
        if not core_provinces.is_empty():
            var parked_capital = core_provinces.pick_random()
            countries_data[old_owner]["capital"] = parked_capital
            #print("[Registry] %s полностью оккупирована, столица временно перенесена в %d (ждёт освобождения)" % [old_owner, parked_capital])
            capital_changed.emit(old_owner, parked_capital)
            return

        # Ни своих, ни core-owned провинций не осталось — страна реально уничтожена.
        _eliminate_country(old_owner)


# ЭКОНОМИКА
## Точечно корректирует monthly_income страны при изменении численности войск
## (вызывается при найме в DivisionManager и при потерях в CombatManager —
## O(1), без обхода всех провинций/стран)
##
## ВАЖНО: помимо точечной правки monthly_income (для мгновенного эффекта на баланс),
## накапливаем ту же поправку в "troop_upkeep" — её обязан учитывать
## AIManager._calculate_monthly_income() при ежемесячном полном пересчёте.
## Иначе полный пересчёт (раз в месяц / при reset) отбрасывает базу
## "население × налог" и стирает все точечные поправки от найма/потерь войск.
func adjust_monthly_income_for_troops(country: String, troop_delta: int) -> void:
    if not countries_data.has(country):
        return
    var upkeep_delta = troop_delta * 100.0

    var current = float(countries_data[country].get("monthly_income", 0.0))
    countries_data[country]["monthly_income"] = current - upkeep_delta

    var upkeep = float(countries_data[country].get("troop_upkeep", 0.0))
    countries_data[country]["troop_upkeep"] = upkeep + upkeep_delta

func _process_economy() -> void:
    var to_remove = []
    
    # 1. Продвигаем ТОЛЬКО активные стройки (быстрый цикл)
    for p_id in active_constructions:
        var key = p_id
        var p = province_data[key]
        
        if p.has("factory_queue") and p["factory_queue"].size() > 0:
            p["factory_queue"][0] += 1
            if p["factory_queue"][0] >= 15:
                p["factory_queue"].pop_front()
                p["factories"] = p.get("factories", 0) + 1

                # Инкрементируем фабрику напрямую, не трогая остальные 9999 провинций
                var owner = p.get("owner", "")
                if owner != "" and countries_data.has(owner):
                    countries_data[owner]["factories"] = countries_data[owner].get("factories", 0) + 1

                # Прирост населения провинции после постройки фабрики
                # (фиксированное значение задаётся в settings.FACTORY_POPULATION_BONUS)
                var pop_before = int(p.get("population", 0))
                var pop_bonus = int(settings.FACTORY_POPULATION_BONUS)
                if pop_bonus > 0:
                    p["population"] = pop_before + pop_bonus
                    if owner != "" and countries_data.has(owner):
                        countries_data[owner]["population"] = countries_data[owner].get("population", 0) + pop_bonus

                # Прирост счастья провинции после постройки фабрики (+1, максимум 100)
                var happ_before = float(p.get("happiness", 50.0))
                p["happiness"] = min(100.0, happ_before + 1.0)

                # Сигналим карте, что в этой провинции достроился завод
                # (owner может быть "" — тогда просто некому подсвечивать)
                factory_built.emit(p_id, owner)

                if p["factory_queue"].is_empty():
                    to_remove.append(p_id)
        else:
            to_remove.append(p_id)
            
    # Чистим завершенные стройки
    for p_id in to_remove:
        active_constructions.erase(p_id)

    # 2. Продвигаем стройки укреплений (fortification)
    var fort_to_remove = []
    for p_id in active_fortification_constructions:
        var p = province_data[p_id]

        # Если провинцию за это время оккупировали/захватили — стройку укрепления
        # отменяем (деньги не возвращаем, как и для заводов, но и не достраиваем).
        p["fortification_progress"] = int(p.get("fortification_progress", 0)) + 1

        if p["fortification_progress"] >= int(settings.TIME_FORTIFICATION):
            p["fortification"] = true
            p.erase("fortification_progress")
            fort_to_remove.append(p_id)

            var owner = p.get("owner", "")
            fortification_built.emit(p_id, owner)

    for p_id in fort_to_remove:
        active_fortification_constructions.erase(p_id)

    # 3. Начисляем продукты
    for country in countries_data:
        var total_factories: int = countries_data[country].get("factories", 0)
        if total_factories > 0:
            var daily_product := total_factories / 30.0
            countries_data[country]["products"] = countries_data[country].get("products", 0.0) + daily_product

## Приблизительный ВВП страны за год:
## (заводы × стоимость продукта + месячный доход) × 12
func get_gdp(country: String) -> float:
    var data = countries_data.get(country, {})
    var factories = float(data.get("factories", 0))
    var product_cost = settings.product_cost
    var monthly_income = float(data.get("monthly_income", 0))
    return (factories * product_cost + monthly_income) * 12.0

# ─── ЗАКАЗ БПЛА ────────────────────────────────────────────────────────────────

## Скорость производства БПЛА (шт/день) исходя из текущего ВВП страны
func get_uav_production_speed(country: String) -> float:
    var gdp = get_gdp(country)
    return gdp / UAV_SPEED_GDP_DIVISOR

## Есть ли у страны активный заказ БПЛА в производстве
func has_active_uav_order(country: String) -> bool:
    return active_uav_orders.has(country)

## Инфо по активному заказу: {"total", "remaining", "per_day"} (пустой Dictionary если заказа нет)
func get_uav_order_info(country: String) -> Dictionary:
    return active_uav_orders.get(country, {})

## Оформить заказ на amount БПЛА. Списывает всю стоимость сразу.
## Возвращает false, если нельзя оформить (уже есть заказ / не хватает денег / amount некорректен).
func start_uav_order(country: String, amount: int) -> bool:
    if amount <= 0:
        return false
    if has_active_uav_order(country):
        return false
    if not countries_data.has(country):
        return false

    var uav_cost: float = settings.uav_cost
    var cost: float = uav_cost * amount
    if country == settings.active_country:
        cost *= settings.get_cost_multiplier()

    if countries_data[country].get("products", 0.0) < cost:
        return false

    var speed = get_uav_production_speed(country)
    if speed <= 0.0:
        return false  # нет производственных мощностей — заказ невозможен

    countries_data[country]["products"] -= cost

    active_uav_orders[country] = {
        "total": amount,
        "remaining": float(amount),
        "per_day": speed,
    }

    #print("[Registry] %s заказал %d БПЛА (скорость %.2f/день)" % [country, amount, speed])
    uav_order_changed.emit(country)
    return true

## Раз в игровой день: продвигаем все активные заказы БПЛА,
## постепенно добавляя произведённые дроны в country_data["uav"]
func _process_uav_orders() -> void:
    if active_uav_orders.is_empty():
        return

    var finished: Array[String] = []

    for country in active_uav_orders:
        var order: Dictionary = active_uav_orders[country]
        var per_day: float = order["per_day"]
        var deliver: float = min(per_day, order["remaining"])

        if deliver > 0.0 and countries_data.has(country):
            countries_data[country]["uav"] = countries_data[country].get("uav", 0.0) + deliver
            order["remaining"] -= deliver

        if order["remaining"] <= 0.0001:
            finished.append(country)

        uav_order_changed.emit(country)

    for country in finished:
        active_uav_orders.erase(country)
        #print("[Registry] Заказ БПЛА страны %s завершён" % country)
        uav_order_changed.emit(country)

# ─── ЗАКАЗ РАКЕТ ────────────────────────────────────────────────────────────────

## Скорость производства ракет (шт/МЕСЯЦ) исходя из текущего ВВП страны
func get_missile_production_speed(country: String) -> float:
    var gdp = get_gdp(country)
    return gdp / MISSILE_SPEED_GDP_DIVISOR

## Есть ли у страны активный заказ ракет в производстве
func has_active_missile_order(country: String) -> bool:
    return active_missile_orders.has(country)

## Инфо по активному заказу: {"total", "remaining", "per_month", "per_day"} (пустой Dictionary если заказа нет)
func get_missile_order_info(country: String) -> Dictionary:
    return active_missile_orders.get(country, {})

## Оформить заказ на amount ракет. Списывает всю стоимость сразу.
## Возвращает false, если нельзя оформить (уже есть заказ / не хватает денег / amount некорректен).
func start_missile_order(country: String, amount: int) -> bool:
    if amount <= 0:
        return false
    if has_active_missile_order(country):
        return false
    if not countries_data.has(country):
        return false

    var missile_cost: float = settings.missile_cost
    var cost: float = missile_cost * amount
    if country == settings.active_country:
        cost *= settings.get_cost_multiplier()

    if countries_data[country].get("products", 0.0) < cost:
        return false

    var speed_month = get_missile_production_speed(country)
    if speed_month <= 0.0:
        return false  # нет производственных мощностей — заказ невозможен

    countries_data[country]["products"] -= cost

    active_missile_orders[country] = {
        "total": amount,
        "remaining": float(amount),
        "per_month": speed_month,
        "per_day": speed_month / MISSILE_DAYS_PER_MONTH,
    }

    #print("[Registry] %s заказал %d ракет (скорость %.3f/месяц)" % [country, amount, speed_month])
    missile_order_changed.emit(country)
    return true

## Раз в игровой день: продвигаем все активные заказы ракет,
## постепенно добавляя произведённые ракеты в country_data["missile"].
## Скорость задана "в месяц", но проверяется/начисляется каждый день дробными порциями,
## поэтому при скорости, например, 0.8 ракет/месяц, к началу второго месяца уже накопится ракета,
## а не только в конце месяца при month_passed.
func _process_missile_orders() -> void:
    if active_missile_orders.is_empty():
        return

    var finished: Array[String] = []

    for country in active_missile_orders:
        var order: Dictionary = active_missile_orders[country]
        var per_day: float = order["per_day"]
        var deliver: float = min(per_day, order["remaining"])

        if deliver > 0.0 and countries_data.has(country):
            countries_data[country]["missile"] = countries_data[country].get("missile", 0.0) + deliver
            order["remaining"] -= deliver

        if order["remaining"] <= 0.0001:
            finished.append(country)

        missile_order_changed.emit(country)

    for country in finished:
        active_missile_orders.erase(country)
        #print("[Registry] Заказ ракет страны %s завершён" % country)
        missile_order_changed.emit(country)

# Вызывать при постройке завода (в start_factory_construction):
# ─── ЭКОНОМИКА ──────────────────────────────────────────────────────────────

## Стоимость постройки фабрики с учётом идеологии страны (тот же множитель "eco",
## что использует ИИ в AIEconomy.process_economy). Единая точка расчёта —
## используется и для ИИ (через AIEconomy), и для игрока (через ProvinceMenu).
func get_factory_cost(country: String) -> float:
    var c_data   = countries_data.get(country, {})
    var ideology = c_data.get("ideology", "liberalism")
    var eco_mult = DiplomacyManager.IDEOLOGIES.get(ideology, DiplomacyManager.IDEOLOGIES["liberalism"])["eco"]
    var cost = settings.factory_cost * eco_mult
    # Модификатор сложности применяется только к игроку — ИИ строит по обычным ценам.
    if country == settings.active_country:
        cost *= settings.get_cost_multiplier()
    return cost

func start_factory_construction(p_id: int, country: String) -> bool:
    var p = province_data[p_id]
    if p.get("factory_queue", []).size() >= 5:
        return false
    var cost = get_factory_cost(country)
    if countries_data[country].get("balance", 0.0) < cost:
        return false
        
    if not p.has("factory_queue"):
        p["factory_queue"] = []
        
    countries_data[country]["balance"] -= cost
    p["factory_queue"].append(0)
    
    active_constructions[p_id] = true # <-- ДОБАВЛЕНО: запоминаем, где идет стройка
    return true

# ─── УКРЕПЛЕНИЕ (FORTIFICATION) ─────────────────────────────────────────────

## Стоимость постройки укрепления. Берётся напрямую из settings, без модификатора
## идеологии (в отличие от get_factory_cost) — при необходимости можно добавить
## тот же eco_mult, что и для заводов.
func get_fortification_cost(country: String) -> float:
    var cost: float = settings.FORTIFICATION_COST
    if country == settings.active_country:
        cost *= settings.get_cost_multiplier()
    return cost

## Начинает строительство укрепления в провинции. Правила:
##  - в провинции может быть только одно укрепление (уже построенное или строящееся);
##  - строить можно только за деньги владельца провинции (settings.FORTIFICATION_COST);
##  - строится settings.TIME_FORTIFICATION игровых дней (см. _process_economy).
## Возвращает false, если укрепление уже есть/строится, или не хватает денег.
func start_fortification_construction(p_id: int, country: String) -> bool:
    if not province_data.has(p_id):
        return false

    var p = province_data[p_id]

    if p.get("fortification", false):
        return false
    if active_fortification_constructions.has(p_id):
        return false

    var cost = get_fortification_cost(country)
    if countries_data[country].get("balance", 0.0) < cost:
        return false

    countries_data[country]["balance"] -= cost
    p["fortification_progress"] = 0

    active_fortification_constructions[p_id] = true
    return true


# ДРОНЫ / РАКЕТЫ
## attacker_country — страна, чей БПЛА нанёс удар. Если указана и является реальной страной,
## ей начисляется продукт за каждую уничтоженную фабрику: destroyed * product_cost * 12.
func destroy_factory(p_id: int, amount: int = 1, attacker_country: String = "") -> void:
    if not province_data.has(p_id): 
        return
        
    var p = province_data[p_id]
    var owner = p.get("owner", "")
    var current_factories = p.get("factories", 0)
    var current_population = p.get("population", 0)
    
    # ФАБРИКИ
    if current_factories > 0:
        # Уничтожаем не больше фабрик, чем там есть
        var destroyed = min(current_factories, amount)
        p["factories"] -= destroyed
        
        if _is_real_country_owner(owner):
            if countries_data.has(owner):
                countries_data[owner]["factories"] = max(0, countries_data[owner].get("factories", 0) - destroyed)
                
        #print("[Registry] Фабрик уничтожено: ", destroyed, " в провинции ", p_id)
        factory_destroyed.emit(p_id, owner, destroyed)

        # НАГРАДА АТАКУЮЩЕМУ: за каждую уничтоженную фабрику — product_cost * 12 продукта
        if _is_real_country_owner(attacker_country) and countries_data.has(attacker_country):
            var product_cost: float = settings.product_cost
            var reward: float = destroyed * 12.0
            countries_data[attacker_country]["products"] = countries_data[attacker_country].get("products", 0.0) + reward
            #print("[Registry] %s получил %.2f продукта за уничтожение %d фабрик" % [attacker_country, reward, destroyed])
        
    # НАСЕЛЕНИЕ
    var kill_pop = settings.KILLS_PER_DRONE * amount
    if current_population >= kill_pop:
        p["population"] -= kill_pop
        if countries_data.has(owner):
                countries_data[owner]["population"] -= kill_pop
                
    uav_strike_landed.emit(p_id)
    
func missile_strike(province_id: int, attacker_country: String = "") -> void:
    if not province_data.has(province_id):
        return

    var p = province_data[province_id]
    var owner = p.get("owner", "")

    # ЗВУК ВЗРЫВА — играет при любом ракетном ударе, независимо от наличия заводов
    Global.play("res://audio/sfx/explosion.ogg", "SFX")

    # УКРЕПЛЕНИЕ — если в провинции построено укрепление, ракета уничтожает ЕГО
    # и на этом гасится: фабрики в этот раз не трогаем. Без укрепления ракета
    # бьёт по фабрикам как обычно (см. ниже).
    if p.get("fortification", false):
        p["fortification"] = false
        fortification_destroyed.emit(province_id)

        # Дивизии всё равно несут потери от удара, невзирая на укрепление.
        DivisionManager.kill_percent_in_province(province_id, MISSILE_KILL_RATIO)
        missile_strike_landed.emit(province_id)
        return

    # ФАБРИКИ — снос ВСЕХ фабрик в провинции
    var current_factories = int(p.get("factories", 0))
    if current_factories > 0:
        p["factories"] = 0
        if _is_real_country_owner(owner):
            if countries_data.has(owner):
                countries_data[owner]["factories"] = max(0, countries_data[owner].get("factories", 0) - current_factories)
                
        #print("[Registry] Ракетный удар: уничтожено фабрик ", current_factories, " в провинции ", province_id)
        factory_destroyed.emit(province_id, owner, current_factories)

        # НАГРАДА АТАКУЮЩЕМУ: за каждую уничтоженную фабрику — 36 продукта
        if _is_real_country_owner(attacker_country) and countries_data.has(attacker_country):
            var reward: float = current_factories * 36.0
            countries_data[attacker_country]["products"] = countries_data[attacker_country].get("products", 0.0) + reward
            #print("[Registry] %s получил %.2f продукта за уничтожение %d фабрик (ракета)" % [attacker_country, reward, current_factories])

    # ДИВИЗИИ — уничтожение 90% личного состава в провинции
    DivisionManager.kill_percent_in_province(province_id, MISSILE_KILL_RATIO)
    
    missile_strike_landed.emit(province_id)
    
    #print("[Registry] Ракетный удар по провинции ", province_id, " завершён")
    
    
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# Универсальная функция для разделения разрядов
func _format_number(value: Variant, separator: String = " ") -> String:
    var n = int(value) # Принудительно приводим к int (защита от float)
    var s = str(abs(n))
    var res = ""
    var i = s.length()
    
    while i > 3:
        i -= 3
        res = separator + s.substr(i, 3) + res
    res = s.substr(0, i) + res
    
    if n < 0:
        res = "-" + res
    return res

# СМЕНИТЬ ЦВЕТ СТРАНЫ
func change_country_color(country: String, new_color: Color) -> void:
    if not countries_data.has(country):
        return
        
    # 1. Получаем индекс страны
    var idx = country_index.get(country, 0)
    
    # 2. Обновляем массив для шейдера
    country_colors[idx] = new_color
    
    # 3. Обновляем словарь для будущих сохранений игры
    countries_data[country]["color"] = [
        int(new_color.r * 255), 
        int(new_color.g * 255), 
        int(new_color.b * 255), 
        255
    ]
    
    # 4. Сообщаем карте, что нужно обновить шейдер
    country_color_changed.emit()



## RESET
func reset() -> void:
    active_missile_orders = {}
    active_uav_orders = {}
    active_constructions = {}
    active_fortification_constructions = {}
    _production_by_country = {}
    owner_province_count = {}
    _lost_provinces_notified = {}
    war_relations = {}
    province_occupants = {}
    province_owners = {}
    province_data = {}
    countries_data = {}
    days_in_power = 0

    _load_countries()
    _load_province_data()
    _load_province_adjacency()
    _recalculate_all_populations()
    _recalculate_all_happiness()
    _recalculate_all_factories()
