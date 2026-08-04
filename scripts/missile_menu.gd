extends Control

var settings = preload("res://new_resource.tres")

@onready var Map = get_node("/root/Game/Map")

@onready var leave_button: Button = $MainPanel/LeaveButton
@onready var launch_button: Button = $LaunchButton

# Меню, которые нужно спрятать на время прицеливания (как в uav_menu.gd)
var menu_to_close: Array = []

var _enemies: Array = []

# Только ОДНА выбранная цель — конкретная дивизия (ArmyCircle), не провинция.
# null значит цель не выбрана.
var selected_target_division: Node = null


func _ready() -> void:
    menu_to_close = [get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu"),
                     get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu"),
                     get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu"),
                     get_node("/root/Game/CanvasLayer/TopMenu"),
                     get_node("/root/Game/CanvasLayer/NotificationMenu"),
                     get_node("/root/Game/CanvasLayer/StatisticsMenu")]

    leave_button.pressed.connect(_on_leave_button_pressed)
    launch_button.pressed.connect(_on_launch_button_pressed)

    hide()


## Открыть меню запуска ракеты. enemies — список стран-противников (война).
## Вызывается из top_menu.gd при нажатии LaunchButton панели PanelMissileOrder.
func open_missile_mode(enemies: Array) -> void:
    _enemies = enemies
    _clear_selection()

    Map.enter_missile_mode(enemies)
    GameClock.lock_pause()

    for menu in menu_to_close:
        menu.hide()

    show()
    print("[MissileMenu] Открыт режим запуска ракеты, противников: ", enemies.size())


## Клик по дивизии (ArmyCircle) на карте в режиме ракеты.
## Можно выбрать только ОДНУ дивизию: повторный клик по ней снимает выбор,
## клик по другой вражеской дивизии просто заменяет текущую цель.
func on_division_clicked(division: Node) -> void:
    if not is_instance_valid(division):
        return

    var owner = division.division_owner
    if not (owner in _enemies):
        print("[MissileMenu] Дивизия не является целью (владелец: ", owner, ")")
        return

    if selected_target_division == division:
        division.deselect_missile_target()
        selected_target_division = null
        print("[MissileMenu] Дивизия убрана из цели")
    else:
        if is_instance_valid(selected_target_division):
            selected_target_division.deselect_missile_target()
        selected_target_division = division
        division.select_missile_target()
        print("[MissileMenu] Дивизия ", division.army_name, " выбрана целью")

    _update_target_line()


## Пересчитывает дугообразную линию "столица -> цель" и отправляет в Map.
func _update_target_line() -> void:
    if not is_instance_valid(selected_target_division):
        Map.clear_missile_target_line()
        return

    var cap_id = int(ProvinceRegistry.countries_data.get(settings.active_country, {}).get("capital", 0))
    if not Map.province_centers.has(cap_id):
        print("[MissileMenu] Не найдена позиция столицы своей страны (cap_id=", cap_id, ")")
        return

    var from_pos: Vector2 = Map.province_centers[cap_id]
    var to_pos: Vector2 = selected_target_division.position
    Map.set_missile_target_line(from_pos, to_pos)


func _on_leave_button_pressed() -> void:
    close_missile_mode()


## Закрыть меню и вернуть карту/UI в обычный режим.
func close_missile_mode() -> void:
    Map.exit_missile_mode()  # exit_missile_mode() сам чистит линию цели
    GameClock.unlock_pause()  # снимаем блокировку, но игра остаётся на паузе
    _enemies = []
    _clear_selection()

    for menu in menu_to_close:
        menu.show()

    hide()


## Снимает серое выделение с выбранной дивизии (если есть) и сбрасывает цель.
func _clear_selection() -> void:
    if is_instance_valid(selected_target_division):
        selected_target_division.deselect_missile_target()
    selected_target_division = null


## LaunchButton — запускает ОДНУ ракету в выбранную дивизию.
## Ракета летит именно за дивизией: если та сменит провинцию в полёте,
## ракета довернёт следом (см. missile.gd/_update_homing).
func _on_launch_button_pressed() -> void:
    if not is_instance_valid(selected_target_division):
        print("[MissileMenu] Цель не выбрана")
        return

    var country_data = ProvinceRegistry.countries_data.get(settings.active_country, {})
    var current_missiles = int(country_data.get("missile", 0))

    if current_missiles < 1:
        print("[MissileMenu] Не хватает ракет для запуска!")
        return

    country_data["missile"] = current_missiles - 1
    ProvinceRegistry.missile_order_changed.emit(settings.active_country)

    var cap_id = int(country_data.get("capital", 0))
    var start_pos: Vector2 = Map.province_centers[cap_id]
    var target_division = selected_target_division
    var target_pos: Vector2 = target_division.position

    var MissileScript = preload("res://scripts/missile.gd")
    var missile = Sprite2D.new()
    missile.set_script(MissileScript)

    missile.start_pos = start_pos
    missile.target_pos = target_pos
    missile.control_pos = MissileLinesLayer.compute_arc_control(start_pos, target_pos)
    missile.target_p_id = target_division.province_id
    missile.target_division = target_division
    missile.attacker_country = settings.active_country

    Map.add_child(missile)

    close_missile_mode()
