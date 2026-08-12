extends Control

## Цвет рамки выбранного слота сохранения.
const SELECTED_BORDER_COLOR := Color("c9a24a")
const DESELECTED_BORDER_COLOR := Color(0.35156286, 0.35156295, 0.35156265, 1)
const EMPTY_SLOT_TEXT := "EMPTY_SAVE_SLOT"

enum Mode { LOAD, SAVE }

## Тот же ресурс настроек, что использует SaveManager — берём active_country для имени слота.
var settings = preload("res://new_resource.tres")

## Отправляется, когда меню закрывается (по кнопке Back). Слушатель (например
## MainMenu, если меню было создано динамически) может сам сделать queue_free().
signal closed

@onready var _list_vbox: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer
@onready var _template: PanelContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/SaveContainer
@onready var _number_saves_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderContainer/NumberSaves
@onready var _title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderContainer/Label
@onready var _back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/BackButton
@onready var _action_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LoadButton
@onready var _action_button_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LoadButton/HBoxContainer/Label
@onready var _scroll: ScrollContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer

# slot -> { "container": PanelContainer, "style": StyleBoxFlat, "tick": TextureRect|null }
## Пустой слот хранится под ключом "" (реальные имена сохранений никогда не пустые).
var _entries: Dictionary = {}
var _selected_slot: String = ""
var _has_selection: bool = false
var _mode: Mode = Mode.LOAD


func _ready() -> void:
    _scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    # SaveContainer в сцене используется только как шаблон для дублирования —
    # убираем его из дерева, чтобы не показывать как отдельное (пустое) сохранение.
    _template.get_parent().remove_child(_template)

    _back_button.pressed.connect(_on_back_pressed)
    _action_button.pressed.connect(_on_action_pressed)

    # Меню сохранений открывают и во время паузы (из exit_menu) — иначе кнопки
    # внутри него тоже "замёрзнут" вместе с остальным деревом.
    process_mode = Node.PROCESS_MODE_ALWAYS

    # Скрыт по умолчанию — открывается через open_for_load()/open_for_save().
    hide()


## Открыть меню в режиме загрузки (как в главном меню): пустого слота нет,
## клик по сохранению выбирает его, кнопка снизу — "Load Save".
func open_for_load() -> void:
    _mode = Mode.LOAD
    _title_label.text = tr("SELECT_SAVE_TITLE")
    _action_button_label.text = tr("LOAD_SAVE_BTN")
    show()
    _populate_saves()


## Открыть меню в режиме сохранения (из паузы/exit_menu): первым всегда идёт
## пустой слот "Empty save slot" — если выбран он, кнопка "Save" создаёт новое
## сохранение. Клик по существующему сохранению выбирает его для перезаписи.
func open_for_save() -> void:
    _mode = Mode.SAVE
    _title_label.text = tr("SAVE_GAME_TITLE")
    _action_button_label.text = tr("SAVE_BTN")
    show()

    if settings.is_saving_disabled():
        # Хардкор: сохранение полностью запрещено — очищаем список и блокируем кнопку.
        for child in _list_vbox.get_children():
            child.queue_free()
        _entries.clear()
        _selected_slot = ""
        _has_selection = false
        _number_saves_label.text = "0"
        _title_label.text = "Saving is disabled on Hardcore"
        _action_button.disabled = true
        return

    _populate_saves()


func _populate_saves() -> void:
    for child in _list_vbox.get_children():
        child.queue_free()
    _entries.clear()
    _selected_slot = ""
    _has_selection = false

    if _mode == Mode.SAVE:
        _add_empty_slot_entry()

    var infos: Array = []
    for slot in SaveManager.list_saves():
        var info: Dictionary = SaveManager.get_save_info(slot)
        if info.is_empty():
            continue
        infos.append(info)

    # Сначала самые свежие сохранения.
    infos.sort_custom(func(a, b): return a.get("saved_at_unix", 0) > b.get("saved_at_unix", 0))

    for info in infos:
        _add_save_entry(info)

    _number_saves_label.text = str(infos.size())

    # Выбираем первый элемент списка по умолчанию — так же, как раньше
    # работал только режим загрузки: кнопка сразу активна.
    var first_slot: String = ""
    var has_any: bool = false
    if _mode == Mode.SAVE:
        has_any = true  # пустой слот есть всегда
    elif not infos.is_empty():
        first_slot = infos[0]["slot"]
        has_any = true

    _action_button.disabled = not has_any
    if has_any:
        _select_slot(first_slot)


