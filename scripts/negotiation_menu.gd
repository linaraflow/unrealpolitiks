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

@onready var SelectAllButton: Button = $VBoxContainer/SelectAllButton
@onready var WarReparationsButton: Button = $VBoxContainer/WarReparationsButton
@onready var ChangeIdeologyButton: Button = $VBoxContainer/ChangeIdeologyButton
@onready var ControlButton: Button = $VBoxContainer/ControlButton

@onready var buttons = [$VBoxContainer/SelectAllButton, $VBoxContainer/WarReparationsButton, $VBoxContainer/ChangeIdeologyButton, $VBoxContainer/ControlButton]

var menu_to_close: Array = ["CountryMenu", "ProvinceMenu", "DivisionMenu", "TopMenu", "NotificationMenu"]

var _enemy: String = ""
var _claimed: Array[int] = []
var _occupied_snapshot: Dictionary = {}

@onready var ReparationsSlider: HSlider = $ReparationsSlider

# ─── ВОЕННЫЕ РЕПАРАЦИИ ──────────────────────────────────────────────────────
var _reparations_active: bool = false

# ─── СМЕНА ИДЕОЛОГИИ ────────────────────────────────────────────────────────
var _ideology_change_active: bool = false

# ─── НАЗНАЧЕНИЕ КОНТРОЛЁРРА ─────────────────────────────────────────────────
var _controller_set_active: bool = false

func _ready():
    for b in buttons:
        b.pivot_offset = b.size / 2
        b.button_down.connect(_on_press.bind(b))
        b.button_up.connect(_on_release.bind(b))

    # Позиция и размер слайдера настроены в редакторе сцены
    ReparationsSlider.step = 1
    ReparationsSlider.value_changed.connect(_on_reparations_slider_changed)
    ReparationsSlider.hide()

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

    SelectAllButton.icon = ICON_MAP
    _hide_reparations_slider()
    _ideology_change_active = false
    ChangeIdeologyButton.icon = ICON_FLAG

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
        
        SelectAllButton.icon = preload("res://assets/icons_negotiation_menu/map.svg")
        
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

func _on_send_demands_pressed() -> void:
    # 1. Обработка провинций, которые игрок захватил у врага (оставляем без изменений)
    for p_id in _claimed:
        ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
        ProvinceRegistry.province_occupants.erase(p_id)
        ProvinceRegistry.province_data[str(p_id)]["core_owner"] = settings.active_country

    for p_id in _occupied_snapshot:
        if not p_id in _claimed:
            var original_owner = _occupied_snapshot[p_id]
            ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
            ProvinceRegistry.province_occupants.erase(p_id)
            ProvinceRegistry.capture_province(p_id, original_owner)
            ProvinceRegistry.province_occupied.emit(p_id, "")

    # 2. Провинции, которые враг оккупировал у игрока, передаются врагу
    # ВАЖНО: against_occupation хранит ИСТИННОГО (core) владельца провинции,
    # а не оккупанта. Поэтому для провинций, отжатых врагом у игрока:
    #   owner              == _enemy (текущий контролёр)
    #   against_occupation == settings.active_country (истинный владелец, игрок)
    for key in ProvinceRegistry.province_data.keys():
        var p = ProvinceRegistry.province_data[key]
        if p.get("owner", "") == _enemy and p.get("against_occupation", "") == settings.active_country:
            var p_id = int(key)
            # Владелец уже = враг, просто узакониваем это (аннексия) и снимаем полосы
            ProvinceRegistry.province_data[key]["core_owner"] = _enemy
            ProvinceRegistry.province_data[key]["against_occupation"] = ""
            ProvinceRegistry.province_occupants.erase(p_id)
            ProvinceRegistry.province_occupied.emit(p_id, "")
            print("[Negotiation] Провинция %d передана врагу %s" % [p_id, _enemy])

    # 3. Военные репарации — переводим деньги игроку, у врага уходит в минус при нехватке
    if _reparations_active:
        var amount = int(ReparationsSlider.value)
        var my_country = settings.active_country

        if ProvinceRegistry.countries_data.has(my_country):
            ProvinceRegistry.countries_data[my_country]["balance"] = ProvinceRegistry.countries_data[my_country].get("balance", 0.0) + amount

        if ProvinceRegistry.countries_data.has(_enemy):
            ProvinceRegistry.countries_data[_enemy]["balance"] = ProvinceRegistry.countries_data[_enemy].get("balance", 0.0) - amount

        print("[Negotiation] Военные репарации: %d получено от %s (баланс врага может уйти в минус)" % [amount, _enemy])

    # 4. Смена идеологии врага на идеологию игрока (принудительно, без учёта стоимости)
    if _ideology_change_active:
        var my_country = settings.active_country
        if ProvinceRegistry.countries_data.has(my_country) and ProvinceRegistry.countries_data.has(_enemy):
            var my_ideology = ProvinceRegistry.countries_data[my_country].get("ideology", "")
            if my_ideology != "" and DiplomacyManager.IDEOLOGIES.has(my_ideology):
                ProvinceRegistry.countries_data[_enemy]["ideology"] = my_ideology
                print("[Negotiation] Идеология %s принудительно изменена на %s" % [_enemy, my_ideology])
                
    if _controller_set_active:
        _set_controller(settings.active_country, _enemy)

    # 5. Завершаем войну (отношения, флаги и т.д.)
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
    SelectAllButton.icon = ICON_MAP
    _hide_reparations_slider()
    _ideology_change_active = false
    ChangeIdeologyButton.icon = ICON_FLAG

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


