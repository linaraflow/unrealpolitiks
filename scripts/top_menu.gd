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

@onready var statistics_menu = get_node("/root/Game/CanvasLayer/StatisticsMenu")

# SellMenu — панель продажи продуктов, лежит как %SellMenu под TopPanel/ProductsLabel
# (её открывает products_label.gd через клик по RichTextLabel, не через Button).
@onready var panel_products: Control = get_node_or_null("%SellMenu")

# Кэш скорости производства БПЛА (шт/день), пересчитывается при каждом refresh панели заказа
var _order_uav_speed: float = 0.0
var _order_uav_cost: float = 0.0

# ─── Узлы панели заказа Ракет (зеркально панели БПЛА) ──────────────────────────
@onready var missile_label: Button = $TopPanel/MissileLabel
@onready var panel_missile_empty: PanelContainer = $PanelMissileEmpty
@onready var panel_missile_order: PanelContainer = $PanelMissileOrder
@onready var create_missile_button: Button = $PanelMissileEmpty/MarginContainer/VBoxContainer/CreateButton
@onready var empty_missile_flag_icon: TextureRect = $PanelMissileEmpty/MarginContainer/VBoxContainer/HBoxContainer/FlagIcon
@onready var empty_missile_label: Label = $PanelMissileEmpty/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/MissileLabel

@onready var missile_company_price_label: Label = $PanelMissileEmpty/MarginContainer/VBoxContainer/CreateButton/MarginContainer/HBoxContainer/PriceLabel
@onready var uav_company_price_label: Label = $PanelUAVEmpty/MarginContainer/VBoxContainer/CreateButton/MarginContainer/HBoxContainer/PriceLabel

var MISSILE_COMPANY_COST = settings.MISSILE_COMPANY_COST

@onready var order_missile_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/MissileLabel
@onready var order_missile_produce_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/ProduceLabel

@onready var order_missile_caption: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/GridContainer/NumberMissileCard/VBoxContainer/MissileCaption
@onready var order_missile_card_number_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/GridContainer/NumberMissileCard/VBoxContainer/NumberLabel

@onready var order_missile_speed_caption: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/GridContainer/SpeedCard/VBoxContainer/SpeedCaption
@onready var order_missile_speed_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/GridContainer/SpeedCard/VBoxContainer/SpeedLabel

@onready var order_missile_status_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/OrderLabel

@onready var order_missile_slider_number_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/Slider/NumberLabel
@onready var order_missile_h_slider: HSlider = $PanelMissileOrder/MarginContainer/VBoxContainer/Slider/HSlider
@onready var order_missile_real_number_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/Slider/RealNumberLabel

@onready var order_missile_time_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/HBoxContainer2/HBoxContainer/TimeLabel
@onready var order_missile_price_label: Label = $PanelMissileOrder/MarginContainer/VBoxContainer/HBoxContainer2/PriceLabel

@onready var order_missile_button: Button = $PanelMissileOrder/MarginContainer/VBoxContainer/OrderButton
@onready var missile_launch_button: Button = $PanelMissileOrder/MarginContainer/VBoxContainer/HBoxContainer/LaunchButton

@onready var ai_army_tick: CheckBox = $TopPanel/AIArmyContainer/CheckBox


# Кэш скорости производства ракет (шт/МЕСЯЦ), пересчитывается при каждом refresh панели заказа
var _order_missile_speed: float = 0.0
var _order_missile_cost: float = 0.0


func _ready() -> void:
    SaveManager.TopMenu = self
    
    hide()
    panel_uav_empty.hide()
    panel_uav_order.hide()
    panel_missile_empty.hide()
    panel_missile_order.hide()

    flag_button.pressed.connect(_on_flag_button_pressed)

    uav_label.pressed.connect(_on_uav_label_pressed)
    create_button.pressed.connect(_on_create_button_pressed)

    order_h_slider.value_changed.connect(_on_order_slider_value_changed)
    order_button.pressed.connect(_on_order_button_pressed)
    launch_button.pressed.connect(_on_launch_button_pressed)
    missile_launch_button.pressed.connect(_on_missile_launch_button_pressed)
    ProvinceRegistry.uav_order_changed.connect(_on_uav_order_changed)

    ai_army_tick.toggled.connect(_on_ai_army_tick_toggled)
    AIManager.player_ai_army_enabled = ai_army_tick.button_pressed

    missile_label.pressed.connect(_on_missile_label_pressed)
    create_missile_button.pressed.connect(_on_create_missile_button_pressed)

    order_missile_h_slider.value_changed.connect(_on_order_missile_slider_value_changed)
    order_missile_button.pressed.connect(_on_order_missile_button_pressed)
    ProvinceRegistry.missile_order_changed.connect(_on_missile_order_changed)

    # Кнопка заказа должна выглядеть одинаково и активной, и disabled (плоский стиль без изменений)
    var order_button_normal_style := order_button.get_theme_stylebox("normal")
    if order_button_normal_style:
        order_button.add_theme_stylebox_override("disabled", order_button_normal_style)
        order_button.add_theme_stylebox_override("hover", order_button_normal_style)
        order_button.add_theme_stylebox_override("pressed", order_button_normal_style)
    var order_button_normal_color := order_button.get_theme_color("font_color")
    order_button.add_theme_color_override("font_disabled_color", order_button_normal_color)

    var order_missile_button_normal_style := order_missile_button.get_theme_stylebox("normal")
    if order_missile_button_normal_style:
        order_missile_button.add_theme_stylebox_override("disabled", order_missile_button_normal_style)
        order_missile_button.add_theme_stylebox_override("hover", order_missile_button_normal_style)
        order_missile_button.add_theme_stylebox_override("pressed", order_missile_button_normal_style)
    var order_missile_button_normal_color := order_missile_button.get_theme_color("font_color")
    order_missile_button.add_theme_color_override("font_disabled_color", order_missile_button_normal_color)
    
    uav_company_price_label.text = "$" + str(ProvinceRegistry._format_number(settings.UAV_COMPANY_COST, "."))
    missile_company_price_label.text = "$" + str(ProvinceRegistry._format_number(settings.MISSILE_COMPANY_COST, "."))


