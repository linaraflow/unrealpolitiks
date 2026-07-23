extends Control

var settings = preload("res://new_resource.tres")

@onready var flag_button: Button = $TopPanel/Flag
@onready var uav_label: Button = $TopPanel/UAVLabel
@onready var panel_uav_empty: PanelContainer = $PanelUAVEmpty
@onready var panel_uav_order: PanelContainer = $PanelUAVOrder
@onready var create_button: Button = $PanelUAVEmpty/MarginContainer/VBoxContainer/CreateButton
@onready var empty_flag_icon: TextureRect = $PanelUAVEmpty/MarginContainer/VBoxContainer/HBoxContainer/FlagIcon
@onready var empty_uav_label: Label = $PanelUAVEmpty/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/UAVLabel

var UAV_COMPANY_COST = settings.UAV_COMPANY_COST

# ─── Узлы панели заказа БПЛА (PanelUAVOrder) ───────────────────────────────────
@onready var order_uav_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/UAVLabel
@onready var order_produce_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/ProduceLabel

@onready var order_uav_caption: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/GridContainer/NumberUAVCard/VBoxContainer/UAVCaption
@onready var order_card_number_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/GridContainer/NumberUAVCard/VBoxContainer/NumberLabel

@onready var order_speed_caption: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/GridContainer/SpeedCard/VBoxContainer/SpeedCaption
@onready var order_speed_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/GridContainer/SpeedCard/VBoxContainer/SpeedLabel

@onready var order_status_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/OrderLabel

@onready var order_slider_number_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/Slider/NumberLabel
@onready var order_h_slider: HSlider = $PanelUAVOrder/MarginContainer/VBoxContainer/Slider/HSlider
@onready var order_real_number_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/Slider/RealNumberLabel

@onready var order_time_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/HBoxContainer2/HBoxContainer/TimeLabel
@onready var order_price_label: Label = $PanelUAVOrder/MarginContainer/VBoxContainer/HBoxContainer2/PriceLabel

@onready var order_button: Button = $PanelUAVOrder/MarginContainer/VBoxContainer/OrderButton
@onready var launch_button: Button = $PanelUAVOrder/MarginContainer/VBoxContainer/HBoxContainer/LaunchButton

@onready var balance_label: Label = $TopPanel/BalanceLabel

# Кэш скорости производства БПЛА (шт/день), пересчитывается при каждом refresh панели заказа
var _order_uav_speed: float = 0.0
var _order_uav_cost: float = 0.0


func _ready() -> void:
    hide()
    panel_uav_empty.hide()
    panel_uav_order.hide()

    uav_label.pressed.connect(_on_uav_label_pressed)
    create_button.pressed.connect(_on_create_button_pressed)

    order_h_slider.value_changed.connect(_on_order_slider_value_changed)
    order_button.pressed.connect(_on_order_button_pressed)
    launch_button.pressed.connect(_on_launch_button_pressed)
    ProvinceRegistry.uav_order_changed.connect(_on_uav_order_changed)

    # Кнопка заказа должна выглядеть одинаково и активной, и disabled (плоский стиль без изменений)
    var order_button_normal_style := order_button.get_theme_stylebox("normal")
    if order_button_normal_style:
        order_button.add_theme_stylebox_override("disabled", order_button_normal_style)
        order_button.add_theme_stylebox_override("hover", order_button_normal_style)
        order_button.add_theme_stylebox_override("pressed", order_button_normal_style)
    var order_button_normal_color := order_button.get_theme_color("font_color")
    order_button.add_theme_color_override("font_disabled_color", order_button_normal_color)


func _on_uav_label_pressed() -> void:
    var country_data = ProvinceRegistry.countries_data[settings.active_country]
    if country_data["uav_company"]:
        # компания уже куплена — открываем/закрываем меню заказа
        panel_uav_order.visible = not panel_uav_order.visible
        if panel_uav_order.visible:
            _refresh_order_panel()
    else:
        # компании ещё нет — открываем/закрываем меню покупки
        if not panel_uav_empty.visible:
            _update_panel_uav_empty(country_data)
        panel_uav_empty.visible = not panel_uav_empty.visible


func _update_panel_uav_empty(country_data: Dictionary) -> void:
    empty_uav_label.text = "UAV programm of " + str(settings.active_country).capitalize()
    empty_flag_icon.texture = load("res://assets/flags/" + str(settings.active_country) + ".png")


func _on_create_button_pressed() -> void:
    var country_data = ProvinceRegistry.countries_data[settings.active_country]
    if country_data["balance"] < UAV_COMPANY_COST:
        return

    country_data["balance"] -= UAV_COMPANY_COST
    balance_label.balance_update()
    country_data["uav_company"] = true

    panel_uav_empty.hide()
    _refresh_order_panel()
    panel_uav_order.show()


func update(country):
    var texture = load("res://assets/flags/" + str(country) + ".png")

    # Создаем новый текстурный стиль
    var new_style = StyleBoxTexture.new()
    new_style.texture = texture

    # Режим растягивания: игнорировать пропорции и заполнить всё пространство
    new_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
    new_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

    # Применяем этот стиль для разных состояний
    flag_button.add_theme_stylebox_override("normal", new_style)
    flag_button.add_theme_stylebox_override("hover", new_style)
    flag_button.add_theme_stylebox_override("pressed", new_style)

    # Обновляем текст кнопки UAV (значение хранится как float, убираем ".0")
    var country_data = ProvinceRegistry.countries_data[country]
    uav_label.text = str(int(country_data["uav"]))


