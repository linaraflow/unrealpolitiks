extends Control
# Settings window logic. Requires the SettingsManager autoload (see SettingsManager.gd).

# NOTE: these @onready paths still point at the original (Russian-named) scene
# nodes — I only translated the text shown to the player, not the node tree
# itself, since renaming nodes here wouldn't match your actual .tscn file.
# The tab titles are overridden to English below via set_tab_title(), so the
# player never sees the Russian node names.
@onready var tabs: TabContainer = $Panel/Root/Tabs
@onready var tab_graphics: VBoxContainer = $Panel/Root/Tabs/Graphics
@onready var tab_interface: VBoxContainer = $Panel/Root/Tabs/Interface
@onready var tab_gameplay: VBoxContainer = $Panel/Root/Tabs/Gameplay
@onready var tab_audio: VBoxContainer = $Panel/Root/Tabs/Sound
@onready var tab_controls: VBoxContainer = $Panel/Root/Tabs/Controls

var s: Node # ссылка на SettingsManager autoload

func _ready() -> void:
    s = get_node("/root/SettingsManager")
    _build_graphics_tab()
    _build_interface_tab()
    _build_gameplay_tab()
    _build_audio_tab()
    _build_controls_tab()

    tabs.set_tab_title(0, "Graphics")
    tabs.set_tab_title(1, "Interface")
    tabs.set_tab_title(2, "Gameplay")
    tabs.set_tab_title(3, "Sound")
    tabs.set_tab_title(4, "Controls")

# ---------------------------------------------------------------
# Row-building helpers
# ---------------------------------------------------------------