func _on_press(button: Button):
    var tween = create_tween()
    tween.tween_property(button, "scale", Vector2(0.92, 0.92), 0.08)


func _on_release(button: Button):
    var tween = create_tween()
    tween.set_ease(Tween.EASE_OUT)
    tween.set_trans(Tween.TRANS_BACK)
    tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.15)


const ICON_MAP: Texture2D = preload("res://assets/icons_negotiation_menu/map.svg")
const ICON_MAP_ON: Texture2D = preload("res://assets/icons_negotiation_menu/map_on.svg")

func _on_select_all_button_pressed() -> void:
    # Если у игрока вообще нет оккупированных провинций врага — ничего не делаем
    if _occupied_snapshot.is_empty():
        return

    if SelectAllButton.icon == ICON_MAP_ON:
        # Кнопка работает как "Сбросить всё"
        for p_id in _claimed.duplicate():
            var original_owner = _occupied_snapshot[p_id]
            ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = original_owner
            ProvinceRegistry.province_occupants[p_id] = original_owner
            ProvinceRegistry.province_occupied.emit(p_id, original_owner)
        _claimed.clear()
        print("[Negotiation] Выбор всех провинций сброшен")

        SelectAllButton.icon = ICON_MAP
    else:
        # Кнопка работает как "Выбрать всё"
        for p_id in _occupied_snapshot:
            if not p_id in _claimed:
                _claimed.append(p_id)
                ProvinceRegistry.province_data[str(p_id)]["against_occupation"] = ""
                ProvinceRegistry.province_occupants.erase(p_id)
                ProvinceRegistry.province_occupied.emit(p_id, "")
        print("[Negotiation] Все оккупированные провинции выбраны: ", _claimed.size())

        SelectAllButton.icon = ICON_MAP_ON

    # НОВОЕ: Пересчитываем провинции при выборе/сбросе «Выбрать всё»
    _update_country_info()


const ICON_COIN: Texture2D = preload("res://assets/icons_negotiation_menu/coin.svg")
const ICON_COIN_ON: Texture2D = preload("res://assets/icons_negotiation_menu/coin_on.svg")

func _on_war_reparations_button_pressed() -> void:
    if _reparations_active:
        _hide_reparations_slider()
    else:
        _show_reparations_slider()


func _show_reparations_slider() -> void:
    var enemy_gdp = ProvinceRegistry.get_gdp(_enemy)
    var max_amount = max(1.0, floor(enemy_gdp / 3.0))

    ReparationsSlider.min_value = 1
    ReparationsSlider.max_value = max_amount
    ReparationsSlider.value = 1
    ReparationsSlider.show()

    WarReparationsButton.icon = ICON_COIN_ON
    _reparations_active = true

    print("[Negotiation] Слайдер репараций: 1..%d" % int(max_amount))


func _hide_reparations_slider() -> void:
    ReparationsSlider.hide()
    WarReparationsButton.icon = ICON_COIN
    _reparations_active = false


func _on_reparations_slider_changed(value: float) -> void:
    $ReparationsSlider/ReparationCostLabel.text = ProvinceRegistry._format_number(value, '.') + "$ "


const ICON_FLAG: Texture2D = preload("res://assets/icons_negotiation_menu/flag.svg")
const ICON_FLAG_ON: Texture2D = preload("res://assets/icons_negotiation_menu/flag_on.svg")

func _on_change_ideology_button_pressed() -> void:
    _ideology_change_active = not _ideology_change_active
    ChangeIdeologyButton.icon = ICON_FLAG_ON if _ideology_change_active else ICON_FLAG

const ICON_CROWN: Texture2D = preload("res://assets/icons_negotiation_menu/crown.svg")
const ICON_CROWN_ON: Texture2D = preload("res://assets/icons_negotiation_menu/crown_on.svg")

func _on_control_button_pressed() -> void:
    _controller_set_active = not _controller_set_active
    ControlButton.icon = ICON_CROWN_ON if _controller_set_active else ICON_CROWN
    
func _set_controller(controller, puppet):
    var controller_data = ProvinceRegistry.countries_data[controller]
    var puppet_data = ProvinceRegistry.countries_data[puppet]
    controller_data["control"].append(puppet)
    puppet_data["controller"] = controller
