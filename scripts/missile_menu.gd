extends Control

var settings = preload("res://new_resource.tres")

@onready var Map = get_node("/root/Game/Map")

@onready var leave_button: Button = $MainPanel/LeaveButton
@onready var launch_button: Button = $LaunchButton

# Меню, которые нужно спрятать на время прицеливания (как в uav_menu.gd)
var menu_to_close: Array = []

var _enemies: Array = []

# Только ОДНА выбранная цель. -1 значит цель не выбрана.
var selected_target: int = -1


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
    selected_target = -1

    Map.enter_missile_mode(enemies)
    GameClock.lock_pause()

    for menu in menu_to_close:
        menu.hide()

    show()
    print("[MissileMenu] Открыт режим запуска ракеты, противников: ", enemies.size())


## Клик по видимой (не затемнённой) провинции карты в режиме ракеты.
## Можно выбрать только ОДНУ провинцию: повторный клик по ней снимает выбор,
## клик по другой вражеской провинции просто заменяет текущую цель.
func on_province_clicked(p_id: int) -> void:
    var owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")

    if not (owner in _enemies):
        print("[MissileMenu] Провинция ", p_id, " не является целью (владелец: ", owner, ")")
        return

    if selected_target == p_id:
        selected_target = -1
        print("[MissileMenu] Провинция ", p_id, " убрана из цели")
    else:
        selected_target = p_id
        print("[MissileMenu] Провинция ", p_id, " выбрана целью")

    _update_target_line()


## Пересчитывает дугообразную линию "столица -> цель" и отправляет в Map.
func _update_target_line() -> void:
    if selected_target < 0:
        Map.clear_missile_target_line()
        return

    var cap_id = int(ProvinceRegistry.countries_data.get(settings.active_country, {}).get("capital", 0))
    if not Map.province_centers.has(cap_id):
        print("[MissileMenu] Не найдена позиция столицы своей страны (cap_id=", cap_id, ")")
        return
    if not Map.province_centers.has(selected_target):
        return

    var from_pos: Vector2 = Map.province_centers[cap_id]
    var to_pos: Vector2 = Map.province_centers[selected_target]
    Map.set_missile_target_line(from_pos, to_pos)


func _on_leave_button_pressed() -> void:
    close_missile_mode()


## Закрыть меню и вернуть карту/UI в обычный режим.
func close_missile_mode() -> void:
    Map.exit_missile_mode()  # exit_missile_mode() сам чистит линию цели
    GameClock.unlock_pause()  # снимаем блокировку, но игра остаётся на паузе
    _enemies = []
    selected_target = -1

    for menu in menu_to_close:
        menu.show()

    hide()


## LaunchButton — запускает ОДНУ ракету в выбранную провинцию.
func _on_launch_button_pressed() -> void:
    if selected_target < 0:
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
    var target_pos: Vector2 = Map.province_centers[selected_target]

    var MissileScript = preload("res://scripts/missile.gd")
    var missile = Sprite2D.new()
    missile.set_script(MissileScript)

    missile.start_pos = start_pos
    missile.target_pos = target_pos
    missile.control_pos = MissileLinesLayer.compute_arc_control(start_pos, target_pos)
    missile.target_p_id = selected_target
    missile.attacker_country = settings.active_country

    Map.add_child(missile)

    close_missile_mode()
