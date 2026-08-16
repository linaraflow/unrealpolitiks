extends Node
# =============================================================================
# SaveManager.gd — autoload
#
# Подключение: Project Settings → Autoload → добавить этот файл как "SaveManager".
# Должен идти ПОСЛЕ ProvinceRegistry, DivisionManager, GameClock, CombatManager,
# DiplomacyManager, AIManager в списке автозагрузок (порядок в Autoload не важен
# для вызова функций, но пусть будет последним для ясности).
#
# Использование:
#   SaveManager.save_game("slot1")
#   SaveManager.load_game("slot1")           # вызывать со сцены game.tscn,
#                                             # ПОСЛЕ того как Map._ready() отработал
#   SaveManager.has_save("slot1") -> bool
#   SaveManager.list_saves() -> Array[String]
#   SaveManager.delete_save("slot1")
#
# Для кнопки "Продолжить" / "Загрузить" в MainMenu удобно всегда использовать
# один и тот же слот "autosave" или явный список слотов (list_saves()).
# =============================================================================

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 1
## Суффикс лёгкого файла метаданных, который лежит рядом с полным сохранением
## и содержит только то, что нужно для отрисовки карточки в SaveMenu (страна,
## дата, дни у власти, ВВП) — без чтения/парсинга всего сейва (может быть
## мегабайты JSON). Пишется в save_game() и читается в get_save_info().
const META_SUFFIX := ".meta.json"

signal save_completed(slot: String)
signal load_completed(slot: String)
signal load_failed(slot: String, reason: String)
signal autosave_completed(slot: String)

var TopMenu: Control
var balance_label: Label
var SelectionBox: Control
var NotificationMenu: Control

var settings = preload("res://new_resource.tres")

## Слот, в который игра сохранялась/из которого загружалась последний раз
## в текущей сессии. "" значит, что за эту сессию игра ещё никуда не
## сохранялась и не загружалась — тогда автосейв ищет свободный слот сам.
var current_slot: String = ""

## Счётчик дней с последнего автосохранения (сбрасывается при срабатывании).
var _autosave_days_accum: int = 0

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)
    GameClock.on_day_passed.connect(_on_autosave_day_passed)

## Дёргается каждый раз, когда в игре проходит очередной день.
func _on_autosave_day_passed(_date = null) -> void:
    var interval: int = SettingsManager.autosave_interval_days
    if interval <= 0:
        _autosave_days_accum = 0
        return

    _autosave_days_accum += 1
    if _autosave_days_accum < interval:
        return

    _autosave_days_accum = 0
    autosave()

## Автосохранение:
## — если игра уже сохранялась/загружалась в этой сессии (current_slot не пуст) —
##   пишем в тот же слот;
## — если нет — "пустого слота" как такового не существует (см. save_menu.gd:
##   там это просто карточка с ключом "", а реальное имя генерируется в момент
##   сохранения) — генерируем новое имя по той же схеме, что и SaveMenu.
func autosave() -> void:
    if settings.is_saving_disabled():
        return

    var slot: String = current_slot
    if slot == "":
        slot = _generate_new_slot_name()

    if save_game(slot):
        autosave_completed.emit(slot)
        print("[SaveManager] Автосохранение выполнено в слот '%s'" % slot)

## "<active_country>_<чч>_<мм>_<сс>" — та же схема, что в save_menu.gd
## (_generate_new_slot_name), продублирована здесь, т.к. SaveMenu создаётся
## только по требованию и на момент автосейва её может не быть в дереве.
## На случай коллизии (сохранение в ту же секунду) добавляем суффикс.
func _generate_new_slot_name() -> String:
    var country: String = settings.active_country
    if country == "":
        country = "Unknown"
    var t := Time.get_time_dict_from_system()
    var base_name := "%s_%02d_%02d_%02d" % [country, t["hour"], t["minute"], t["second"]]

    var slot := base_name
    var suffix := 2
    while has_save(slot):
        slot = "%s_%d" % [base_name, suffix]
        suffix += 1
    return slot