func _row(parent: Control, label_text: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.custom_minimum_size = Vector2(0, 36)
    row.add_theme_constant_override("separation", 16)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(260, 0)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(label)
    parent.add_child(row)
    return row

func _add_dropdown(parent: Control, label_text: String, options: Array, current_index: int, on_selected: Callable) -> OptionButton:
    var row := _row(parent, label_text)
    var opt := OptionButton.new()
    opt.custom_minimum_size = Vector2(220, 0)
    for o in options:
        opt.add_item(str(o))
    opt.selected = current_index
    opt.item_selected.connect(on_selected)
    row.add_child(opt)
    return opt

func _add_toggle(parent: Control, label_text: String, current_value: bool, on_toggled: Callable) -> CheckButton:
    var row := _row(parent, label_text)
    var chk := CheckButton.new()
    chk.button_pressed = current_value
    chk.toggled.connect(on_toggled)
    row.add_child(chk)
    return chk

func _add_slider(parent: Control, label_text: String, min_v: float, max_v: float, step: float, current_value: float, on_changed: Callable, as_percent: bool = false) -> HSlider:
    var row := _row(parent, label_text)
    var slider := HSlider.new()
    slider.min_value = min_v
    slider.max_value = max_v
    slider.step = step
    slider.value = current_value
    slider.custom_minimum_size = Vector2(180, 0)
    var value_label := Label.new()
    value_label.custom_minimum_size = Vector2(48, 0)
    value_label.text = _format_slider_value(current_value, as_percent)
    slider.value_changed.connect(func(v):
        value_label.text = _format_slider_value(v, as_percent)
        on_changed.call(v)
    )
    row.add_child(slider)
    row.add_child(value_label)
    return slider

func _format_slider_value(v: float, as_percent: bool) -> String:
    if as_percent:
        return "%d%%" % int(round(v * 100.0))
    return str(int(round(v)))

func _add_spinbox(parent: Control, label_text: String, min_v: int, max_v: int, step: int, current_value: int, suffix: String, on_changed: Callable) -> SpinBox:
    var row := _row(parent, label_text)
    var spin := SpinBox.new()
    spin.min_value = min_v
    spin.max_value = max_v
    spin.step = step
    spin.value = current_value
    spin.suffix = suffix
    spin.custom_minimum_size = Vector2(140, 0)
    spin.value_changed.connect(on_changed)
    row.add_child(spin)
    return spin

func _add_keybind_row(parent: Control, action_label: String, action_key: String) -> void:
    var row := _row(parent, action_label)
    var btn := Button.new()
    btn.text = s.keybinds.get(action_key, "?")
    btn.custom_minimum_size = Vector2(140, 0)
    btn.pressed.connect(func(): _start_rebind(btn, action_key))
    row.add_child(btn)

var _rebind_btn: Button = null
var _rebind_action_key: String = ""

func _start_rebind(btn: Button, action_key: String) -> void:
    btn.text = "Press a key..."
    _rebind_btn = btn
    _rebind_action_key = action_key

func _input(event: InputEvent) -> void:
    if _rebind_btn == null:
        return

    var bound_name := ""

    if event is InputEventKey and event.pressed and not event.echo:
        bound_name = OS.get_keycode_string(event.keycode)

    elif event is InputEventMouseButton and event.pressed:
        # Колёсико мыши не приходит как InputEventKey — это отдельный тип
        # события (InputEventMouseButton), поэтому раньше ребайндер его
        # просто игнорировал. Обрабатываем основные кнопки мыши и скролл здесь.
        match event.button_index:
            MOUSE_BUTTON_WHEEL_UP:
                bound_name = "Wheel Up"
            MOUSE_BUTTON_WHEEL_DOWN:
                bound_name = "Wheel Down"
            MOUSE_BUTTON_LEFT:
                bound_name = "Mouse Left"
            MOUSE_BUTTON_RIGHT:
                bound_name = "Mouse Right"
            MOUSE_BUTTON_MIDDLE:
                bound_name = "Mouse Middle"
            _:
                bound_name = "Mouse %d" % event.button_index

    if bound_name == "":
        return

    s.keybinds[_rebind_action_key] = bound_name
    s.sync_single_action(_rebind_action_key)
    _rebind_btn.text = bound_name
    get_viewport().set_input_as_handled()
    _rebind_btn = null
    _rebind_action_key = ""

# ---------------------------------------------------------------
# Tab: Graphics
# ---------------------------------------------------------------

func _build_graphics_tab() -> void:
    var res_labels := []
    for r in s.RESOLUTIONS:
        res_labels.append("%dx%d" % [r.x, r.y])
    _add_dropdown(tab_graphics, "Screen resolution", res_labels, s.resolution_index, func(idx):
        s.resolution_index = idx
        s._apply_display()
    )

    _add_dropdown(tab_graphics, "Window mode", ["Windowed", "Fullscreen", "Borderless window"], s.window_mode, func(idx):
        s.window_mode = idx
        s._apply_display()
    )

    _add_toggle(tab_graphics, "Vertical sync (VSync)", s.vsync_enabled, func(v):
        s.vsync_enabled = v
        s._apply_display()
    )

    _add_dropdown(tab_graphics, "FPS limit", ["30", "60", "120", "144", "Unlimited"], _fps_to_index(s.fps_limit), func(idx):
        s.fps_limit = _index_to_fps(idx)
        s._apply_display()
    )

func _fps_to_index(fps: int) -> int:
    match fps:
        30: return 0
        60: return 1
        120: return 2
        144: return 3
        _: return 4

func _index_to_fps(idx: int) -> int:
    match idx:
        0: return 30
        1: return 60
        2: return 120
        3: return 144
        _: return 0 # unlimited

# ---------------------------------------------------------------
# Tab: Interface
# ---------------------------------------------------------------

func _build_interface_tab() -> void:
    _add_slider(tab_interface, "UI scale", 0.8, 1.5, 0.05, s.ui_scale, func(v):
        s.ui_scale = v
        get_tree().root.content_scale_factor = v
    , true)

    _add_dropdown(tab_interface, "Interface language", ["Русский", "English", "Deutsch", "Français"], _lang_to_index(s.language), func(idx):
        s.language = _index_to_lang(idx)
        # hook up your Localization/TranslationServer reload here
    )

func _lang_to_index(lang: String) -> int:
    match lang:
        "ru": return 0
        "en": return 1
        "de": return 2
        "fr": return 3
        _: return 0

func _index_to_lang(idx: int) -> String:
    match idx:
        0: return "ru"
        1: return "en"
        2: return "de"
        3: return "fr"
        _: return "ru"

# ---------------------------------------------------------------
# Tab: Gameplay
# ---------------------------------------------------------------

func _build_gameplay_tab() -> void:
    _add_toggle(tab_gameplay, "Auto-pause on declaration of war", s.autopause_on_war, func(v):
        s.autopause_on_war = v
    )

    _add_spinbox(tab_gameplay, "Autosave (days, 0 = off)", 0, 365, 1, s.autosave_interval_days, " d", func(v):
        s.autosave_interval_days = int(v)
    )

# ---------------------------------------------------------------
# Tab: Sound
# ---------------------------------------------------------------

func _build_audio_tab() -> void:
    _add_slider(tab_audio, "Master volume", 0.0, 1.0, 0.01, s.volume_master, func(v):
        s.volume_master = v
        s._set_bus_volume("Master", v)
    , true)

    _add_slider(tab_audio, "Music", 0.0, 1.0, 0.01, s.volume_music, func(v):
        s.volume_music = v
        s._set_bus_volume("Music", v)
    , true)

    _add_slider(tab_audio, "Sound effects", 0.0, 1.0, 0.01, s.volume_effects, func(v):
        s.volume_effects = v
        s._set_bus_volume("Effects", v)
    , true)

# ---------------------------------------------------------------
# Tab: Controls
# ---------------------------------------------------------------

func _build_controls_tab() -> void:
    var keybind_title := Label.new()
    keybind_title.text = "Key bindings"
    keybind_title.add_theme_font_size_override("font_size", 16)
    tab_controls.add_child(keybind_title)

    for action_key in s.keybinds.keys():
        _add_keybind_row(tab_controls, _action_display_name(action_key), action_key)

func _action_display_name(key: String) -> String:
    var names := {
        "zoom_in": "Zoom in",
        "zoom_out": "Zoom out",
        "pause": "Pause",
        "build_factory": "Build factory",
        "summon_troops": "Summon troops",
        "summon_max_troops_province": "Summon max troops in province",
        "hide_ui": "Hide UI",
        "hide_all_divisions": "Hide all divisions",
    }
    return names.get(key, key)

# ---------------------------------------------------------------
# Bottom buttons
# ---------------------------------------------------------------

func _on_save_pressed() -> void:
    s.save_settings()
    s.apply_all()

func _on_reset_pressed() -> void:
    s.reset_to_defaults()
    get_tree().reload_current_scene()

func _on_back_pressed() -> void:
    queue_free() # if this scene is instanced as an overlay over the menu/pause screen
