extends PanelContainer

# ====== ЦВЕТА ======
var text_color_active = Color.WHITE
var text_color_inactive = Color(0.7, 0.7, 0.7)
var icon_color_inactive = Color("8e8e93")
var accent_color = Color("0a84ff")

# ====== ДАННЫЕ ПУНКТОВ (порядок должен совпадать с порядком кнопок в сцене) ======
var menu_items = ["Politics", "Economy", "Population"]

var selected_index = 0
var item_buttons: Array[Button] = []

var expanded = false
var list_full_height = 0
var is_animating = false

# ====== ССЫЛКИ НА НОДЫ (пути соответствуют твоей иерархии) ======
@onready var list_panel: PanelContainer = $VBoxContainer/ListPanel

@onready var item_politics: Button = $VBoxContainer/ListPanel/VBoxContainer/ItemPolitics
@onready var item_economy: Button = $VBoxContainer/ListPanel/VBoxContainer/ItemEconomy
@onready var item_population: Button = $VBoxContainer/ListPanel/VBoxContainer/ItemPopulation

@onready var dropdown_panel: PanelContainer = $VBoxContainer/DropdownPanel
@onready var dropdown_button: Button = $VBoxContainer/DropdownPanel/DropdownButton
@onready var dropdown_label: Label = $VBoxContainer/DropdownPanel/DropdownButton/MarginContainer/HBoxContainer/DropdownLabel
@onready var only_tick: CheckBox = $VBoxContainer/DropdownPanel/DropdownButton/MarginContainer/HBoxContainer/OnlyTick
@onready var arrow_icon: TextureRect = $VBoxContainer/DropdownPanel/DropdownButton/MarginContainer/HBoxContainer/ArrowIcon

# Заглушка на месте чекбокса для Politics: обычный Control с
# size_flags_horizontal = EXPAND_FILL, занимает то же место в HBoxContainer,
# чтобы при скрытии OnlyTick раскладка (например, положение ArrowIcon) не
# прыгала. Создаётся кодом в _ready(), в сцене её заводить не нужно.
var only_tick_spacer: Control

@onready var Map = get_node("/root/Game/Map")


func _ready():
    item_buttons = [item_politics, item_economy, item_population]

    for i in item_buttons.size():
        item_buttons[i].pressed.connect(_on_item_pressed.bind(i))

    dropdown_button.pressed.connect(_on_dropdown_pressed)
    only_tick.toggled.connect(_on_only_tick_toggled)

    # Создаём Control-заглушку рядом с OnlyTick в том же HBoxContainer
    only_tick_spacer = Control.new()
    only_tick_spacer.name = "OnlyTickSpacer"
    only_tick_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    only_tick_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    only_tick_spacer.visible = false
    var only_tick_parent = only_tick.get_parent()
    only_tick_parent.add_child(only_tick_spacer)
    only_tick_parent.move_child(only_tick_spacer, only_tick.get_index())

    arrow_icon.pivot_offset = arrow_icon.size / 2.0
    arrow_icon.resized.connect(func(): arrow_icon.pivot_offset = arrow_icon.size / 2.0)

    # Выставляем состояние по умолчанию (первый пункт выбран)
    _update_selection_visuals(selected_index)
    dropdown_label.text = menu_items[selected_index]

    # На Politics чекбокс "только своя страна" не имеет смысла — прячем его
    # и показываем на его месте Control-заглушку с Expand
    _set_only_tick_visible(selected_index != 0)

    call_deferred("_cache_list_height")


func _cache_list_height():
    await get_tree().process_frame
    list_full_height = list_panel.size.y
    list_panel.clip_contents = true

    if expanded:
        list_panel.custom_minimum_size.y = list_full_height
        list_panel.modulate.a = 1.0
    else:
        list_panel.custom_minimum_size.y = 0.0
        list_panel.modulate.a = 0.0


# ====== ВЫБОР ПУНКТА МЕНЮ ======
func _on_item_pressed(index: int):
    selected_index = index
    _update_selection_visuals(index)
    dropdown_label.text = menu_items[index]

    match index:
        0: # Politics — чекбокс тут не нужен, прячем и сбрасываем
            only_tick.set_pressed_no_signal(false)
            _set_only_tick_visible(false)
            Map.set_mode_only_own_country(false)
            Map.set_map_mode(Map.MapMode.NONE)
        1: # Economy
            _set_only_tick_visible(true)
            Map.set_map_mode(Map.MapMode.ECONOMY)
        2: # Population
            _set_only_tick_visible(true)
            Map.set_map_mode(Map.MapMode.POPULATION)


# ====== ЧЕКБОКС "ТОЛЬКО СВОЯ СТРАНА" ======
func _on_only_tick_toggled(pressed: bool):
    Map.set_mode_only_own_country(pressed)


## Показывает OnlyTick и прячет заглушку (или наоборот). Заглушка держит
## Expand-раскладку в HBoxContainer, пока чекбокса нет (режим Politics).
func _set_only_tick_visible(visible_: bool) -> void:
    only_tick.visible = visible_
    only_tick_spacer.visible = not visible_


## Полный сброс панели к дефолту — вызывается из Map.restart(). Выбирает
## Politics, прячет/сбрасывает чекбокс "только своя страна" и сворачивает
## список без анимации (на рестарте она не нужна).
func reset_to_default() -> void:
    selected_index = 0
    _update_selection_visuals(0)
    dropdown_label.text = menu_items[0]

    only_tick.set_pressed_no_signal(false)
    _set_only_tick_visible(false)
    Map.set_mode_only_own_country(false)
    Map.set_map_mode(Map.MapMode.NONE)

    if expanded:
        expanded = false
        is_animating = false
        arrow_icon.rotation_degrees = 0.0
        list_panel.custom_minimum_size.y = 0.0
        list_panel.modulate.a = 0.0


func _update_selection_visuals(index: int):
    for i in item_buttons.size():
        var margin = item_buttons[i].get_child(0)          # MarginContainer
        var hbox = margin.get_child(0)                     # HBoxContainer
        var icon = hbox.get_node("Icon")
        var label = hbox.get_node("Label")
        var check = hbox.get_node("Checkmark")

        var is_sel = (i == index)
        label.add_theme_color_override("font_color", text_color_active if is_sel else text_color_inactive)
        icon.modulate = Color.WHITE if is_sel else icon_color_inactive
        check.visible = is_sel
        dropdown_label.text = menu_items[index]


# ====== СВОРАЧИВАНИЕ / РАЗВОРАЧИВАНИЕ СПИСКА ======
func _on_dropdown_pressed():
    if is_animating:
        return
    is_animating = true
    expanded = !expanded

    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(arrow_icon, "rotation_degrees", 180.0 if expanded else 0.0, 0.25)

    if expanded:
        list_panel.custom_minimum_size.y = 0
        list_panel.modulate.a = 0.0
        tween.tween_property(list_panel, "custom_minimum_size:y", list_full_height, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.tween_property(list_panel, "modulate:a", 1.0, 0.2)
    else:
        tween.tween_property(list_panel, "custom_minimum_size:y", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
        tween.tween_property(list_panel, "modulate:a", 0.0, 0.15)

    tween.finished.connect(func(): is_animating = false)