## Прячет все панели TopMenu (UAV/Missile/Products), кроме перечисленных в keep_open.
## Вызывается перед открытием любой из них, чтобы не было двух открытых одновременно.
func _close_other_top_panels(keep_open: Array = []) -> void:
    for p in [panel_uav_empty, panel_uav_order, panel_missile_empty, panel_missile_order, panel_products]:
        if p == null or p in keep_open:
            continue
        p.hide()


## Кнопка TopMenu/TopPanel/Flag — открывает/закрывает панель статистики.
## Перед открытием закрываем остальные панели TopMenu (UAV/Missile/Products),
## чтобы не было двух открытых одновременно.
## Чекбокс "AI Army" в TopPanel — включает/выключает автоматическое движение
## армии игрока по тем же правилам, что использует ИИ (AIMilitary.process_military_movement).
func _on_ai_army_tick_toggled(toggled_on: bool) -> void:
    AIManager.player_ai_army_enabled = toggled_on


func _on_flag_button_pressed() -> void:
    _close_other_top_panels()
    statistics_menu.toggle_menu()


func _on_uav_label_pressed() -> void:
    var country_data = ProvinceRegistry.countries_data[settings.active_country]
    if country_data["uav_company"]:
        # компания уже куплена — открываем/закрываем меню заказа
        var was_open = panel_uav_order.visible
        _close_other_top_panels()
        panel_uav_order.visible = not was_open
        if panel_uav_order.visible:
            _refresh_order_panel()
    else:
        # компании ещё нет — открываем/закрываем меню покупки
        var was_open = panel_uav_empty.visible
        _close_other_top_panels()
        if not was_open:
            _update_panel_uav_empty(country_data)
        panel_uav_empty.visible = not was_open


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
    _close_other_top_panels()
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
    missile_label.text = str(int(country_data.get("missile", 0.0)))


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

    var products: float = float(country_data.get("products", 0.0))
    var max_uav: int = 0
    if _order_uav_cost > 0.0:
        max_uav = int(floor(products / _order_uav_cost))

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
    order_price_label.text = "📦 " + ProvinceRegistry._format_number(price) + " products"


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


# ─── ПАНЕЛЬ ЗАКАЗА РАКЕТ (зеркально панели БПЛА) ────────────────────────────────

func _on_missile_label_pressed() -> void:
    var country_data = ProvinceRegistry.countries_data[settings.active_country]
    if country_data["missile_company"]:
        # компания уже куплена — открываем/закрываем меню заказа
        var was_open = panel_missile_order.visible
        _close_other_top_panels()
        panel_missile_order.visible = not was_open
        if panel_missile_order.visible:
            _refresh_missile_order_panel()
    else:
        # компании ещё нет — открываем/закрываем меню покупки
        var was_open = panel_missile_empty.visible
        _close_other_top_panels()
        if not was_open:
            _update_panel_missile_empty(country_data)
        panel_missile_empty.visible = not was_open


func _update_panel_missile_empty(country_data: Dictionary) -> void:
    empty_missile_label.text = "Missile programm of " + str(settings.active_country).capitalize()
    empty_missile_flag_icon.texture = load("res://assets/flags/" + str(settings.active_country) + ".png")


func _on_create_missile_button_pressed() -> void:
    var country_data = ProvinceRegistry.countries_data[settings.active_country]
    if country_data["balance"] < MISSILE_COMPANY_COST:
        return

    country_data["balance"] -= MISSILE_COMPANY_COST
    balance_label.balance_update()
    country_data["missile_company"] = true

    panel_missile_empty.hide()
    _close_other_top_panels()
    _refresh_missile_order_panel()
    panel_missile_order.show()


