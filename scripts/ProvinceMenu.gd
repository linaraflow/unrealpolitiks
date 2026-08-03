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
@onready var ui_canvas_layer = get_node("/root/Game/CanvasLayer")

var current_province_id: int = -1

# --- lifecycle -----------------------------------------------------------

const COLOR_GOOD = Color(0.45, 0.85, 0.45)
const COLOR_MID = Color(0.85, 0.6, 0.17)
const COLOR_BAD = Color(0.75, 0.22, 0.17)

# Максимальный размер очереди строительства заводов (совпадает с ProvinceRegistry).
const MAX_QUEUE_SIZE := 5

var queue_toast: Label
var queue_toast_tween: Tween

func _ready():
    $Panel.add_to_group("ProvincePanel")
    GameClock.on_day_passed.connect(_on_day_passed)
    recruit_btn.pressed.connect(_on_recruit_button_pressed)
    build_factory_btn.pressed.connect(_on_build_factory_button_pressed)
    _setup_queue_toast()
    hide()

# Хоткеи R/W/E работают только если это меню сейчас реально открыто для
# провинции, которой владеет игрок (actions_section.visible уже считает это
# в update_info — совпадает с условием, при котором видны сами кнопки).
func _unhandled_input(event: InputEvent) -> void:
    if not visible or not actions_section.visible:
        return

    if Input.is_action_just_pressed("build_factory"):
        _on_build_factory_button_pressed()

    if Input.is_action_just_pressed("summon_troops"):
        _on_recruit_button_pressed()

    if Input.is_action_just_pressed("summon_max_troops_province"):
        _on_instant_max_recruit()

# Создаёт плавающую надпись, привязанную к низу ЭКРАНА (не панели), поэтому
# она не двигается и не масштабируется вместе с картой/камерой и не зависит
# от изменения размера панели ProvinceMenu.
func _setup_queue_toast() -> void:
    if ui_canvas_layer == null:
        return

    queue_toast = Label.new()
    queue_toast.name = "QueueToast"
    queue_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    queue_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    queue_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var toast_font = load("res://fonts/new_font_variation.tres")
    if toast_font:
        queue_toast.add_theme_font_override("font", toast_font)
    queue_toast.add_theme_font_size_override("font_size", 22)
    queue_toast.add_theme_color_override("font_outline_color", Color.BLACK)
    queue_toast.add_theme_constant_override("outline_size", 6)
    queue_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_toast.z_index = 100
    queue_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    queue_toast.offset_top = -180
    queue_toast.offset_bottom = -120
    queue_toast.offset_left = 20
    queue_toast.offset_right = -20
    queue_toast.modulate.a = 0.0
    queue_toast.visible = false
    queue_toast.process_mode = Node.PROCESS_MODE_ALWAYS
    ui_canvas_layer.add_child(queue_toast)

# Плавно показывает надпись внизу экрана заданным цветом, затем плавно прячет.
func show_queue_toast(text: String, color: Color = Color(1, 1, 1)) -> void:
    if queue_toast == null:
        return

    queue_toast.text = text
    queue_toast.add_theme_color_override("font_color", color)

    if queue_toast_tween and queue_toast_tween.is_valid():
        queue_toast_tween.kill()

    queue_toast.visible = true
    queue_toast.modulate.a = 0.0

    # Фиксированные целевые offset'ы (не зависят от текущего размера вьюпорта
    # и не «сползают» от повторных вызовов — в отличие от position).
    const FINAL_OFFSET_TOP := -180.0
    const FINAL_OFFSET_BOTTOM := -120.0
    const SLIDE_DISTANCE := 40.0

    queue_toast.offset_top = FINAL_OFFSET_TOP + SLIDE_DISTANCE
    queue_toast.offset_bottom = FINAL_OFFSET_BOTTOM + SLIDE_DISTANCE

    queue_toast_tween = create_tween()
    queue_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
    queue_toast_tween.set_parallel(true)
    queue_toast_tween.tween_property(queue_toast, "modulate:a", 1.0, 0.25)\
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    queue_toast_tween.tween_property(queue_toast, "offset_top", FINAL_OFFSET_TOP, 0.25)\
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    queue_toast_tween.tween_property(queue_toast, "offset_bottom", FINAL_OFFSET_BOTTOM, 0.25)\
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    queue_toast_tween.set_parallel(false)
    queue_toast_tween.tween_interval(1.6)
    queue_toast_tween.tween_property(queue_toast, "modulate:a", 0.0, 0.2)\
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    queue_toast_tween.tween_callback(func(): queue_toast.visible = false)

    if queue_toast.get_parent() == null and ui_canvas_layer != null and is_instance_valid(ui_canvas_layer):
        ui_canvas_layer.add_child(queue_toast)

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
    if data.get("owner", "unknown") == "sea":
        hide()
        return
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

    var queue: Array = p_data.get("factory_queue", [])
    if queue.size() >= MAX_QUEUE_SIZE:
        show_queue_toast("The construction queue is full", COLOR_BAD)
        return

    var success = ProvinceRegistry.start_factory_construction(p_id, settings.active_country)
    if success:
        balance_label.balance_update()
        var updated_queue: Array = ProvinceRegistry.province_data.get(p_id, {}).get("factory_queue", [])
        show_queue_toast("Factory construction %d/%d" % [updated_queue.size(), MAX_QUEUE_SIZE], COLOR_GOOD)
    else:
        var factory_cost: String = ProvinceRegistry._format_number(settings.factory_cost, ".")
        show_queue_toast("Not enough money (%s required)" % factory_cost, COLOR_BAD)

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

# --- instant max recruit (E) -------------------------------------------------
# Считает максимум войск, которые можно призвать прямо сейчас — ограничение
# по деньгам ИЛИ по 1% населения провинции, что меньше — и призывает сразу,
# минуя слайдер. Логика (цена за солдата, порог в 100 человек, сам вызов
# призыва, списание баланса, просадка happiness) продублирована из
# recruit_slider_panel.gd, чтобы результат был идентичен ручному призыву
# через слайдер на максимум.
func _on_instant_max_recruit() -> void:
    var province_id = settings.last_clicked_province_id
    var local_pos = settings.local_mouse

    if province_id == -1:
        return

    var p_data = ProvinceRegistry.province_data.get(province_id, {})
    var pop = p_data.get("population", 0)
    var owner = p_data.get("owner", "")
    var balance = ProvinceRegistry.countries_data[owner]["balance"]

    var pop_limit = int(pop * 0.01)
    var money_limit = int(balance / settings.COST_PER_SOLDIER)
    var amount = min(pop_limit, money_limit)

    if amount < 100:
        show_queue_toast("Not enough money or population to recruit (min. 100)", COLOR_BAD)
        return

    var cost = int(amount * settings.COST_PER_SOLDIER)
    var happiness_drain_per_1k = 0.1

    DivisionManager.recruit(province_id, local_pos, amount)
    ProvinceRegistry.countries_data[owner]["balance"] -= cost
    var happiness_drain = (float(amount) / 1000.0) * happiness_drain_per_1k
    var province_happiness = ProvinceRegistry.province_data[province_id]["happiness"]
    ProvinceRegistry.province_data[province_id]["happiness"] = max(0.0, province_happiness - happiness_drain)

    balance_label.balance_update()
    update_army_info()
    show_queue_toast("Recruited %d troops" % amount, COLOR_GOOD)

func update_army_info():
    var p_data = ProvinceRegistry.province_data.get(settings.last_clicked_province_id, {})
    update_info(p_data)
    if division_menu:
        division_menu.update_info(p_data)
