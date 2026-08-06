extends Panel

var settings = preload("res://new_resource.tres")

@onready var slider = $VSlider # Твой вертикальный слайдер
@onready var troops_label = $TroopsLabel # Текст с войсками
@onready var cost_label = $CostLabel # Текст со стоимостью
@onready var confirm_btn = $ConfirmButton # Кнопка "Призвать"
@onready var balance_label = get_node_or_null("/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel")

var HAPPINESS_DRAIN_PER_1K_RECRUITS = 0.1

var current_province_id = -1
var local_pos = Vector2.ZERO
var cost

func _ready():
    hide()
    slider.value_changed.connect(_on_slider_value_changed)
    confirm_btn.pressed.connect(_on_confirm_pressed)

func open_menu(province_id: int, pos: Vector2, pop: int, balance: float):
    current_province_id = province_id
    local_pos = pos

    # Считаем лимиты: 1% от населения и сколько денег в казне
    var pop_limit = int(pop * 0.01)
    var money_limit = int(balance / settings.COST_PER_SOLDIER)
    
    # Максимум можно призвать то, во что мы упираемся раньше
    var max_recruits = min(pop_limit, money_limit)

    if max_recruits < 100:
        return # Слишком мало ресурсов для минимального призыва

    slider.min_value = 0
    slider.max_value = max_recruits
    slider.value = max_recruits # Ставим ползунок на максимум по умолчанию
    
    _update_info(slider.value)
    show()

func _on_slider_value_changed(value: float):
    _update_info(int(value))

func _update_info(amount: int):
    cost = int(amount * settings.COST_PER_SOLDIER)
    troops_label.text = "🪖 " + tr("TROOPS") + ": " + str(amount)
    cost_label.text = "💵 " + tr("COST") + ": " + ProvinceRegistry._format_number(cost, ".")
    # Минимальный порог призыва - 100 человек
    confirm_btn.disabled = amount < 100

func _on_confirm_pressed():
    if slider.value >= 100:
        DivisionManager.recruit(current_province_id, local_pos, int(slider.value))
        ProvinceRegistry.countries_data[settings.active_country]["balance"] -= cost
        var happiness_drain = (float(slider.value) / 1000.0) * HAPPINESS_DRAIN_PER_1K_RECRUITS
        var province_happiness = ProvinceRegistry.province_data[current_province_id]["happiness"]
        ProvinceRegistry.province_data[current_province_id]["happiness"] = max(0.0, province_happiness - happiness_drain)
        balance_label.balance_update()
        hide()
        # Вызываем обновление UI (например, в ProvinceMenu и DivisionMenu)
        get_parent().update_info(ProvinceRegistry.province_data[current_province_id])