## Вызывай при старте НОВОЙ игры (не загрузки), чтобы автосейв не продолжил
## писать в слот, из которого/в который был последний save/load предыдущей
## партии — иначе после "Новая игра" автосохранение молча перезапишет чужой слот.
func reset_session() -> void:
    current_slot = ""
    _autosave_days_accum = 0

func _slot_path(slot: String) -> String:
    return SAVE_DIR + slot + ".json"

func _meta_path(slot: String) -> String:
    return SAVE_DIR + slot + META_SUFFIX

func has_save(slot: String) -> bool:
    return FileAccess.file_exists(_slot_path(slot))

func list_saves() -> Array:
    var result: Array = []
    var dir = DirAccess.open(SAVE_DIR)
    if dir == null:
        return result
    dir.list_dir_begin()
    var f = dir.get_next()
    while f != "":
        # Мета-файлы (*.meta.json) тоже заканчиваются на ".json" — исключаем
        # их явно, иначе они попадут в список как "сохранения"-призраки.
        if f.ends_with(".json") and not f.ends_with(META_SUFFIX):
            result.append(f.get_basename())
        f = dir.get_next()
    dir.list_dir_end()
    return result

func delete_save(slot: String) -> void:
    var path = _slot_path(slot)
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
    var meta_path = _meta_path(slot)
    if FileAccess.file_exists(meta_path):
        DirAccess.remove_absolute(meta_path)

## Лёгкое чтение метаданных сохранения для UI (SaveMenu) без полной загрузки игры.
## Возвращает {} если файл битый/отсутствует.
##
## Быстрый путь: читает маленький "slot.meta.json" (пишется в save_game()) —
## это единственное, что нужно открывать при отрисовке SaveMenu, даже если
## сохранений 50+.
## Медленный путь (только для старых сейвов без meta-файла, сделанных до
## появления этого механизма): парсит весь "slot.json" целиком, как раньше,
## и затем ДОПИСЫВАЕТ meta-файл рядом, чтобы при следующем открытии SaveMenu
## этот слот тоже пошёл по быстрому пути.
func get_save_info(slot: String) -> Dictionary:
    var meta_path = _meta_path(slot)
    if FileAccess.file_exists(meta_path):
        var meta_file := FileAccess.open(meta_path, FileAccess.READ)
        if meta_file != null:
            var meta_text := meta_file.get_as_text()
            meta_file.close()
            var meta_parsed = JSON.parse_string(meta_text)
            if meta_parsed != null and typeof(meta_parsed) == TYPE_DICTIONARY:
                return meta_parsed

    # Мета-файла нет (старый сейв) — читаем и парсим полный файл сохранения один раз.
    var info := _read_info_from_full_save(slot)
    if not info.is_empty():
        _write_meta(slot, info)  # миграция: в следующий раз пойдём быстрым путём
    return info

func _read_info_from_full_save(slot: String) -> Dictionary:
    var path = _slot_path(slot)
    if not FileAccess.file_exists(path):
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var text := file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(text)
    if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
        return {}

    var data: Dictionary = parsed
    var settings_d: Dictionary = data.get("settings", {})
    var pr_d: Dictionary = data.get("province_registry", {})

    var country: String = settings_d.get("active_country", "")
    var countries_data: Dictionary = pr_d.get("countries_data", {})
    var country_info: Dictionary = countries_data.get(country, {})

    return {
        "slot": slot,
        "country": country,
        "days_in_power": int(pr_d.get("days_in_power", 0)),
        # Та же формула, что и в ProvinceRegistry.get_gdp(), но по данным из файла
        # сохранения — сам ProvinceRegistry на момент открытия SaveMenu ещё не
        # содержит эти данные (игра не загружена).
        "gdp": _calc_gdp(country_info),
        "saved_at_unix": int(data.get("saved_at_unix", 0)),
    }