## Полностью пересобирает содержимое PanelMissileOrder под текущую страну/баланс/заказ.
## Вызывать при открытии панели и при изменении активного заказа.
func _refresh_missile_order_panel() -> void:
    var country = settings.active_country
    if not ProvinceRegistry.countries_data.has(country):
        return
    var country_data: Dictionary = ProvinceRegistry.countries_data[country]

    _order_missile_cost = settings.missile_cost
    _order_missile_speed = ProvinceRegistry.get_missile_production_speed(country)

    # Счётчик ракет страны всегда выводится в TopPanel/MissileLabel
    missile_label.text = str(int(country_data.get("missile", 0.0)))

    order_missile_label.text = "Missile of " + country
    order_missile_produce_label.text = "Missile Production"

    order_missile_caption.text = "Amount"
    order_missile_speed_caption.text = "Speed"
    order_missile_speed_label.text = "%.2f/month" % _order_missile_speed

    if ProvinceRegistry.has_active_missile_order(country):
        _show_active_missile_order(country)
    else:
        _show_new_missile_order_form(country_data)


## Состояние "заказа ещё нет" — слайдер активен, можно выбрать количество и оформить заказ
func _show_new_missile_order_form(country_data: Dictionary) -> void:
    order_missile_status_label.text = "New Order"

    order_missile_h_slider.editable = true
    order_missile_button.disabled = false

    var products: float = float(country_data.get("products", 0.0))
    var max_missile: int = 0
    if _order_missile_cost > 0.0:
        max_missile = int(floor(products / _order_missile_cost))

    order_missile_h_slider.min_value = 0
    order_missile_h_slider.max_value = max_missile
    order_missile_h_slider.step = 1
    order_missile_h_slider.value = 0

    order_missile_real_number_label.text = "of %s" % ProvinceRegistry._format_number(max_missile)

    _update_missile_order_preview(0)


## Состояние "заказ уже производится" — слайдер и кнопка заблокированы, показываем прогресс.
## Скорость хранится "в месяц", но пополняется каждый игровой день дробными порциями,
## поэтому прогресс-бар и счётчик обновляются ежедневно, а не только раз в месяц.
func _show_active_missile_order(country: String) -> void:
    var info: Dictionary = ProvinceRegistry.get_missile_order_info(country)
    if info.is_empty():
        _show_new_missile_order_form(ProvinceRegistry.countries_data[country])
        return

    order_missile_h_slider.editable = false
    order_missile_button.disabled = true

    var total: int = int(info["total"])
    var remaining: float = info["remaining"]
    var per_month: float = info["per_month"]
    var produced: int = total - int(ceil(remaining))

    order_missile_status_label.text = "Order In Production"
    order_missile_slider_number_label.text = str(total)
    order_missile_h_slider.max_value = max(total, 1)
    order_missile_h_slider.value = total - remaining

    order_missile_card_number_label.text = "%s / %s" % [
        ProvinceRegistry._format_number(produced),
        ProvinceRegistry._format_number(total)
    ]

    var months_left: float = 0.0
    if per_month > 0.0:
        months_left = remaining / per_month
    order_missile_time_label.text = "%.1f months" % months_left

    order_missile_real_number_label.text = ""
    order_missile_price_label.text = ""


func _on_order_missile_slider_value_changed(value: float) -> void:
    _update_missile_order_preview(value)


## Живой пересчёт количества / времени производства / цены при перетаскивании слайдера
func _update_missile_order_preview(value: float) -> void:
    var amount: int = int(value)

    order_missile_slider_number_label.text = str(amount)
    order_missile_card_number_label.text = str(amount)

    var months: float = 0.0
    if _order_missile_speed > 0.0:
        months = amount / _order_missile_speed
    order_missile_time_label.text = "%.1f months" % months

    var price: float = amount * _order_missile_cost
    order_missile_price_label.text = "📦 " + ProvinceRegistry._format_number(price) + " products"


func _on_order_missile_button_pressed() -> void:
    var country = settings.active_country
    var amount: int = int(order_missile_h_slider.value)
    if amount <= 0:
        return

    if ProvinceRegistry.start_missile_order(country, amount):
        _refresh_missile_order_panel()
        balance_label.balance_update()

## ProvinceRegistry сигналит сюда при старте/прогрессе/завершении заказа.
## Счётчик в TopPanel обновляем всегда, саму панель — только если она открыта для этой страны.
func _on_missile_order_changed(country: String) -> void:
    if country != settings.active_country:
        return

    var country_data: Dictionary = ProvinceRegistry.countries_data.get(country, {})
    missile_label.text = str(int(country_data.get("missile", 0.0)))

    if panel_missile_order.visible:
        _refresh_missile_order_panel()


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

## LaunchButton в PanelMissileOrder — открывает MissileMenu и переводит карту
## в режим прицеливания ракеты: все провинции кроме своих и вражеских затемняются
## (использует ту же универсальную функцию Map._apply_targeting_mask(), что и БПЛА).
func _on_missile_launch_button_pressed() -> void:
    var country = settings.active_country
    var enemies: Array = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        print("[TopMenu] Нет противников для запуска ракеты")
        return

    panel_missile_order.hide()

    var missile_menu = get_node("/root/Game/CanvasLayer/MissileMenu")
    missile_menu.open_missile_mode(enemies)
