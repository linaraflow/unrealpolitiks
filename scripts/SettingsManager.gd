extends Node
# Autoload singleton. Добавь в Project Settings -> Autoload как "SettingsManager".

signal settings_applied

const SAVE_PATH := "user://settings.cfg"

# ---------- Графика ----------
var resolution_index: int = 2          # индекс в RESOLUTIONS
var window_mode: int = 0               # 0=окно,1=полноэкран,2=безрамочное окно
var vsync_enabled: bool = true
var fps_limit: int = 60                # 0 = без лимита

## Логический холст, в котором живёт весь UI (все .tscn с якорями/офсетами
## подобраны под него). НЕ равен выбранному в настройках "разрешению" —
## иначе элементы с фиксированными пиксельными офсетами (SellMenu, панели
## заказа БПЛА/ракет и т.п.) начинают "уезжать" относительно элементов
## с процентными якорями при смене разрешения (см. баг с TopMenu на 2К).
const BASE_UI_RESOLUTION := Vector2i(1920, 1080)

const RESOLUTIONS := [
    Vector2i(1280, 720),
    Vector2i(1600, 900),
    Vector2i(1920, 1080),
    Vector2i(2560, 1440),
]

# ---------- Интерфейс ----------
var ui_scale: float = 1.0              # 0.8 .. 1.5
var language: String = "ru"            # "ru","en", ...

const SUPPORTED_LANGUAGES := ["en", "ru", "de", "fr"]
const DEFAULT_LANGUAGE := "en"

# ---------- Геймплей ----------
var autopause_on_war: bool = true
var autosave_interval_days: int = 30   # 0 = выключено

# ---------- Звук ----------
var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 1.0
var volume_ui: float = 1.0

# ---------- Управление ----------
var keybinds: Dictionary = {
    "zoom_in": "Wheel Up",
    "zoom_out": "Wheel Down",
    "pause": "Space",
    "build_factory": "R",
    "build_fortification": "T",
    "summon_troops": "W",
    "summon_max_troops_province": "E",
    "hide_ui": "Tab",
    "hide_all_divisions": "V",
    "hide_country_labels": "B",
}

func _ready() -> void:
    load_settings()
    apply_all()

func apply_all() -> void:
    _apply_display()
    _apply_audio()
    apply_language()
    sync_input_map()
    settings_applied.emit()

# ---------- Ввод (InputMap) ----------
# Здесь "keybinds" (просто текст для отображения на кнопках) конвертируется
# в реальные экшены Godot, которые можно проверять через Input.is_action_*().
# Экшены создаются программно, поэтому НЕ обязательно заводить их руками
# в Project Settings -> Input Map — это делает код ниже при старте игры.

func sync_input_map() -> void:
    for action_key in keybinds.keys():
        var event := _string_to_input_event(keybinds[action_key])
        if event == null:
            push_warning("Не удалось разобрать бинд '%s' для действия '%s'" % [keybinds[action_key], action_key])
            continue

        if not InputMap.has_action(action_key):
            InputMap.add_action(action_key)

        InputMap.action_erase_events(action_key)
        InputMap.action_add_event(action_key, event)

# Вызывай это сразу после того как игрок успешно переназначил клавишу в
# меню настроек (не дожидаясь нажатия "Сохранить"), чтобы новый бинд
# заработал в игре немедленно.
func sync_single_action(action_key: String) -> void:
    if not keybinds.has(action_key):
        return
    var event := _string_to_input_event(keybinds[action_key])
    if event == null:
        return
    if not InputMap.has_action(action_key):
        InputMap.add_action(action_key)
    InputMap.action_erase_events(action_key)
    InputMap.action_add_event(action_key, event)