func _on_flag_mouse_entered() -> void:
    flag_button.modulate = Color(0.7, 0.7, 0.7)  # темнее


func _on_flag_mouse_exited() -> void:
    flag_button.modulate = Color(1, 1, 1)  # обратно нормальный


# ─── ПАНЕЛЬ ЗАКАЗА БПЛА ─────────────────────────────────────────────────────────

## Полностью пересобирает содержимое PanelUAVOrder под текущую страну/баланс/заказ.
## Вызывать при открытии панели и при изменении активного заказа.
func _refresh_order_panel() -> void:
    var country = settings.active_country
    if not ProvinceRegistry.countries_data.has(country):
        return
    var country_data: Dictionary = ProvinceRegistry.countries_data[country]

    _order_uav_cost = settings.uav_cost
    _order_uav_speed = ProvinceRegistry.get_uav_production_speed(country)

    # Счётчик БПЛА страны всегда выводится в TopPanel/UAVLabel
    uav_label.text = str(int(country_data.get("uav", 0)))

    order_uav_label.text = "UAV of " + country
    order_produce_label.text = "UAV Production"

    order_uav_caption.text = "Amount"
    order_speed_caption.text = "Speed"
    order_speed_label.text = "%.1f/day" % _order_uav_speed

    if ProvinceRegistry.has_active_uav_order(country):
        _show_active_order(country)
    else:
        _show_new_order_form(country_data)


## Состояние "заказа ещё нет" — слайдер активен, можно выбрать количество и оформить заказ
func _show_new_order_form(country_data: Dictionary) -> void:
    order_status_label.text = "New Order"

    order_h_slider.editable = true
    order_button.disabled = false

    var balance: float = float(country_data.get("balance", 0.0))
    var max_uav: int = 0
    if _order_uav_cost > 0.0:
        max_uav = int(floor(balance / _order_uav_cost))

    order_h_slider.min_value = 0
    order_h_slider.max_value = max_uav
    order_h_slider.step = 1
    order_h_slider.value = 0

    order_real_number_label.text = "of %s" % ProvinceRegistry._format_number(max_uav)

    _update_order_preview(0)


## Состояние "заказ уже производится" — слайдер и кнопка заблокированы, показываем прогресс
func _show_active_order(country: String) -> void:
    var info: Dictionary = ProvinceRegistry.get_uav_order_info(country)
    if info.is_empty():
        _show_new_order_form(ProvinceRegistry.countries_data[country])
        return

    order_h_slider.editable = false
    order_button.disabled = true

    var total: int = int(info["total"])
    var remaining: float = info["remaining"]
    var per_day: float = info["per_day"]
    var produced: int = total - int(ceil(remaining))

    order_status_label.text = "Order In Production"
    order_slider_number_label.text = str(total)
    order_h_slider.max_value = max(total, 1)
    order_h_slider.value = total - remaining

    order_card_number_label.text = "%s / %s" % [
        ProvinceRegistry._format_number(produced),
        ProvinceRegistry._format_number(total)
    ]

    var days_left: float = 0.0
    if per_day > 0.0:
        days_left = remaining / per_day
    order_time_label.text = "%.0f days" % ceil(days_left)

    order_real_number_label.text = ""
    order_price_label.text = ""


func _on_order_slider_value_changed(value: float) -> void:
    _update_order_preview(value)


## Живой пересчёт количества / времени производства / цены при перетаскивании слайдера
func _update_order_preview(value: float) -> void:
    var amount: int = int(value)

    order_slider_number_label.text = str(amount)
    order_card_number_label.text = str(amount)

    var days: float = 0.0
    if _order_uav_speed > 0.0:
        days = amount / _order_uav_speed
    order_time_label.text = "%.0f days" % ceil(days)

    var price: float = amount * _order_uav_cost
    order_price_label.text = "$" + ProvinceRegistry._format_number(price)


func _on_order_button_pressed() -> void:
    var country = settings.active_country
    var amount: int = int(order_h_slider.value)
    if amount <= 0:
        return
    
    if ProvinceRegistry.start_uav_order(country, amount):
        _refresh_order_panel()
        balance_label.balance_update()

## ProvinceRegistry сигналит сюда при старте/прогрессе/завершении заказа.
## Счётчик в TopPanel обновляем всегда, саму панель — только если она открыта для этой страны.
func _on_uav_order_changed(country: String) -> void:
    if country != settings.active_country:
        return

    var country_data: Dictionary = ProvinceRegistry.countries_data.get(country, {})
    uav_label.text = str(int(country_data.get("uav", 0)))

    if panel_uav_order.visible:
        _refresh_order_panel()


# ─── ЗАПУСК БПЛА ────────────────────────────────────────────────────────────────

## LaunchButton в PanelUAVOrder — открывает UAVMenu и переводит карту
## в режим прицеливания: все провинции кроме своих и вражеских затемняются.
func _on_launch_button_pressed() -> void:
    var country = settings.active_country
    var enemies: Array = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        print("[TopMenu] Нет противников для запуска БПЛА")
        return

    panel_uav_order.hide()

    var uav_menu = get_node("/root/Game/CanvasLayer/UAVMenu")
    uav_menu.open_uav_mode(enemies)