## Пишет лёгкий файл метаданных рядом с полным сохранением.
func _write_meta(slot: String, info: Dictionary) -> void:
    var meta_file := FileAccess.open(_meta_path(slot), FileAccess.WRITE)
    if meta_file == null:
        push_warning("[SaveManager] Не удалось записать meta-файл для слота '%s'" % slot)
        return
    meta_file.store_string(JSON.stringify(info))
    meta_file.close()

## Приблизительный годовой ВВП страны по сохранённым данным —
## дублирует формулу ProvinceRegistry.get_gdp(): (заводы × стоимость продукта + месячный доход) × 12
func _calc_gdp(country_info: Dictionary) -> float:
    var factories := float(country_info.get("factories", 0))
    var product_cost: float = settings.product_cost
    var monthly_income := float(country_info.get("monthly_income", 0))
    return (factories * product_cost + monthly_income) * 12.0

# ─────────────────────────────────────────────────────────────────────────────
# SAVE
# ─────────────────────────────────────────────────────────────────────────────

func save_game(slot: String) -> bool:
    if settings.is_saving_disabled():
        push_warning("[SaveManager] Сохранение недоступно на сложности Hardcore")
        return false

    var data := {
        "version": SAVE_VERSION,
        "saved_at_unix": Time.get_unix_time_from_system(),

        "clock": _save_clock(),
        "settings": _save_settings(),
        "province_registry": _save_province_registry(),
        "divisions": _save_divisions(),
        "diplomacy": _save_diplomacy(),
        "ai": _save_ai(),
        "projectiles": _save_projectiles(),
        "statistics": _save_statistics(),
    }

    var json_string := JSON.stringify(data)
    var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
    if file == null:
        push_error("[SaveManager] Не удалось открыть файл для записи: " + _slot_path(slot))
        return false

    file.store_string(json_string)
    file.close()

    # Сразу же пишем лёгкие метаданные рядом — SaveMenu потом читает только
    # их и не трогает полный (потенциально огромный) json сохранения.
    var pr_d: Dictionary = data["province_registry"]
    var country: String = data["settings"].get("active_country", "")
    var country_info: Dictionary = (pr_d.get("countries_data", {}) as Dictionary).get(country, {})
    _write_meta(slot, {
        "slot": slot,
        "country": country,
        "days_in_power": int(pr_d.get("days_in_power", 0)),
        "gdp": _calc_gdp(country_info),
        "saved_at_unix": int(data["saved_at_unix"]),
    })

    current_slot = slot
    print("[SaveManager] Игра сохранена в слот '%s'" % slot)
    save_completed.emit(slot)
    return true

func _save_clock() -> Dictionary:
    return {
        "day": GameClock.day,
        "month": GameClock.month,
        "year": GameClock.year,
        "speed_index": GameClock.speed_index,
        "paused": GameClock.paused,
    }

func _save_settings() -> Dictionary:
    var s = settings  # тот же Resource, что и у остальных синглтонов
    return {
        "active_country": s.active_country,
        "last_clicked_province_id": s.last_clicked_province_id,
        "difficulty": s.difficulty
    }

func _save_province_registry() -> Dictionary:
    var pr = ProvinceRegistry
    return {
        "province_data": pr.province_data,                 # Dictionary[int, Dictionary] -> JSON приведёт ключи к строкам, это нормально
        "province_owners": pr.province_owners,
        "province_occupants": pr.province_occupants,
        "country_index": pr.country_index,
        "owner_province_count": pr.owner_province_count,
        "war_relations": pr.war_relations,
        "countries_data": pr.countries_data,
        "active_uav_orders": pr.active_uav_orders,
        "active_missile_orders": pr.active_missile_orders,
        "active_constructions": pr.active_constructions,
        "active_fortification_constructions": pr.active_fortification_constructions,
        "days_in_power": pr.days_in_power,
        "fog_of_war_enabled": pr.fog_of_war_enabled,
    }