func _string_to_input_event(bound_name: String) -> InputEvent:
    match bound_name:
        "Wheel Up":
            var e := InputEventMouseButton.new()
            e.button_index = MOUSE_BUTTON_WHEEL_UP
            return e
        "Wheel Down":
            var e := InputEventMouseButton.new()
            e.button_index = MOUSE_BUTTON_WHEEL_DOWN
            return e
        "Mouse Left":
            var e := InputEventMouseButton.new()
            e.button_index = MOUSE_BUTTON_LEFT
            return e
        "Mouse Right":
            var e := InputEventMouseButton.new()
            e.button_index = MOUSE_BUTTON_RIGHT
            return e
        "Mouse Middle":
            var e := InputEventMouseButton.new()
            e.button_index = MOUSE_BUTTON_MIDDLE
            return e
        _:
            # Обычная клавиша клавиатуры — превращаем строку ("R", "Tab",
            # "Space", ...) обратно в keycode тем же способом, каким
            # get_keycode_string() превращал keycode в строку при ребайнде.
            var keycode := OS.find_keycode_from_string(bound_name)
            if keycode == KEY_NONE:
                return null
            var e := InputEventKey.new()
            e.keycode = keycode
            return e

func _apply_display() -> void:
    var res: Vector2i = RESOLUTIONS[resolution_index]
    var win := get_tree().root
    var screen_idx := win.current_screen # фиксируем монитор ДО смены режима

    match window_mode:
        0: # Окно
            win.borderless = false
            win.mode = Window.MODE_WINDOWED
            win.current_screen = screen_idx
            # Физическое окно не может быть больше рабочей области монитора —
            # иначе часть окна окажется за пределами экрана.
            var screen_size := DisplayServer.screen_get_size(screen_idx)
            var window_size := Vector2i(min(res.x, screen_size.x), min(res.y, screen_size.y))
            win.size = window_size
            _center_window(window_size, screen_idx)
        1: # Полноэкранный (настоящий эксклюзивный fullscreen — реальная смена
            # видеорежима, со сворачиванием при alt-tab)
            win.borderless = false
            win.current_screen = screen_idx
            win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
        2: # Безрамочное окно (растянуто на экран, но остаётся обычным окном — быстрый alt-tab)
            win.mode = Window.MODE_WINDOWED
            win.borderless = true
            win.current_screen = screen_idx
            var screen_pos := DisplayServer.screen_get_position(screen_idx)
            var screen_size := DisplayServer.screen_get_size(screen_idx)
            win.size = screen_size
            win.position = screen_pos

    # ВАЖНО: content_scale_size — это ЛОГИЧЕСКИЙ холст UI, а не "внутреннее
    # разрешение под FPS". Он должен быть ПОСТОЯННЫМ (BASE_UI_RESOLUTION),
    # а не равным выбранному res — иначе при смене "разрешения" сам холст,
    # в котором живут все .tscn с якорями/офсетами, физически меняет размер,
    # и элементы с фиксированными пиксельными офсетами (SellMenu, панели
    # заказа БПЛА/ракет) начинают рассинхронизироваться с элементами на
    # процентных якорях (см. баг: TopMenu "не уменьшается" на 2К).
    #
    # CONTENT_SCALE_MODE_VIEWPORT сам растянет/сожмёт этот постоянный холст
    # под фактический размер окна (win.size = res) — именно это и даёт эффект
    # "выбрал 2К — картинка стала другого размера", без поломки раскладки UI.
    win.content_scale_size = BASE_UI_RESOLUTION
    win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
    win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

    DisplayServer.window_set_vsync_mode(
        DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
    )

    Engine.max_fps = fps_limit


func _center_window(size: Vector2i, screen_idx: int) -> void:
    var win := get_tree().root
    var screen_pos := DisplayServer.screen_get_position(screen_idx)
    var screen_size := DisplayServer.screen_get_size(screen_idx)
    var pos := screen_pos + (screen_size - size) / 2
    win.position = pos

func _apply_audio() -> void:
    _set_bus_volume("Master", volume_master)
    _set_bus_volume("Music", volume_music)
    _set_bus_volume("SFX", volume_sfx)
    _set_bus_volume("UI", volume_ui)

func _set_bus_volume(bus_name: String, linear: float) -> void:
    var idx := AudioServer.get_bus_index(bus_name)
    if idx == -1:
        return # шина не создана в проекте — создай в Audio tab или пропусти
    AudioServer.set_bus_volume_db(idx, linear_to_db(max(linear, 0.0001)))

