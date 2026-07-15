extends Control

@export var settings: Resource

# Высоты панели с кнопками призыва/постройки и без них — подбери под свою
# сцену: временно закомментируй строки ниже, запусти игру, наведи на
# "свою" провинцию (кнопки видны), глянь Panel.size.y в Remote-инспекторе,
# повтори для чужой (кнопки скрыты), впиши оба значения сюда.
const PANEL_HEIGHT_WITH_ACTIONS := 245.0
const PANEL_HEIGHT_WITHOUT_ACTIONS := 145.0

@onready var owner_label = $Panel/MarginContainer/VBoxContainer/HeaderRow/OwnerLabel
@onready var name_label  = $Panel/MarginContainer/VBoxContainer/HeaderRow/NameLabel
@onready var population_label = $Panel/MarginContainer/VBoxContainer/StatsRow/PopulationBox/VBoxContainer/PopulationLabel
@onready var factories_label = $Panel/MarginContainer/VBoxContainer/StatsRow/FactoriesBox/VBoxContainer/FactoriesLabel
@onready var happiness_label = $Panel/MarginContainer/VBoxContainer/HappinessRow/HappinessLabel
@onready var happiness_bar = $Panel/MarginContainer/VBoxContainer/HappinessRow/HappinessBar
@onready var actions_section = $Panel/MarginContainer/VBoxContainer/ActionsRow
@onready var actions_separator = $Panel/MarginContainer/VBoxContainer/HSeparator
@onready var recruit_btn = $Panel/MarginContainer/VBoxContainer/ActionsRow/RecruitButton
@onready var build_factory_btn = $Panel/MarginContainer/VBoxContainer/ActionsRow/BuildFactoryButton
@onready var balance_label = get_node_or_null("/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel")
@onready var division_menu = get_node_or_null("/root/Game/CanvasLayer/DivisionMenu")
@onready var recruit_slider_panel = $RecruitSliderPanel

var current_province_id: int = -1

# --- lifecycle -----------------------------------------------------------

const COLOR_GOOD = Color(0.23, 0.54, 0.23)
const COLOR_MID = Color(0.85, 0.6, 0.17)
const COLOR_BAD = Color(0.75, 0.22, 0.17)

func _ready():
    $Panel.add_to_group("ProvincePanel")
    GameClock.on_day_passed.connect(_on_day_passed)
    recruit_btn.pressed.connect(_on_recruit_button_pressed)
    build_factory_btn.pressed.connect(_on_build_factory_button_pressed)
    hide()

# Красит заливку ProgressBar в зависимости от значения (как в panel.gd)
func _set_stat_bar(bar: ProgressBar, value: float) -> void:
    bar.min_value = 0
    bar.max_value = 100
    bar.value = clamp(value, 0, 100)

    var color: Color = COLOR_BAD if value < 25 else (COLOR_MID if value < 60 else COLOR_GOOD)

    var sb = StyleBoxFlat.new()
    sb.bg_color = color
    sb.corner_radius_top_left = 3
    sb.corner_radius_top_right = 3
    sb.corner_radius_bottom_left = 3
    sb.corner_radius_bottom_right = 3
    bar.add_theme_stylebox_override("fill", sb)

func _on_day_passed(_date: Dictionary) -> void:
    if visible and settings.last_clicked_province_id != -1:
        var data = ProvinceRegistry.province_data.get(settings.last_clicked_province_id, {})
        update_info(data)

# --- info display ----------------------------------------------------------

func update_info(data: Dictionary):
    if data.has("id"):
        current_province_id = int(data["id"])
    var owner_name = data.get("owner", "unknown")
    owner_label.text = owner_name
    name_label.text  = data.get("name", "unknown")
    population_label.text = _format_population(int(data.get("population", 0)))
    factories_label.text = str(int(data.get("factories", 0))) + " factories"

    var happiness = round(data.get("happiness", 0))
    happiness_label.text = get_happiness(happiness)
    _set_stat_bar(happiness_bar, happiness)

    var flag_path = "res://assets/flags/" + owner_name + ".png"
    var can_act = owner_name == settings.active_country and data.get("against_occupation", "") == ""
    actions_section.visible = can_act
    actions_separator.visible = can_act

    var style = StyleBoxTexture.new()
    style.texture = load(flag_path)

    if can_act:
        $Panel.get_parent().custom_minimum_size.y = PANEL_HEIGHT_WITH_ACTIONS
        $Panel.size.y = PANEL_HEIGHT_WITH_ACTIONS
    else:
        $Panel.get_parent().custom_minimum_size.y = PANEL_HEIGHT_WITHOUT_ACTIONS
        $Panel.size.y = PANEL_HEIGHT_WITHOUT_ACTIONS

func _format_population(n: int) -> String:
    var s = str(n)
    var result = ""
    var count = 0
    for i in range(s.length() - 1, -1, -1):
        result = s[i] + result
        count += 1
        if count % 3 == 0 and i != 0:
            result = " " + result
    return result

func get_happiness(happiness) -> String:
    if happiness <= 30:
        return "😫 " + str(happiness)
    elif happiness <= 70:
        return "😐 " + str(happiness)
    else:
        return "😁 " + str(happiness)

# --- build factory -----------------------------------------------------------

func _on_build_factory_button_pressed() -> void:
    var p_id = settings.last_clicked_province_id
    var p_data = ProvinceRegistry.province_data.get(p_id, {})

    if p_data.get("against_occupation", "") != "":
        print("Нельзя строить в оккупированной провинции!")
        return

    var success = ProvinceRegistry.start_factory_construction(p_id, settings.active_country)
    if success:
        print("Строительство завода началось!")
        balance_label.balance_update()
    else:
        print("Недостаточно денег (нужно 1 000 000 💵)!")

# --- recruit (перенесено из recruite_button.gd) -----------------------------

func _on_recruit_button_pressed() -> void:
    var province_id = settings.last_clicked_province_id
    var local_pos = settings.local_mouse

    if province_id == -1:
        return

    var p_data = ProvinceRegistry.province_data.get(province_id, {})
    var pop = p_data.get("population", 0)
    var owner = p_data.get("owner", "")
    var balance = ProvinceRegistry.countries_data[owner]["balance"]

    recruit_slider_panel.open_menu(province_id, local_pos, pop, balance)

func update_army_info():
    var p_data = ProvinceRegistry.province_data.get(settings.last_clicked_province_id, {})
    update_info(p_data)
    if division_menu:
        division_menu.update_info(p_data)