# ─────────────────────────────────────────────────────────────────────────────
# ЭЛЕМЕНТЫ СПИСКА
# ─────────────────────────────────────────────────────────────────────────────

func _add_save_entry(info: Dictionary) -> void:
    var slot: String = info.get("slot", "")

    var container := _template.duplicate() as PanelContainer
    container.show()
    container.mouse_filter = Control.MOUSE_FILTER_STOP

    # StyleBoxFlat при duplicate() копируется по ссылке (тот же ресурс, что и у
    # шаблона) — делаем свою копию, чтобы менять border_color только у этого слота.
    var base_style: StyleBoxFlat = _template.get_theme_stylebox("panel")
    var style: StyleBoxFlat = base_style.duplicate()
    container.add_theme_stylebox_override("panel", style)

    var hbox: HBoxContainer = container.get_node("MarginContainer/HBoxContainer")
    var flag_rect: TextureRect = hbox.get_node("FlagRect")
    var country_name_label: Label = hbox.get_node("VBoxContainer/CountryName")
    var days_label: Label = hbox.get_node("VBoxContainer/HBoxContainer/DaysInPower")
    var gdp_label: Label = hbox.get_node("VBoxContainer/HBoxContainer/GDPLabel")
    var time_label: Label = hbox.get_node("TimeLabel")
    var tick_rect: TextureRect = hbox.get_node("TickRect")

    var country: String = info.get("country", "")
    country_name_label.text = tr(country.to_upper()) if country != "" else tr("UNKNOWN_COUNTRY")
    flag_rect.texture = _load_flag(country)
    days_label.text = tr("DAYS_INT_FMT") % int(info.get("days_in_power", 0))
    gdp_label.text = _format_money(float(info.get("gdp", 0.0)))
    time_label.text = _format_time_ago(int(info.get("saved_at_unix", 0)))
    tick_rect.visible = false

    container.gui_input.connect(_on_save_container_gui_input.bind(slot))

    _list_vbox.add_child(container)
    _entries[slot] = {
        "container": container,
        "style": style,
        "tick": tick_rect,
    }
    _ignore_mouse_recursive(container)


## Специальная первая карточка в режиме сохранения — при выборе и нажатии
## кнопки "Save" создаётся новое сохранение с именем "<страна>_<чч>_<мм>_<сс>".
func _add_empty_slot_entry() -> void:
    var container := _template.duplicate() as PanelContainer
    container.show()
    container.mouse_filter = Control.MOUSE_FILTER_STOP
    container.custom_minimum_size.y = 74

    var base_style: StyleBoxFlat = _template.get_theme_stylebox("panel")
    var style: StyleBoxFlat = base_style.duplicate()
    container.add_theme_stylebox_override("panel", style)

    var hbox: HBoxContainer = container.get_node("MarginContainer/HBoxContainer")
    var tick_rect: TextureRect = hbox.get_node("TickRect")

    # Прячем всё, кроме галочки выбора и одной надписи по центру.
    for child in hbox.get_children():
        if child != tick_rect:
            child.hide()

    var label := Label.new()
    label.text = tr(EMPTY_SLOT_TEXT)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hbox.add_child(label)
    hbox.move_child(label, 0)
    tick_rect.visible = false

    container.gui_input.connect(_on_save_container_gui_input.bind(""))

    _list_vbox.add_child(container)
    _list_vbox.move_child(container, 0)
    _entries[""] = {
        "container": container,
        "style": style,
        "tick": tick_rect,
    }
    _ignore_mouse_recursive(container)