func _save_divisions() -> Dictionary:
    var out := {
        "armies": [],          # плоский список — проще восстанавливать
        "army_counters": DivisionManager.army_counters,
    }

    for p_id in DivisionManager.armies:
        for circle in DivisionManager.armies[p_id]:
            if not is_instance_valid(circle):
                continue
            out["armies"].append({
                "province_id": circle.province_id,
                "army_name": circle.army_name,
                "soldiers": circle.soldiers,
                "division_owner": circle.division_owner,
                "position": [circle.position.x, circle.position.y],
                "is_moving": circle.is_moving,
                "current_target_province_id": circle.current_target_province_id,
                "target_destination_pos": [circle.target_destination_pos.x, circle.target_destination_pos.y],
            })

    return out

## Летящие БПЛА и ракеты — Sprite2D-ноды, добавленные как прямые дети Map
## (см. map.gd:_clear_in_flight_projectiles, там их находят по script.resource_path).
func _save_projectiles() -> Dictionary:
    var out := {
        "uavs": [],
        "missiles": [],
    }

    var current_scene := get_tree().current_scene
    if current_scene == null:
        return out
    var map_node := current_scene.get_node_or_null("Map")
    if map_node == null:
        return out

    for child in map_node.get_children():
        if not (child is Sprite2D) or not child.get_script():
            continue
        var path: String = child.get_script().resource_path

        if path == "res://scripts/uav_drone.gd":
            out["uavs"].append({
                "position": [child.position.x, child.position.y],
                "target_pos": [child.target_pos.x, child.target_pos.y],
                "target_p_id": child.target_p_id,
                "amount": child.amount,
                "attacker_country": child.attacker_country,
            })

        elif path == "res://scripts/missile.gd":
            out["missiles"].append({
                "start_pos": [child.start_pos.x, child.start_pos.y],
                "control_pos": [child.control_pos.x, child.control_pos.y],
                "target_pos": [child.target_pos.x, child.target_pos.y],
                "target_p_id": child.target_p_id,
                "attacker_country": child.attacker_country,
                "t": child._t,
            })

    return out

func _save_diplomacy() -> Dictionary:
    return {
        "active_processes": DiplomacyManager.active_processes,
    }

func _save_ai() -> Dictionary:
    return {
        "factory_cooldowns": AIManager.factory_cooldowns,
        "recruitment_cooldowns": AIManager.recruitment_cooldowns,
        "uav_launch_cooldowns": AIManager.uav_launch_cooldowns,
        "missile_launch_cooldowns": AIManager.missile_launch_cooldowns,
        "player_ai_army_enabled": AIManager.player_ai_army_enabled,
        "ai_aggression": AIManager.ai_aggression,
    }

## Панель "Внутренняя статистика страны" (statistics_menu.gd) сама не автолоад,
## а обычная нода сцены — копим её weekly_stats/war_stats так же, как остальные
## данные, через прямой путь в дереве (как это делает и сам map.gd:restart()).
func _save_statistics() -> Dictionary:
    var stats_menu = get_node_or_null("/root/Game/CanvasLayer/StatisticsMenu")
    if stats_menu == null:
        return {}
    return {
        "weekly_stats": stats_menu.weekly_stats,
        "war_stats": stats_menu.war_stats,
    }

# ─────────────────────────────────────────────────────────────────────────────
# LOAD
# ─────────────────────────────────────────────────────────────────────────────