func save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("graphics", "resolution_index", resolution_index)
    cfg.set_value("graphics", "window_mode", window_mode)
    cfg.set_value("graphics", "vsync_enabled", vsync_enabled)
    cfg.set_value("graphics", "fps_limit", fps_limit)

    cfg.set_value("interface", "ui_scale", ui_scale)
    cfg.set_value("interface", "language", language)

    cfg.set_value("gameplay", "autopause_on_war", autopause_on_war)
    cfg.set_value("gameplay", "autosave_interval_days", autosave_interval_days)

    cfg.set_value("audio", "volume_master", volume_master)
    cfg.set_value("audio", "volume_music", volume_music)
    cfg.set_value("audio", "volume_sfx", volume_sfx)
    cfg.set_value("audio", "volume_ui", volume_ui)

    cfg.set_value("controls", "keybinds", keybinds)

    cfg.save(SAVE_PATH)

func load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        # Файла ещё нет — это первый запуск. Пытаемся подхватить язык
        # операционной системы пользователя вместо жёстко заданного "ru".
        language = _detect_system_language()
        return

    resolution_index = cfg.get_value("graphics", "resolution_index", resolution_index)
    window_mode = cfg.get_value("graphics", "window_mode", window_mode)
    vsync_enabled = cfg.get_value("graphics", "vsync_enabled", vsync_enabled)
    fps_limit = cfg.get_value("graphics", "fps_limit", fps_limit)

    ui_scale = cfg.get_value("interface", "ui_scale", ui_scale)
    language = cfg.get_value("interface", "language", language)

    autopause_on_war = cfg.get_value("gameplay", "autopause_on_war", autopause_on_war)
    autosave_interval_days = cfg.get_value("gameplay", "autosave_interval_days", autosave_interval_days)

    volume_master = cfg.get_value("audio", "volume_master", volume_master)
    volume_music = cfg.get_value("audio", "volume_music", volume_music)
    volume_sfx = cfg.get_value("audio", "volume_sfx", volume_sfx)
    volume_ui = cfg.get_value("audio", "volume_ui", volume_ui)

    var loaded_keybinds: Dictionary = cfg.get_value("controls", "keybinds", keybinds)
    # Оставляем только те ключи, что реально существуют в дефолтном наборе —
    # так старые/удалённые действия (например, ранее сохранённый "open_map")
    # не будут воскресать из старого settings.cfg.
    var default_keys := keybinds.keys()
    keybinds = {}
    for key in default_keys:
        keybinds[key] = loaded_keybinds.get(key, _default_keybind(key))

## Определяет язык ОС пользователя (OS.get_locale() вернёт что-то вроде
## "ru_RU", "en_US", "de_DE", "fr_FR", "uk_UA" и т.п.). Берём только код
## языка (первые 2 буквы) и проверяем, есть ли он в списке поддерживаемых.
## Если нет — откатываемся на DEFAULT_LANGUAGE ("en").
func _detect_system_language() -> String:
    var locale := OS.get_locale_language() # напр. "ru", "en", "uk"
    if locale in SUPPORTED_LANGUAGES:
        return locale
    return DEFAULT_LANGUAGE

func apply_language() -> void:
    TranslationServer.set_locale(language)
    print(tr("TAB_GRAPHICS"))
    print("Locale: ", TranslationServer.get_locale())

func _default_keybind(action_key: String) -> String:
    var defaults := {
        "zoom_in": "Wheel Up", "zoom_out": "Wheel Down", "pause": "Space",
        "build_factory": "R", "build_fortification": "T", "summon_troops": "W",
        "summon_max_troops_province": "E", "hide_ui": "Tab",
        "hide_all_divisions": "V", "hide_country_labels": "B",
    }
    return defaults.get(action_key, "?")

func reset_to_defaults() -> void:
    var fresh = get_script().new()
    for prop in ["resolution_index","window_mode","vsync_enabled","fps_limit",
        "ui_scale","language",
        "autopause_on_war","autosave_interval_days",
        "volume_master","volume_music","volume_sfx","volume_ui",
        "keybinds"]:
        set(prop, fresh.get(prop))
    apply_all()