## Дочерние Label/TextureRect по умолчанию имеют mouse_filter=STOP и перехватывают
## клик раньше, чем он доходит до gui_input самого контейнера — из-за этого клики
## по тексту/иконкам внутри карточки "не засчитывались". Пропускаем клик насквозь.
func _ignore_mouse_recursive(node: Node) -> void:
    for child in node.get_children():
        if child is Control:
            child.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ignore_mouse_recursive(child)


func _on_save_container_gui_input(event: InputEvent, slot: String) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _select_slot(slot)
        if _mode == Mode.LOAD and event.double_click:
            _on_action_pressed()


func _select_slot(slot: String) -> void:
    if not _entries.has(slot):
        return

    if _has_selection and _entries.has(_selected_slot):
        var prev: Dictionary = _entries[_selected_slot]
        (prev["style"] as StyleBoxFlat).border_color = DESELECTED_BORDER_COLOR
        (prev["tick"] as TextureRect).visible = false

    _selected_slot = slot
    _has_selection = true
    var cur: Dictionary = _entries[slot]
    (cur["style"] as StyleBoxFlat).border_color = SELECTED_BORDER_COLOR
    (cur["tick"] as TextureRect).visible = true

    _action_button.disabled = false


# ─────────────────────────────────────────────────────────────────────────────
# ДЕЙСТВИЯ
# ─────────────────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
    hide()
    closed.emit()


func _on_action_pressed() -> void:
    if not _has_selection:
        return
    if _mode == Mode.LOAD:
        SaveManager.request_load(_selected_slot)
    elif settings.is_saving_disabled():
        return
    elif _selected_slot == "":
        _create_new_save()
    else:
        SaveManager.save_game(_selected_slot)
        print("[SaveMenu] Сохранение перезаписано: ", _selected_slot)
        _populate_saves()


func _create_new_save() -> void:
    if settings.can_draw == false:
        return
    if settings.is_saving_disabled():
        return 
        
    var slot := _generate_new_slot_name()
    SaveManager.save_game(slot)
    print("[SaveMenu] Игра сохранена в новый слот: ", slot)
    hide()
    closed.emit()


## "<active_country>_<чч>_<мм>_<сс>", например "Niger_11_48_53".
func _generate_new_slot_name() -> String:
    var country: String = settings.active_country
    if country == "":
        country = "Unknown"
    var t := Time.get_time_dict_from_system()
    return "%s_%02d_%02d_%02d" % [country, t["hour"], t["minute"], t["second"]]


# ─────────────────────────────────────────────────────────────────────────────
# ФОРМАТИРОВАНИЕ
# ─────────────────────────────────────────────────────────────────────────────

func _load_flag(country: String) -> Texture2D:
    if country == "":
        return null
    var path := "res://assets/flags/%s.png" % country.capitalize()
    if ResourceLoader.exists(path):
        return load(path)
    return null


func _format_money(value: float) -> String:
    var sign := "-" if value < 0.0 else ""
    var v := absf(value)
    if v >= 1_000_000_000.0:
        return "%s$%.1fB" % [sign, v / 1_000_000_000.0]
    elif v >= 1_000_000.0:
        return "%s$%.1fM" % [sign, v / 1_000_000.0]
    elif v >= 1_000.0:
        return "%s$%.1fK" % [sign, v / 1_000.0]
    return "%s$%d" % [sign, int(v)]


func _format_time_ago(saved_at_unix: int) -> String:
    if saved_at_unix <= 0:
        return ""
    var diff: int = int(Time.get_unix_time_from_system()) - saved_at_unix
    if diff < 60:
        return tr("TIME_JUST_NOW")
    elif diff < 3600:
        return tr("TIME_MIN_AGO_FMT") % int(diff / 60.0)
    elif diff < 86400:
        return tr("TIME_HOURS_AGO_FMT") % int(diff / 3600.0)
    else:
        return tr("TIME_DAYS_AGO_FMT") % int(diff / 86400.0)