## ВАЖНО: вызывать после того, как сцена game.tscn (и Map._ready()) уже
## полностью отработали — т.е. после смены сцены на game.tscn и одного
## await get_tree().process_frame (см. пример в MainMenu.gd ниже).
## Вызывать из MainMenu вместо ручной смены сцены + await + load_game().
## Работает надёжно, потому что SaveManager — autoload и не удаляется
## при смене сцены (в отличие от MainMenu, который change_scene_to_file()
## уничтожает сразу же, обрывая любой await, написанный в его методах).
func request_load(slot: String) -> void:
    if not has_save(slot):
        print("[SaveManager] Сохранение '%s' не найдено" % slot)
        load_failed.emit(slot, "no_such_save")
        return

    get_tree().change_scene_to_file("res://game.tscn")

    await get_tree().process_frame
    await get_tree().process_frame  # даём Map._ready() отработать (там есть await внутри)

    var current_scene := get_tree().current_scene
    if current_scene == null:
        push_error("[SaveManager] current_scene == null после смены сцены")
        load_failed.emit(slot, "no_current_scene")
        return

    var map_node := current_scene.get_node_or_null("Map")
    if map_node == null:
        push_error("[SaveManager] Не найден узел Map под корнем '%s'." % current_scene.name)
        load_failed.emit(slot, "no_map_node")
        return

    var ok := load_game(slot)
    if not ok:
        push_error("[SaveManager] load_game('%s') вернул false" % slot)

func load_game(slot: String) -> bool:
    var path = _slot_path(slot)
    if not FileAccess.file_exists(path):
        load_failed.emit(slot, "no_such_save")
        return false

    var file := FileAccess.open(path, FileAccess.READ)
    var text := file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(text)
    if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
        push_error("[SaveManager] Файл сохранения '%s' повреждён или пуст (длина текста: %d)" % [path, text.length()])
        load_failed.emit(slot, "corrupted")
        return false

    var data: Dictionary = parsed
    
    # ==== DISCORD ====
    DiscordRPC.state = tr("TAKING_OVER_THE_WORLD")
    DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system())
    DiscordRPC.refresh()  # обязательно вызывать после каждого изменения полей

    # Полный сброс текущего состояния (как при рестарте), затем накатываем сохранение
    # ВАЖНО: раньше здесь был жёсткий путь "/root/Game/Map", который ломался,
    # если корневой узел game.tscn называется не буквально "Game" — тогда
    # map_node оказывался null, функция тихо выходила, а игрок оставался
    # смотреть на только что созданную (дефолтную) сцену game.tscn, что и
    # выглядело как "новая игра" вместо загрузки сохранения.
    var current_scene := get_tree().current_scene
    if current_scene == null:
        load_failed.emit(slot, "no_current_scene")
        return false

    var map_node = current_scene.get_node_or_null("Map")
    if map_node == null:
        push_error("[SaveManager] Не найден узел 'Map' под корнем '%s' (проверь структуру game.tscn)" % current_scene.name)
        load_failed.emit(slot, "no_map_node")
        return false

    map_node._clear_in_flight_projectiles()
    map_node._close_all_menus()

    ProvinceRegistry.reset()
    DivisionManager.reset()
    GameClock.reset()
    CombatManager.reset()
    DiplomacyManager.reset()
    AIManager.reset()

    _load_clock(data.get("clock", {}))
    _load_settings(data.get("settings", {}))
    _load_province_registry(data.get("province_registry", {}))

    # _load_province_registry() пишет province_owners/province_data напрямую
    # в словари, минуя capture_province() — а именно там обычно вызывается
    # PathCache.invalidate_cache() при смене владельца провинции. Без этого
    # PathCache остаётся со старым кэшем путей (посчитанным ДО загрузки, для
    # владельцев "по умолчанию") и не знает о территориях, захваченных за
    # время партии и записанных в сейв — из-за этого после загрузки дивизии
    # на таких территориях не могли пройти дальше соседней провинции.
    PathCache.invalidate_cache()

    _load_diplomacy(data.get("diplomacy", {}))
    _load_ai(data.get("ai", {}))
    _load_statistics(data.get("statistics", {}))
    
    TopMenu.show()
    TopMenu.update(settings.active_country)
    balance_label.balance_update()
    SelectionBox.show()
    NotificationMenu.show()

    # Перерисовываем карту по загруженным данным (аналог restart())
    map_node._reset_map_textures()
    map_node._paint_all_provinces_from_data()
    map_node.country_labels_layer.rebuild()
    map_node._init_capital_borders()
    if map_node.has_method("_rebuild_all_fortification_icons"):
        map_node._rebuild_all_fortification_icons()

    _load_divisions(data.get("divisions", {}), map_node)
    _load_projectiles(data.get("projectiles", {}), map_node)

    # На всякий случай пересчитываем видимость всех дивизий разом — это
    # актуально, если фактическая видимость какой-то дивизии в момент её
    # создания в _load_divisions ещё не была корректна (например пока не все
    # провинции были готовы) или отличалась в старом сейве от текущего флага.
    DivisionManager.refresh_fog_of_war_visibility()

    # Пересобираем бои по факту вражеских войск в одной провинции
    _rebuild_battles()

    map_node.date._on_clock_day_passed({})
    map_node.date._update_speed_label(GameClock.speed_index)
    map_node.choose_map_panel.reset_to_default()

    var s = settings
    s.can_draw = true
    map_node.opening.hide()
    
    Global._on_music_finished()

    current_slot = slot
    _autosave_days_accum = 0  # отсчёт до автосейва начинаем заново от момента загрузки

    print("[SaveManager] Игра загружена из слота '%s'" % slot)
    load_completed.emit(slot)
    return true

