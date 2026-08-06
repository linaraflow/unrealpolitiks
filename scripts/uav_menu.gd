extends Control

var settings = preload("res://new_resource.tres")

@onready var Map = get_node("/root/Game/Map")

# Пути ниже собраны по дереву сцены со скриншота.
# Если у тебя структура чуть отличается — поправь пути под свою сцену.
@onready var leave_button: Button = $MainPanel/LeaveButton

@onready var uav_header: HBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/UAVHeader
@onready var total_label: Label = $PanelContainer/MarginContainer/VBoxContainer/UAVHeader/VBoxContainer/TotalLabel

@onready var main_card: PanelContainer = $PanelContainer/MarginContainer/VBoxContainer/MainCard
@onready var num_label: Label = $PanelContainer/MarginContainer/VBoxContainer/MainCard/VBoxContainer/HBoxContainer/NumLabel
@onready var minus_button: Button = $PanelContainer/MarginContainer/VBoxContainer/MainCard/VBoxContainer/SliderContainer/MinusButton
@onready var drones_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/MainCard/VBoxContainer/SliderContainer/HSlider
@onready var plus_button: Button = $PanelContainer/MarginContainer/VBoxContainer/MainCard/VBoxContainer/SliderContainer/PlusButton

@onready var launch_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LaunchButton

# Меню, которые нужно спрятать на время прицеливания (как в negotiation_menu.gd)
var menu_to_close: Array = []

var _enemies: Array = []

# Выбранные вражеские провинции-цели (клик по провинции — добавить/убрать)
var selected_targets: Array[int] = []

func _ready() -> void:
    menu_to_close = [get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu"),
                     get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu"),
                     get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu"),
                     get_node("/root/Game/CanvasLayer/TopMenu"),
                     get_node("/root/Game/CanvasLayer/NotificationMenu"),
                     get_node("/root/Game/CanvasLayer/StatisticsMenu")]

    leave_button.pressed.connect(_on_leave_button_pressed)
    launch_button.pressed.connect(_on_launch_button_pressed)

    drones_slider.min_value = 1
    drones_slider.step = 1
    drones_slider.value_changed.connect(_on_slider_value_changed)
    minus_button.pressed.connect(_on_minus_button_pressed)
    plus_button.pressed.connect(_on_plus_button_pressed)

    _update_labels()
    hide()


## Открыть меню запуска БПЛА. enemies — список стран-противников (война),
## их провинции остаются видимыми на карте, все остальные затемняются.
## Вызывается из top_menu.gd при нажатии LaunchButton.
func open_uav_mode(enemies: Array) -> void:
    _enemies = enemies
    selected_targets.clear()

    _update_slider_max()
    _update_labels()

    Map.enter_uav_mode(enemies)
    GameClock.lock_pause()

    for menu in menu_to_close:
        menu.hide()

    show()
    print("[UAVMenu] Открыт режим запуска БПЛА, противников: ", enemies.size())


## Клик по видимой (не затемнённой) провинции карты в режиме БПЛА.
## Клик по вражеской провинции добавляет/убирает её из списка целей —
## от столицы своей страны до каждой цели рисуется линия со стрелочками.
## Клик по своей провинции игнорируется (целью быть не может).
func on_province_clicked(p_id: int) -> void:
    var owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")

    if not (owner in _enemies):
        print("[UAVMenu] Провинция ", p_id, " не является целью (владелец: ", owner, ")")
        return

    if p_id in selected_targets:
        selected_targets.erase(p_id)
        print("[UAVMenu] Провинция ", p_id, " убрана из целей")
    else:
        # Добавляем цель, только если на неё хватит дронов при текущем значении
        # слайдера: drones_per_target * (кол-во целей ПОСЛЕ добавления) <= доступно.
        var needed_if_added = int(drones_slider.value) * (selected_targets.size() + 1)
        if needed_if_added > _get_available_uavs():
            print("[UAVMenu] Недостаточно БПЛА для ещё одной цели (нужно: ", needed_if_added, ", доступно: ", _get_available_uavs(), ")")
            return

        selected_targets.append(p_id)
        print("[UAVMenu] Провинция ", p_id, " добавлена в цели")

    _update_target_lines()
    _update_slider_max()
    _update_labels()


