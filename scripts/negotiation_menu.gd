extends Control

var settings = preload("res://new_resource.tres")

@onready var Map = get_node("/root/Game/Map")

# ─── ССЫЛКИ НА ОБЫЧНЫЕ LABEL ─────────────────────────────────────────────────
@onready var player_flag_rect: TextureRect = $VBoxContainer/PlayerFlag
@onready var player_title_label: Label = $VBoxContainer/PlayerProvincePanel/PlayerTitleLabel
@onready var player_count_label: Label = $VBoxContainer/PlayerProvincePanel/PlayerCountLabel

@onready var enemy_flag_rect: TextureRect = $VBoxContainer/EnemyFlag
@onready var enemy_title_label: Label = $VBoxContainer/EnemyProvincePanel/EnemyTitleLabel
@onready var enemy_count_label: Label = $VBoxContainer/EnemyProvincePanel/EnemyCountLabel
# ─────────────────────────────────────────────────────────────────────────────

var menu_to_close: Array = ["FlagRect", "BalanceMenu", "CountryMenu", "ProvinceMenu", "DivisionMenu", "Date"]

var _enemy: String = ""
var _claimed: Array[int] = []
var _occupied_snapshot: Dictionary = {}


func open_negotiation(enemy: String) -> void:
    _enemy = enemy
    _claimed.clear()
    _occupied_snapshot.clear()

    # owner = active_country (мы захватили), occupied_by = enemy (полосы его цвета)
    for key in ProvinceRegistry.province_data:
        var p = ProvinceRegistry.province_data[key]
        if p.get("owner", "") == settings.active_country and p.get("against_occupation", "") == enemy:
            _occupied_snapshot[int(key)] = enemy

    print("[Negotiation] Оккупированных провинций врага: ", _occupied_snapshot.size())

    settings.negotiation_mode = true
    Map.enter_negotiation_mode(enemy)
    GameClock.paused = true
    DivisionManager.set_negotiation_visibility([settings.active_country, enemy])

    for menu in menu_to_close:
        get_node("/root/Game/CanvasLayer/" + menu).hide()
        
    # НОВОЕ: Обновляем флаги и базовые цифры при открытии
    _update_country_info()
    show()


func on_province_clicked(p_id: int) -> void:
    if not _occupied_snapshot.has(p_id):
        return

    if p_id in _claimed:
        # Передумали — возвращаем полосы
        _claimed.erase(p_id)
        var original_owner = _occupied_snapshot[p_id]
        ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = original_owner
        ProvinceRegistry.province_occupants[p_id] = original_owner
        ProvinceRegistry.province_occupied.emit(p_id, original_owner)
        print("[Negotiation] Провинция %d возвращена в оккупацию" % p_id)
    else:
        # Забираем — убираем полосы визуально
        _claimed.append(p_id)
        ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
        ProvinceRegistry.province_occupants.erase(p_id)
        ProvinceRegistry.province_occupied.emit(p_id, "")
        print("[Negotiation] Провинция %d добавлена в требования" % p_id)
        
    # НОВОЕ: Пересчитываем провинции при клике на карте
    _update_country_info()


func _on_select_all_pressed() -> void:
    for p_id in _occupied_snapshot:
        if not p_id in _claimed:
            _claimed.append(p_id)
            ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
            ProvinceRegistry.province_occupants.erase(p_id)
            ProvinceRegistry.province_occupied.emit(p_id, "")
    print("[Negotiation] Все оккупированные провинции выбраны: ", _claimed.size())
    
    # НОВОЕ: Пересчитываем провинции при выборе «Выбрать всё»
    _update_country_info()


func _on_send_demands_pressed() -> void:
    # Claimed — данные уже чистые, просто убеждаемся
    for p_id in _claimed:
        ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
        ProvinceRegistry.province_occupants.erase(p_id)

    # Остальные оккупированные — возвращаем врагу
    for p_id in _occupied_snapshot:
        if not p_id in _claimed:
            var original_owner = _occupied_snapshot[p_id]
            ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
            ProvinceRegistry.province_occupants.erase(p_id)
            ProvinceRegistry.capture_province(p_id, original_owner)
            ProvinceRegistry.province_occupied.emit(p_id, "")
            print("[Negotiation] Провинция %d возвращена %s" % [p_id, original_owner])

    ProvinceRegistry.end_war(settings.active_country, _enemy)
    _close()


func _on_close_button_pressed() -> void:
    # Откатываем визуальные изменения — возвращаем полосы на claimed провинции
    for p_id in _claimed:
        var original_owner = _occupied_snapshot[p_id]
        ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = original_owner
        ProvinceRegistry.province_occupants[p_id] = original_owner
        ProvinceRegistry.province_occupied.emit(p_id, original_owner)

    _close()


func _close() -> void:
    _claimed.clear()
    _occupied_snapshot.clear()
    _enemy = ""

    settings.negotiation_mode = false
    Map.exit_negotiation_mode()
    GameClock.toggle_pause()
    DivisionManager.set_negotiation_visibility([])

    for menu in menu_to_close:
        get_node("/root/Game/CanvasLayer/" + menu).show()
    hide()


# ─── МЕТОД ОБНОВЛЕНИЯ ИНТЕРФЕЙСА ───────────────────────────────────────
func _update_country_info() -> void:
    var my_country = settings.active_country
    
    player_flag_rect.texture = load("res://assets/flags/" + my_country + ".png")
    enemy_flag_rect.texture = load("res://assets/flags/" + _enemy + ".png")
    
    var unreturned_count = _occupied_snapshot.size() - _claimed.size()
    var my_count = ProvinceRegistry.owner_province_count.get(my_country, 0) - unreturned_count
    var enemy_count = ProvinceRegistry.owner_province_count.get(_enemy, 0) + unreturned_count
    
    player_title_label.text = "Prov."
    enemy_title_label.text = "Prov."
    
    # Просто передаем числа. Цвета и размеры уже настроены в самом Godot!
    player_count_label.text = str(my_count)
    enemy_count_label.text = str(enemy_count)
    