func _load_clock(d: Dictionary) -> void:
    GameClock.day = int(d.get("day", 1))
    GameClock.month = int(d.get("month", 1))
    GameClock.year = int(d.get("year", 2012))
    GameClock.speed_index = int(d.get("speed_index", 1))
    GameClock.paused = true

func _load_settings(d: Dictionary) -> void:
    settings.active_country = d.get("active_country", "")
    settings.last_clicked_province_id = d.get("last_clicked_province_id", "")
    settings.difficulty = int(d.get("difficulty", GameSettings.Difficulty.STANDARD)) as GameSettings.Difficulty

## JSON превращает int-ключи Dictionary в строки — конвертируем обратно.
func _intkeys(d: Dictionary) -> Dictionary:
    var out := {}
    for k in d:
        if (k as String).is_valid_int():
            out[int(k)] = d[k]
        else:
            out[k] = d[k]
    return out

func _load_province_registry(d: Dictionary) -> void:
    var pr = ProvinceRegistry

    # ВАЖНО: pr.province_data НЕЛЬЗЯ переприсваивать новым Dictionary через "=".
    # При старте игры ProvinceRegistry._load_province_data() делает
    # "settings.province_data = province_data" — это ссылка на ТОТ ЖЕ объект
    # Dictionary, а не копия. Pathfinder.gd при построении маршрута дивизий
    # читает владельца провинции именно из settings.province_data, а не из
    # ProvinceRegistry.province_data. Если тут написать "pr.province_data =
    # _intkeys(...)", создаётся НОВЫЙ словарь, и ссылка settings.province_data
    # рвётся — Pathfinder продолжает видеть СТАРЫЕ (домашние) владения, из-за
    # чего маршрут через территории, захваченные за игру и восстановленные из
    # сейва, не строится (дивизия может шагнуть только на 1 соседнюю провинцию).
    # Поэтому чистим и заполняем существующий словарь на месте — так ссылка
    # settings.province_data остаётся указывать на актуальные данные.
    pr.province_data.clear()
    pr.province_data.merge(_intkeys(d.get("province_data", {})))

    pr.province_owners = _intkeys(d.get("province_owners", {}))
    pr.province_occupants = _intkeys(d.get("province_occupants", {}))
    pr.country_index = d.get("country_index", {})
    pr.owner_province_count = d.get("owner_province_count", {})
    pr.war_relations = d.get("war_relations", {})
    pr.countries_data = d.get("countries_data", {})
    pr.active_uav_orders = d.get("active_uav_orders", {})
    pr.active_missile_orders = d.get("active_missile_orders", {})
    pr.active_constructions = _intkeys(d.get("active_constructions", {}))
    pr.active_fortification_constructions = _intkeys(d.get("active_fortification_constructions", {}))
    pr.days_in_power = int(d.get("days_in_power", 0))
    # По умолчанию true, чтобы старые сейвы (сохранённые до появления тумана
    # войны) грузились с включённым туманом — так же, как выглядит новая игра.
    pr.fog_of_war_enabled = bool(d.get("fog_of_war_enabled", true))