## Пересчитывает линии "столица -> цель" по текущему selected_targets
## и отправляет их на отрисовку в Map.
func _update_target_lines() -> void:
    if selected_targets.is_empty():
        Map.clear_uav_target_lines()
        return

    var cap_id = int(ProvinceRegistry.countries_data.get(settings.active_country, {}).get("capital", 0))
    if not Map.province_centers.has(cap_id):
        print("[UAVMenu] Не найдена позиция столицы своей страны (cap_id=", cap_id, ")")
        return

    var from_pos: Vector2 = Map.province_centers[cap_id]

    var targets: Array = []
    for target_id in selected_targets:
        if Map.province_centers.has(target_id):
            targets.append(Map.province_centers[target_id])

    Map.set_uav_target_lines(from_pos, targets)


## Реакция на изменение значения слайдера "кол-во дронов на провинцию".
func _on_slider_value_changed(_value: float) -> void:
    _update_labels()


func _on_minus_button_pressed() -> void:
    drones_slider.value -= 1


func _on_plus_button_pressed() -> void:
    drones_slider.value += 1


## Сколько БПЛА сейчас доступно у активной страны.
func _get_available_uavs() -> int:
    var country_data = ProvinceRegistry.countries_data.get(settings.active_country, {})
    return int(country_data.get("uav", 0))


## max_value слайдера = доступные БПЛА / кол-во выбранных провинций (целочисленно),
## чтобы нельзя было выбрать больше дронов на провинцию, чем реально хватит на все цели.
## Если провинции ещё не выбраны — делим на 1 (весь запас доступен на одну цель).
func _update_slider_max() -> void:
    var available = _get_available_uavs()
    var targets_count = max(selected_targets.size(), 1)
    var new_max = max(available / targets_count, 1)

    drones_slider.max_value = new_max
    drones_slider.value = clamp(drones_slider.value, 1, new_max)


## Кол-во дронов на одну провинцию — берём из слайдера.
func _get_drones_per_province() -> int:
    return int(drones_slider.value)


## TotalLabel = "N available" — сколько БПЛА всего есть у страны.
## NumLabel = "на провинцию / нужно всего" — где "нужно всего" = slider.value * кол-во выбранных провинций.
func _update_labels() -> void:
    var available = _get_available_uavs()
    var per_province = _get_drones_per_province()
    var total_needed = per_province * selected_targets.size()

    total_label.text = str(available) + " " + tr("AVAILABLE")
    num_label.text = str(per_province) + " / " + str(total_needed)


## Повесь эту функцию на кнопку закрытия меню в редакторе (CloseButton.pressed).
func _on_close_button_pressed() -> void:
    close_uav_mode()


## MainPanel/LeaveButton — выход из режима запуска БПЛА.
func _on_leave_button_pressed() -> void:
    close_uav_mode()


## Закрыть меню и вернуть карту/UI в обычный режим.
func close_uav_mode() -> void:
    Map.exit_uav_mode()  # exit_uav_mode() сам чистит линии целей
    GameClock.unlock_pause()  # снимаем блокировку, но игра остаётся на паузе
    _enemies = []
    selected_targets.clear()
    _update_labels()

    for menu in menu_to_close:
        menu.show()

    hide()


func _on_launch_button_pressed() -> void:
    var drones_per_target = _get_drones_per_province()
    var total_needed = selected_targets.size() * drones_per_target

    if total_needed <= 0:
        return

    var country_data = ProvinceRegistry.countries_data.get(settings.active_country, {})
    var current_uavs = int(country_data.get("uav", 0))

    if current_uavs < total_needed:
        print("[UAVMenu] Не хватает БПЛА для запуска! Требуется: ", total_needed)
        return

    country_data["uav"] -= total_needed
    ProvinceRegistry.uav_order_changed.emit(settings.active_country)

    var cap_id = int(country_data.get("capital", 0))
    var start_pos = Map.province_centers[cap_id]
    var DroneScript = preload("res://scripts/uav_drone.gd")

    # Выпускаем ровно ОДНУ текстуру на каждую цель
    for target_id in selected_targets:
        var drone = Sprite2D.new()
        drone.set_script(DroneScript)

        drone.position = start_pos
        drone.target_pos = settings.province_centers[target_id]
        drone.target_p_id = target_id

        # Передаем системное количество дронов внутрь скрипта
        drone.amount = drones_per_target
        # Страна-атакующий, чтобы за уничтоженные фабрики начислялся продукт
        drone.attacker_country = settings.active_country

        Map.add_child(drone)

    close_uav_mode()