func _load_diplomacy(d: Dictionary) -> void:
    DiplomacyManager.active_processes = d.get("active_processes", {})

func _load_ai(d: Dictionary) -> void:
    AIManager.factory_cooldowns = d.get("factory_cooldowns", {})
    AIManager.recruitment_cooldowns = d.get("recruitment_cooldowns", {})
    AIManager.uav_launch_cooldowns = d.get("uav_launch_cooldowns", {})
    AIManager.missile_launch_cooldowns = d.get("missile_launch_cooldowns", {})
    AIManager.player_ai_army_enabled = bool(d.get("player_ai_army_enabled", false))
    # Старые сейвы (сохранённые до появления слайдера агрессии) не содержат
    # это поле — по умолчанию считаем агрессию 100% (1.0), как и было раньше.
    AIManager.ai_aggression = clampf(float(d.get("ai_aggression", 1.0)), 0.0, 1.0)
    AIManager._build_initial_country_cache()  # пересобрать индекс "страна -> провинции" по новому province_data

    # ВАЖНО: AIManager.player_ai_army_enabled выше восстановлен верно, но
    # визуальный CheckBox в TopMenu (TopPanel/AIArmyContainer/CheckBox) сам
    # по себе не трогается никем — он остаётся в том состоянии, в котором его
    # оставил top_menu.gd._ready() (выполняется ДО load_game(), см. request_load()).
    # Без этой синхронизации галочка на экране не совпадает с реальным
    # значением, и первое же нажатие пользователем на чекбокс перезаписывает
    # только что загруженное состояние обратно.
    if TopMenu != null:
        TopMenu.set_ai_army_tick(AIManager.player_ai_army_enabled)

func _load_statistics(d: Dictionary) -> void:
    var stats_menu = get_node_or_null("/root/Game/CanvasLayer/StatisticsMenu")
    if stats_menu == null:
        return
    stats_menu.weekly_stats = d.get("weekly_stats", {})
    stats_menu.war_stats = d.get("war_stats", {})
    stats_menu._refresh()  # перерисовать панель (счётчик войн обновляется независимо от видимости)

const ArmyScene = preload("res://ArmyCircle.tscn")

func _load_divisions(d: Dictionary, map_node: Node) -> void:
    DivisionManager.army_counters = d.get("army_counters", {})

    for entry in d.get("armies", []):
        var p_id: int = int(entry.get("province_id", -1))
        if p_id == -1:
            continue

        var pos_arr = entry.get("position", [0.0, 0.0])
        var pos = Vector2(pos_arr[0], pos_arr[1])

        var army = ArmyScene.instantiate()
        map_node.add_child(army)
        army.position = pos
        army.soldiers = int(entry.get("soldiers", 0))
        army.division_owner = entry.get("division_owner", "")
        army.army_name = entry.get("army_name", "")
        army.province_id = p_id
        army._update_flag_texture()
        army.apply_fog_visibility()

        if not DivisionManager.armies.has(p_id):
            DivisionManager.armies[p_id] = []
        DivisionManager.armies[p_id].append(army)
        # ВАЖНО: армии тут создаются в обход DivisionManager.recruit(), поэтому
        # индекс armies_by_country (см. оптимизацию AIMilitary.process_military_movement)
        # нужно заполнять вручную — иначе после загрузки сейва ИИ "не видит"
        # армии, которые на момент сохранения стояли не на своей территории.
        DivisionManager._register_army(army.division_owner, p_id)

        # Если дивизия была в пути — пересчитываем маршрут от текущей позиции
        # до сохранённой цели (саму кривую не сериализуем, она строится заново).
        if bool(entry.get("is_moving", false)):
            var target_p_id: int = int(entry.get("current_target_province_id", -1))
            var target_pos_arr = entry.get("target_destination_pos", pos_arr)
            var target_pos = Vector2(target_pos_arr[0], target_pos_arr[1])
            if target_p_id != -1:
                army.start_movement_to(target_p_id, target_pos)

    for p_id in DivisionManager.armies:
        DivisionManager.reposition_armies_in_province(p_id)

const UavDroneScript = preload("res://scripts/uav_drone.gd")
const MissileScript = preload("res://scripts/missile.gd")
const MISSILE_TRAIL_RESTORE_SEGMENTS := 20

## Восстанавливает летящие БПЛА и ракеты как прямых детей Map — так же,
## как их создают uav_menu.gd/missile_menu.gd/AIManager (add_child(Sprite2D
## с назначенным script)). Свойства выставляем ДО add_child, потому что
## _ready() обоих скриптов сразу использует их (target_pos/start_pos и т.д.).
func _load_projectiles(d: Dictionary, map_node: Node) -> void:
    for entry in d.get("uavs", []):
        var pos_arr = entry.get("position", [0.0, 0.0])
        var target_arr = entry.get("target_pos", pos_arr)

        var drone := Sprite2D.new()
        drone.set_script(UavDroneScript)
        drone.position = Vector2(pos_arr[0], pos_arr[1])
        drone.target_pos = Vector2(target_arr[0], target_arr[1])
        drone.target_p_id = int(entry.get("target_p_id", -1))
        drone.amount = int(entry.get("amount", 1))
        drone.attacker_country = entry.get("attacker_country", "")

        map_node.add_child(drone)  # запускает _ready(): текстура, поворот к цели

    for entry in d.get("missiles", []):
        var start_arr = entry.get("start_pos", [0.0, 0.0])
        var control_arr = entry.get("control_pos", start_arr)
        var target_arr = entry.get("target_pos", start_arr)
        var t: float = float(entry.get("t", 0.0))

        var missile := Sprite2D.new()
        missile.set_script(MissileScript)
        missile.start_pos = Vector2(start_arr[0], start_arr[1])
        missile.control_pos = Vector2(control_arr[0], control_arr[1])
        missile.target_pos = Vector2(target_arr[0], target_arr[1])
        missile.target_p_id = int(entry.get("target_p_id", -1))
        missile.attacker_country = entry.get("attacker_country", "")

        # _ready() выставит position = start_pos и создаст след с одной точкой (start_pos) —
        # доводим ракету и след до сохранённого t вручную, т.к. сама кривая не сериализуется.
        map_node.add_child(missile)

        missile._t = t
        for i in range(1, MISSILE_TRAIL_RESTORE_SEGMENTS + 1):
            var tt: float = t * float(i) / float(MISSILE_TRAIL_RESTORE_SEGMENTS)
            missile._extend_trail(missile._point_on_curve(tt))
        missile.position = missile._point_on_curve(t)
        missile._update_rotation(t)

## Провинции, где после загрузки оказались войска враждующих стран —
## запускаем check_for_battle, чтобы CombatManager пересобрал active_battles.
func _rebuild_battles() -> void:
    for p_id in DivisionManager.armies.keys():
        var circles: Array = DivisionManager.armies[p_id]
        if circles.is_empty():
            continue
        CombatManager.check_for_battle(circles[0], p_id)
