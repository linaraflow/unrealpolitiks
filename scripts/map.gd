extends Sprite2D

@export var settings: Resource
@export var ui_menu: Control

var tech_image: Image
var data_image: Image
var data_texture: ImageTexture

var occup_image: Image
var occup_texture: ImageTexture

# НОВОЕ: текстура режима переговоров
var neg_image: Image
var neg_texture: ImageTexture

var _highlight_elapsed: float = -1.0

# ─── ЗЕЛЁНАЯ ВСПЫШКА "ЗАВОД ПОСТРОЕН" ────────────────────────────────────────
const FLASH_SLOTS: int = 8
var _game_time: float = 0.0
var _flash_ids: Array = []      # Array[Vector3], размер FLASH_SLOTS
var _flash_starts: Array = []   # Array[float],  размер FLASH_SLOTS
var _flash_next_slot: int = 0

# ─── КРАСНАЯ ВСПЫШКА "УДАР РАКЕТОЙ / БПЛА" ───────────────────────────────────
const RED_FLASH_SLOTS: int = 8
var _red_flash_ids: Array = []
var _red_flash_starts: Array = []
var _red_flash_next_slot: int = 0

var _neg_enemy: String = ""
var divisions_hidden: bool = false

# ─── РЕЖИМ ЗАПУСКА БПЛА ───────────────────────────────────────────────────────
var uav_mode: bool = false
var _uav_enemies: Array = []
var uav_image: Image
var uav_texture: ImageTexture


var distribute_mode: bool = false
var distribute_image: Image
var distribute_texture: ImageTexture

## Слой с линиями "столица -> цель" и бегущими по ним стрелочками (UAVMenu).
## Создаётся как child-нода в _ready(), координаты — как у province_centers.
var uav_lines_layer: Node2D

# ─── РЕЖИМ ЗАПУСКА РАКЕТЫ ─────────────────────────────────────────────────────
## Использует те же uav_image/uav_texture/uav_mode шейдерные параметры,
## что и режим БПЛА — одновременно активен только один из режимов,
## затемнение реализовано через общую функцию _apply_targeting_mask().
var missile_mode: bool = false
var _missile_enemies: Array = []

## Слой с дугообразной линией "столица -> цель" для MissileMenu.
var missile_lines_layer: Node2D

## Слой с цифрами "число заводов" на вражеских провинциях — показывается
## одновременно с затемнением карты в режимах БПЛА и ракеты (см.
## _apply_targeting_mask / _clear_targeting_mask).
var factory_labels_layer: Node2D

# Сохраняем локальные координаты последнего физического клика мыши
var _last_click_local_pos: Vector2 = Vector2.ZERO

@onready var CountryMenu          = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu")
@onready var CountryPanel         = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel")
@onready var ProvinceMenu         = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu")
@onready var DivisionMenu         = get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu")
@onready var FlagRect             = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel/HeaderRow/FlagRect")
@onready var ColorPanel           = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel/HeaderRow/FlagRect/ColorPanel")
@onready var recruit_slider_panel = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu/RecruitSliderPanel")
@onready var blue                 = get_node("/root/Game/CanvasLayer/BLUE")
@onready var date                 = get_node("/root/Game/CanvasLayer/TopMenu/TopPanel/DatePanel")
@onready var choose_map_panel     = get_node("/root/Game/CanvasLayer/TopMenu/ChooseMapPanel")

const IGNORE_IDS = [15307124, 0]

var path1: String = "res://province_adjacency.json"
var province_centers: Dictionary = {}

# ─── ОБВОДКА СТОЛИЧНОЙ ПРОВИНЦИИ ──────────────────────────────────────────────
## capital_texture: 256x256, индексируется так же, как data_texture/occup_texture
## (по младшим 16 битам p_id = mask.r, mask.g). alpha > 0.5 → это провинция-столица.
var capital_image: Image
var capital_texture: ImageTexture

## country -> p_id провинции, которая сейчас помечена как столица этой страны
## (нужно, чтобы при переносе столицы снять метку со старой провинции).
var capital_province_by_country: Dictionary = {}

# ─── РЕЖИМЫ КАРТЫ (экономика, население и т.п.) ──────────────────────────────
## mode_texture: 256x256, индексируется так же, как data_texture (по младшим
## 16 битам p_id = mask.r, mask.g). r-канал = нормализованное 0..1 значение
## (белый=0, оранжевый=1 в текущем шейдере), alpha>0.5 = провинция участвует.
enum MapMode { NONE, ECONOMY, POPULATION }
var current_map_mode: MapMode = MapMode.NONE

var mode_image: Image
var mode_texture: ImageTexture

## Кэш последнего известного максимума значения активного режима, по которому
## отнормирован mode_texture. Нужен, чтобы точечно обновлять один пиксель
## (_update_mode_pixel) без полного перестроения текстуры при каждом
## отдельном изменении (постройка завода, потери населения при ударе и т.п.).
var _mode_max_value: int = 1
var _mode_min_value: int = 0

## Если true — режим ECONOMY/POPULATION раскрашивает градиентом только
## провинции settings.active_country (min/max считаются в пределах своей
## территории), все остальные провинции остаются с обычным политическим
## цветом (alpha=0 в mode_texture). Переключается чекбоксом "только своя
## страна" в ChooseMapPanel.
var mode_only_own_country: bool = false

func _ready():
    child_entered_tree.connect(_on_child_entered_tree)
    
    var tech_tex = load("res://TechMap_alpha_06.png")
    tech_image = tech_tex.get_image()

    # НОВОЕ: больше не используем вручную нарисованную визуальную карту.
    # Вместо неё — сплошная заливка (цвет "моря"/фона), а вся суша красится
    # шейдером через data_texture по данным из provinces.json.
    var base_size = tech_image.get_size()
    var base_img = Image.create(base_size.x, base_size.y, false, Image.FORMAT_RGB8)
    base_img.fill(Color8(9, 20, 33))  # цвет моря/фона — подставь свой
    texture = ImageTexture.create_from_image(base_img)

    await get_tree().process_frame
    var path: Array = PathCache.find_path_cached(129, 134, settings.active_country)
    print("Путь 5 -> 21: ", path)

    # data_texture (владение)
    data_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    data_image.fill(Color(0, 0, 0, 0))
    data_texture = ImageTexture.create_from_image(data_image)

    # occup_texture (оккупация)
    occup_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    occup_image.fill(Color(0, 0, 0, 0))
    occup_texture = ImageTexture.create_from_image(occup_image)

    # neg_texture (режим переговоров)
    neg_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    neg_image.fill(Color(0, 0, 0, 0))
    neg_texture = ImageTexture.create_from_image(neg_image)

    # uav_texture (режим прицеливания: БПЛА и ракеты)
    uav_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    uav_image.fill(Color(0, 0, 0, 0))
    uav_texture = ImageTexture.create_from_image(uav_image)

    # Слой линий/стрелочек БПЛА — добавляем как child, чтобы использовать
    # ту же локальную систему координат, что и province_centers.
    uav_lines_layer = preload("res://scripts/uav_lines_layer.gd").new()
    uav_lines_layer.name = "UAVLinesLayer"
    add_child(uav_lines_layer)

    # Слой дугообразной линии для ракет (MissileMenu)
    missile_lines_layer = preload("res://scripts/missile_lines_layer.gd").new()
    missile_lines_layer.name = "MissileLinesLayer"
    add_child(missile_lines_layer)
    
    distribute_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    distribute_image.fill(Color(0, 0, 0, 0))
    distribute_texture = ImageTexture.create_from_image(distribute_image)
    material.set_shader_parameter("distribute_texture", distribute_texture)
    material.set_shader_parameter("distribute_mode", false)

    # Слой цифр "число заводов" на вражеских провинциях (режимы БПЛА/ракеты)
    factory_labels_layer = preload("res://scripts/province_factory_labels_layer.gd").new()
    factory_labels_layer.name = "FactoryLabelsLayer"
    add_child(factory_labels_layer)

    # capital_texture (обводка столичных провинций)
    capital_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    capital_image.fill(Color(0, 0, 0, 0))
    capital_texture = ImageTexture.create_from_image(capital_image)

    # mode_texture (режимы карты: экономика и т.п.)
    mode_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    mode_image.fill(Color(0, 0, 0, 0))
    mode_texture = ImageTexture.create_from_image(mode_image)

    material.set_shader_parameter("tech_map",      tech_tex)
    material.set_shader_parameter("data_texture",  data_texture)
    material.set_shader_parameter("occup_texture", occup_texture)
    material.set_shader_parameter("neg_texture",   neg_texture)
    material.set_shader_parameter("uav_texture",   uav_texture)
    material.set_shader_parameter("capital_texture", capital_texture)
    material.set_shader_parameter("mode_texture",  mode_texture)
    material.set_shader_parameter("map_mode_active", false)
    material.set_shader_parameter("country_colors", ProvinceRegistry.country_colors)

    # Буфер вспышек "завод построен" — изначально все слоты пустые (id 0,0,0)
    _flash_ids.resize(FLASH_SLOTS)
    _flash_starts.resize(FLASH_SLOTS)
    for i in FLASH_SLOTS:
        _flash_ids[i] = Vector3.ZERO
        _flash_starts[i] = -1000.0
    material.set_shader_parameter("flash_ids", _flash_ids)
    material.set_shader_parameter("flash_starts", _flash_starts)
    material.set_shader_parameter("game_time", 0.0)
    
    # Буфер красных вспышек "удар ракетой/БПЛА" — изначально все слоты пустые
    _red_flash_ids.resize(RED_FLASH_SLOTS)
    _red_flash_starts.resize(RED_FLASH_SLOTS)
    for i in RED_FLASH_SLOTS:
        _red_flash_ids[i] = Vector3.ZERO
        _red_flash_starts[i] = -1000.0
    material.set_shader_parameter("red_flash_ids", _red_flash_ids)
    material.set_shader_parameter("red_flash_starts", _red_flash_starts)

    # НОВОЕ: разово красим ВСЕ ~10000 провинций владельцами из provinces.json.
    # Пишем прямо в Image и обновляем текстуру ОДИН раз в конце —
    # если вместо этого дергать capture_province() in цикле, это даст
    # 10000 сигналов province_captured и 10000 отдельных data_texture.update(),
    # что будет заметно тормозить старт игры.
    _paint_all_provinces_from_data()

    # Обводка столичных провинций: заполняем capital_texture по текущим
    # "capital" всех стран из countries_data (один проход, без сигналов).
    _init_capital_borders()

    ProvinceRegistry.province_captured.connect(_on_province_captured)
    ProvinceRegistry.province_army_changed.connect(_on_province_army_changed)
    ProvinceRegistry.province_occupied.connect(_on_province_occupied)
    ProvinceRegistry.country_color_changed.connect(_on_country_color_changed)
    ProvinceRegistry.capital_changed.connect(_on_capital_changed)
    ProvinceRegistry.factory_built.connect(_on_factory_built)
    ProvinceRegistry.factory_destroyed.connect(_on_factory_destroyed)
    ProvinceRegistry.missile_strike_landed.connect(_on_missile_strike_landed)   # <-- НОВОЕ
    ProvinceRegistry.uav_strike_landed.connect(_on_uav_strike_landed)

    CountryMenu.visible = false

    DivisionManager.map_node = self
    province_centers = settings.province_centers

    CombatManager.battle_ended.connect(_on_battle_ended)

    var tex_size = texture.get_size()
    material.set_shader_parameter("texture_size", tex_size)

    var cam = get_viewport().get_camera_2d()
    if cam:
        material.set_shader_parameter("camera_zoom", cam.zoom.x)
        material.set_shader_parameter("camera_pos", cam.position)
        cam.zoom_changed.connect(func(new_zoom):
            material.set_shader_parameter("camera_zoom", new_zoom.x)
        )

    _restore_occupation_from_data()

func _process(delta: float) -> void:
    if _highlight_elapsed >= 0.0:
        _highlight_elapsed += delta
        material.set_shader_parameter("highlight_time", _highlight_elapsed)

    _game_time += delta
    material.set_shader_parameter("game_time", _game_time)


func _input(event: InputEvent):
    if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_V and not settings.negotiation_mode:
        divisions_hidden = not divisions_hidden
        _update_divisions_visibility()
        return

    # Enter — сделать последнюю нажатую провинцию столицей её владельца
    if event is InputEventKey and event.pressed and not event.is_echo() \
            and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
        var p_id = settings.last_clicked_province_id
        var owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")
        if owner != "":
            ProvinceRegistry.set_capital(owner, p_id)
        else:
            print("[Map] Enter: у последней нажатой провинции нет владельца")
        return

    if not event is InputEventMouseButton or event.pressed:
        return
    if get_viewport().gui_get_hovered_control() != null:
        return

    # ВАЖНО: это срабатывает на КАЖДОЕ отпускание ЛКМ на карте — в том числе
    # и в момент, когда ты отпускаешь мышь после перетаскивания selection box.
    # Раньше здесь выделение чистилось безусловно, без проверки Shift, и это
    # стирало результат selection_box.gd ДО того, как он успевал добавить туда
    # новых юнитов (т.к. _input() выполняется раньше _unhandled_input()).
    # Из-за этого стакинг через Shift не работал никогда — сброс происходил
    # тут, а не в selection_box.gd. Добавляем ту же проверку Shift, что и там.
    if event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_SHIFT) and not distribute_mode:
        SelectionManager.clear_selection()

    var coords = _get_map_coords()
    var px = tech_image.get_pixelv(coords)
    var p_id = _px_to_id(px)
    settings.last_clicked_province_color = Color(px.r, px.g, px.b)


    if p_id in IGNORE_IDS:
        return

    # НОВОЕ: в режиме переговоров блокируем клики по затемнённым провинциям
    if settings.negotiation_mode and not _is_province_visible_in_negotiation(p_id):
        return

    # В режиме прицеливания (БПЛА или ракета) блокируем клики по затемнённым провинциям
    if uav_mode and not _is_targeting_visible(p_id, _uav_enemies):
        return
    if missile_mode and not _is_targeting_visible(p_id, _missile_enemies):
        return
    if distribute_mode and not _is_own_province(p_id):
        return
    # Запоминаем точную локальную позицию клика
    _last_click_local_pos = get_local_mouse_position()

    var province_info = ProvinceRegistry.province_data.get(p_id, {})
    var current_owner = province_info.get("owner", "")

    print("Clicked Province ID: ", p_id, " Owner: ", current_owner,
          " Occupant: ", ProvinceRegistry.get_occupant(p_id),
           "  coords:", get_local_mouse_position())

    if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
        recruit_slider_panel.hide()
        ColorPanel.hide()
        
    if event.button_index == MOUSE_BUTTON_LEFT:
        _handle_left_click(p_id, px, province_info, current_owner)
    elif event.button_index == MOUSE_BUTTON_RIGHT:
        _handle_right_click(p_id, px, province_info, current_owner)


func _handle_left_click(p_id, px, province_info, current_owner):
    # РЕЖИМ ЗАПУСКА БПЛА: передаём клик в UAVMenu и выходим
    if uav_mode:
        get_node("/root/Game/CanvasLayer/UAVMenu").on_province_clicked(p_id)
        return

    # РЕЖИМ ЗАПУСКА РАКЕТЫ: передаём клик в MissileMenu и выходим
    if missile_mode:
        get_node("/root/Game/CanvasLayer/MissileMenu").on_province_clicked(p_id)
        return
    
    if distribute_mode:
        get_node("/root/Game/CanvasLayer/ControlDivisionsMenu").on_distribute_province_clicked(p_id)
        return
    
    # РЕЖИМ ПЕРЕГОВОРОВ: передаём клик в меню и выходим
    if settings.negotiation_mode:
        get_node("/root/Game/CanvasLayer/NegotiationMenu").on_province_clicked(p_id)
        return
    
    var local_mouse = province_centers.get(p_id, to_local(get_global_mouse_position()))
    settings.local_mouse = local_mouse
    settings.last_clicked_province_id = p_id
    _select_province(px)
    ProvinceMenu.update_info(province_info)
    CountryPanel.show()
    CountryPanel.update_info()
    FlagRect.update()
    if settings.negotiation_mode == false:
        CountryPanel.update_info()
        DivisionMenu.update_info(province_info)

        if not settings.can_draw:
            get_node("../CanvasLayer/BLUE").text = current_owner if current_owner != "sea" else "Choose Country"
            CountryMenu.show()
            return
        elif current_owner != "sea":
            ProvinceMenu.show()


func _handle_right_click(p_id, px, province_info, current_owner):
    print("ПКМ на провинции: ", p_id, " owner: ", current_owner)
    print("Есть выделенная дивизия: ", SelectionManager.has_selection())
    
    if distribute_mode:
        return

    if SelectionManager.has_selection():
        var target_pos = province_centers.get(p_id, to_local(get_global_mouse_position()))
        if SelectionManager.can_move_to(p_id, current_owner):
            SelectionManager.move_selected_to(p_id, target_pos)
            settings.last_clicked_province_id = p_id

    if not settings.can_draw:
        return
    if current_owner == "":
        return

    settings.last_clicked_province_id = p_id
    _select_province(px)
    if settings.negotiation_mode == false:
        DivisionMenu.update_info(province_info)
    ProvinceMenu.update_info(province_info)
    CountryPanel.update_info()
    FlagRect.update()


# ─── РЕЖИМ ПЕРЕГОВОРОВ ────────────────────────────────────────────────────────

## Включить режим переговоров с указанным врагом.
## Вызывать из negotiation_menu.gd или panel.gd.
func enter_negotiation_mode(enemy: String) -> void:
    settings.negotiation_mode = true
    _neg_enemy = enemy

    # Заполняем neg_texture: пиксель светлый = провинция видима
    neg_image.fill(Color(0, 0, 0, 0))  # сначала всё чёрное

    for key in ProvinceRegistry.province_data:
        var p = ProvinceRegistry.province_data[key]
        var owner = p.get("owner", "")
        if owner == settings.active_country or owner == enemy:
            var p_id = int(key)
            var r = p_id & 0xFF
            var g = (p_id >> 8) & 0xFF
            neg_image.set_pixel(r, g, Color(1, 0, 0, 1))

    neg_texture.update(neg_image)
    material.set_shader_parameter("negotiation_mode", true)
    print("[Map] Режим переговоров с: ", enemy)


## Выключить режим переговоров и вернуть карту к нормальному виду.
func exit_negotiation_mode() -> void:
    settings.negotiation_mode = false
    _neg_enemy = ""
    neg_image.fill(Color(0, 0, 0, 0))
    neg_texture.update(neg_image)
    material.set_shader_parameter("negotiation_mode", false)
    print("[Map] Режим переговоров завершён")


## Проверить видима ли провинция в режиме переговоров (для блокировки кликов).
func _is_province_visible_in_negotiation(p_id: int) -> bool:
    var p = ProvinceRegistry.province_data.get(p_id, {})
    var owner = p.get("owner", "")
    return owner == settings.active_country or owner == _neg_enemy


# ─── РЕЖИМ ЗАПУСКА БПЛА / РАКЕТ (универсальное затемнение карты) ─────────────

## Включить режим прицеливания БПЛА. enemies — список стран-противников,
## чьи провинции остаются видимыми (все остальные затемняются).
## Вызывать из uav_menu.gd (аналогично enter_negotiation_mode).
func enter_uav_mode(enemies: Array) -> void:
    uav_mode = true
    _uav_enemies = enemies
    _apply_targeting_mask(enemies)
    print("[Map] Режим запуска БПЛА, противников: ", enemies.size())


## Выключить режим прицеливания БПЛА и вернуть карту к нормальному виду.
func exit_uav_mode() -> void:
    uav_mode = false
    _uav_enemies = []
    _clear_targeting_mask()
    clear_uav_target_lines()
    print("[Map] Режим запуска БПЛА завершён")


## Включить режим прицеливания РАКЕТЫ. Затемнение работает точно так же,
## как в enter_uav_mode — через общую функцию _apply_targeting_mask().
## Вызывать из missile_menu.gd при нажатии LaunchButton в PanelMissileOrder.
func enter_missile_mode(enemies: Array) -> void:
    missile_mode = true
    _missile_enemies = enemies
    _apply_targeting_mask(enemies)
    print("[Map] Режим запуска ракеты, противников: ", enemies.size())


## Выключить режим прицеливания ракеты и вернуть карту к нормальному виду.
func exit_missile_mode() -> void:
    missile_mode = false
    _missile_enemies = []
    _clear_targeting_mask()
    clear_missile_target_line()
    print("[Map] Режим запуска ракеты завершён")


## УНИВЕРСАЛЬНАЯ функция затемнения карты: видимыми остаются только
## провинции своей страны и провинции из списка enemies.
## Используется и для БПЛА (enter_uav_mode), и для ракет (enter_missile_mode) —
## оба режима переиспользуют один и тот же uav_texture/uav_mode шейдерный
## параметр, так как одновременно активен только один из двух режимов.
func _apply_targeting_mask(enemies: Array) -> void:
    uav_image.fill(Color(0, 0, 0, 0))  # сначала всё затемнено

    for key in ProvinceRegistry.province_data:
        var p = ProvinceRegistry.province_data[key]
        var owner = p.get("owner", "")
        if owner == settings.active_country or owner in enemies:
            var p_id = int(key)
            var r = p_id & 0xFF
            var g = (p_id >> 8) & 0xFF
            uav_image.set_pixel(r, g, Color(1, 0, 0, 1))

    uav_texture.update(uav_image)
    material.set_shader_parameter("uav_mode", true)

    _show_enemy_factory_labels(enemies)
    

## Реакция на удар ракетой — подсвечиваем провинцию красным.
func _on_missile_strike_landed(p_id: int) -> void:
    _flash_province_red(p_id)


## Реакция на удар БПЛА — подсвечиваем провинцию красным.
## destroy_factory() в ProvinceRegistry уменьшает и фабрики, и население этой
## провинции, поэтому если сейчас активен режим "население" — обновляем цвет.
func _on_uav_strike_landed(p_id: int) -> void:
    if current_map_mode == MapMode.POPULATION:
        _update_mode_pixel(p_id)
    _flash_province_red(p_id)
    
## Запускает плавную красную вспышку на провинции p_id
## (аналог _flash_province_green, но со своим кольцевым буфером
## red_flash_ids/red_flash_starts, чтобы не конфликтовать с зелёной вспышкой
## завода — у них разные цвета и потенциально разное время срабатывания).
func _flash_province_red(p_id: int) -> void:
    var r = (p_id & 0xFF) / 255.0
    var g = ((p_id >> 8) & 0xFF) / 255.0
    var b = ((p_id >> 16) & 0xFF) / 255.0

    var slot = _red_flash_next_slot
    _red_flash_next_slot = (_red_flash_next_slot + 1) % RED_FLASH_SLOTS

    _red_flash_ids[slot] = Vector3(r, g, b)
    _red_flash_starts[slot] = _game_time

    material.set_shader_parameter("red_flash_ids", _red_flash_ids)
    material.set_shader_parameter("red_flash_starts", _red_flash_starts)


## УНИВЕРСАЛЬНАЯ функция снятия затемнения карты (общая для БПЛА и ракет).
func _clear_targeting_mask() -> void:
    uav_image.fill(Color(0, 0, 0, 0))
    uav_texture.update(uav_image)
    material.set_shader_parameter("uav_mode", false)
    _clear_enemy_factory_labels()


## Собирает подписи "число заводов" по всем видимым (не затемнённым)
## вражеским провинциям и отправляет их в factory_labels_layer.
## Провинции без заводов (0) не подписываются, чтобы не захламлять карту.
func _show_enemy_factory_labels(enemies: Array) -> void:
    var entries: Array = []
    for key in ProvinceRegistry.province_data:
        var p_id = int(key)
        if p_id in IGNORE_IDS:
            continue
        var p = ProvinceRegistry.province_data[key]
        var owner = p.get("owner", "")
        if not (owner in enemies):
            continue

        var factories = int(p.get("factories", 0))
        if factories <= 0:
            continue
        if not province_centers.has(p_id):
            continue

        entries.append({"p_id": p_id, "pos": province_centers[p_id], "count": factories})

    if factory_labels_layer:
        factory_labels_layer.set_labels(entries)


## Убирает все подписи "число заводов" (выход из режима прицеливания).
func _clear_enemy_factory_labels() -> void:
    if factory_labels_layer:
        factory_labels_layer.clear_labels()


## Проверить видима ли провинция в режиме прицеливания (БПЛА или ракета).
func _is_targeting_visible(p_id: int, enemies: Array) -> bool:
    var p = ProvinceRegistry.province_data.get(p_id, {})
    var owner = p.get("owner", "")
    return owner == settings.active_country or owner in enemies
  
  
func _is_own_province(p_id: int) -> bool:
    return ProvinceRegistry.province_data.get(p_id, {}).get("owner", "") == settings.active_country

func enter_distribute_mode() -> void:
    distribute_mode = true
    distribute_image.fill(Color(0, 0, 0, 0))
    distribute_texture.update(distribute_image)
    material.set_shader_parameter("distribute_mode", true)

func exit_distribute_mode() -> void:
    distribute_mode = false
    distribute_image.fill(Color(0, 0, 0, 0))
    distribute_texture.update(distribute_image)
    material.set_shader_parameter("distribute_mode", false)

## Подсвечивает/снимает подсветку провинции, выбранной в DistributePanel.
func set_distribute_province_highlighted(p_id: int, highlighted: bool) -> void:
    var r = p_id & 0xFF
    var g = (p_id >> 8) & 0xFF
    distribute_image.set_pixel(r, g, Color(1, 0, 0, 1) if highlighted else Color(0, 0, 0, 0))
    distribute_texture.update(distribute_image)


## Обновляет линии "столица -> выбранная вражеская провинция" с бегущими
## по ним стрелочками. Вызывается из uav_menu.gd при изменении списка целей.
## from_pos/target_positions — локальные координаты Map (как в province_centers).
func set_uav_target_lines(from_pos: Vector2, target_positions: Array) -> void:
    if uav_lines_layer:
        uav_lines_layer.set_lines(from_pos, target_positions)


## Убирает все линии целей БПЛА (закрытие меню / выход из режима).
func clear_uav_target_lines() -> void:
    if uav_lines_layer:
        uav_lines_layer.clear_lines()


## Обновляет дугообразную линию "столица -> выбранная вражеская провинция"
## для MissileMenu. from_pos/to_pos — локальные координаты Map.
func set_missile_target_line(from_pos: Vector2, to_pos: Vector2) -> void:
    if missile_lines_layer:
        missile_lines_layer.set_line(from_pos, to_pos)


## Убирает линию цели ракеты (закрытие меню / выход из режима).
func clear_missile_target_line() -> void:
    if missile_lines_layer:
        missile_lines_layer.clear_line()


# ─── СИГНАЛЫ ──────────────────────────────────────────────────────────────────

func _on_province_captured(p_id: int, new_owner: String):
    var r = p_id & 0xFF
    var g = (p_id >> 8) & 0xFF
    var idx = ProvinceRegistry.country_index.get(new_owner, 0)
    data_image.set_pixel(r, g, Color(idx / 255.0, 0, 0, 1))
    data_texture.update(data_image)

    if ui_menu and ProvinceRegistry.province_data.has(p_id):
        ui_menu.update_info(ProvinceRegistry.province_data[p_id])


func _on_province_occupied(p_id: int, occupier: String):
    print("=== ON_PROVINCE_OCCUPIED CALLED === p_id:", p_id, " occupier:", occupier)

    var r = p_id & 0xFF
    var g = (p_id >> 8) & 0xFF

    if occupier == "":
        occup_image.set_pixel(r, g, Color(0, 0, 0, 0))
    else:
        var idx = ProvinceRegistry.country_index.get(occupier, 0)
        occup_image.set_pixel(r, g, Color(idx / 255.0, 0, 0, 1))

    occup_texture.update(occup_image)

    CountryPanel.update_info()
    FlagRect.update()


func _on_province_army_changed(changed_p_id: int, division = null):
    if changed_p_id == settings.last_clicked_province_id:
        var p_data = ProvinceRegistry.province_data.get(changed_p_id, {})
        DivisionMenu.update_info(p_data)
    CountryPanel.update_info()
    FlagRect.update()


func _on_battle_ended(province_id: int, winner: String) -> void:
    if winner == "":
        return

    var current_owner = ProvinceRegistry.province_data.get(province_id, {}).get("owner", "")

    print("=== BATTLE ENDED === province:", province_id, " winner:", winner, " owner:", current_owner)

    if current_owner != winner:
        ProvinceRegistry.occupy_province(province_id, winner)
    
    print("=== OCCUPY CALLED ===")

    CountryPanel.update_info()
    FlagRect.update()


# ─── ВСПОМОГАТЕЛЬНЫЕ ─────────────────────────────────────────────────────────

func _clear_occup_pixel(p_id: int) -> void:
    var r = p_id & 0xFF
    var g = (p_id >> 8) & 0xFF
    occup_image.set_pixel(r, g, Color(0, 0, 0, 0))
    occup_texture.update(occup_image)


## Красит все провинции их владельцами из province_data за один проход.
## В отличие от вызова capture_province()/occupy_province() в цикле,
## тут НЕТ сигналов и НЕТ texture.update() на каждую провинцию —
## только один update() в самом конце.
## Для ~10000 провинций это разница
## между "мгновенно" и "заметная пауза/лаги при старте".
func _paint_all_provinces_from_data() -> void:
    for key in ProvinceRegistry.province_data:
        var p_id = int(key)
        if p_id in IGNORE_IDS:
            continue

        var p = ProvinceRegistry.province_data[key]
        var owner = p.get("owner", "")

        # Морские провинции (owner == "sea") намеренно НЕ пишем в data_texture:
        # пиксель остаётся с alpha=0, поэтому шейдер покажет фоновый цвет
        # (цвет моря) вместо country_colors, и границы тоже не будут
        # рисоваться относительно них (см. game.gdshader: own_is_sea/n*_is_sea).
        if owner == ProvinceRegistry.SEA_OWNER:
            ProvinceRegistry.province_owners[p_id] = owner
            continue

        # Пустой owner ("" — ничья/неосвоенная земля) красим индексом 0.
        # Убедись, что country_colors[0] в countries.json — это нужный
        # тебе нейтральный цвет, а не случайно первая настоящая страна.
        var idx = ProvinceRegistry.country_index.get(owner, 0)

        var r = p_id & 0xFF
        var g = (p_id >> 8) & 0xFF
        data_image.set_pixel(r, g, Color(idx / 255.0, 0, 0, 1))

        # province_owners нужен для ProvinceRegistry.capture() (переход всех
        # провинций страны), поэтому синхронизируем и его — без сигналов.
        ProvinceRegistry.province_owners[p_id] = owner

    data_texture.update(data_image)


func _restore_occupation_from_data() -> void:
    for key in ProvinceRegistry.province_data:
        var p = ProvinceRegistry.province_data[key]
        var occ = p.get("against_occupation", "")
        if occ != "":
            var p_id = int(key)
            var r = p_id & 0xFF
            var g = (p_id >> 8) & 0xFF
            var idx = ProvinceRegistry.country_index.get(occ, 0)
            occup_image.set_pixel(r, g, Color(idx / 255.0, 0, 0, 1))
    occup_texture.update(occup_image)

# ─── КАРТА ────────────────────────────────────────────────────────────────────

func _get_map_coords() -> Vector2i:
    var local_pos = get_local_mouse_position()
    var tex_size = texture.get_size()
    if centered:
        local_pos += tex_size / 2.0
    var img_size = tech_image.get_size()
    var coords = Vector2i(local_pos)
    return coords.clamp(Vector2i.ZERO, img_size - Vector2i(1, 1))


func _px_to_id(px: Color) -> int:
    var r = int(px.r * 255)
    var g = int(px.g * 255)
    var b = int(px.b * 255)
    return r | (g << 8) | (b << 16)


func _select_province(px: Color) -> void:
    material.set_shader_parameter("selected_province_color", Vector3(px.r, px.g, px.b))
    material.set_shader_parameter("highlight_time", 0.0)
    _highlight_elapsed = 0.0


## Реакция на ProvinceRegistry.factory_built — подсвечиваем провинцию
## своей страны зелёным, когда в ней достроился завод.
func _on_factory_built(p_id: int, country: String) -> void:
    if current_map_mode == MapMode.ECONOMY:
        _update_mode_pixel(p_id)
    if country != settings.active_country:
        return
    _flash_province_green(p_id)


## Реакция на ProvinceRegistry.factory_destroyed — если сейчас активен режим
## карты "экономика", обновляем цвет провинции (число фабрик уменьшилось).
func _on_factory_destroyed(p_id: int, country: String, amount: int) -> void:
    if current_map_mode == MapMode.ECONOMY:
        _update_mode_pixel(p_id)


## Запускает плавную зелёную вспышку на провинции p_id.
## Использует кольцевой буфер слотов, поэтому несколько вспышек
## могут идти одновременно (например, если построилось сразу
## несколько заводов в один день).
func _flash_province_green(p_id: int) -> void:
    var r = (p_id & 0xFF) / 255.0
    var g = ((p_id >> 8) & 0xFF) / 255.0
    var b = ((p_id >> 16) & 0xFF) / 255.0

    var slot = _flash_next_slot
    _flash_next_slot = (_flash_next_slot + 1) % FLASH_SLOTS

    _flash_ids[slot] = Vector3(r, g, b)
    _flash_starts[slot] = _game_time

    material.set_shader_parameter("flash_ids", _flash_ids)
    material.set_shader_parameter("flash_starts", _flash_starts)


func _deselect_province() -> void:
    material.set_shader_parameter("selected_province_color", Vector3(-1.0, -1.0, -1.0))
    material.set_shader_parameter("highlight_time", -1.0)
    _highlight_elapsed = -1.0

func _update_divisions_visibility() -> void:
    for army in get_tree().get_nodes_in_group("army_circles"):
        if is_instance_valid(army):
            army.visible = not divisions_hidden
            if is_instance_valid(army.current_path_node):
                army.current_path_node.visible = not divisions_hidden

func _on_child_entered_tree(node: Node) -> void:
    if node.has_method("setup") or node is Path2D:
        node.visible = not divisions_hidden

func _on_country_color_changed() -> void:
    material.set_shader_parameter("country_colors", ProvinceRegistry.country_colors)


# ─── РЕЖИМЫ КАРТЫ: ЭКОНОМИКА / НАСЕЛЕНИЕ (белый → оранжевый по значению) ─────
# Обе раскраски используют одну и ту же mode_texture/_rebuild_mode_texture/
# _update_mode_pixel — конкретное поле province_data берётся из
# _mode_field_name() в зависимости от current_map_mode.

## Переключить режим карты. Вызывать из UI (кнопка/выпадающий список режимов).
## MapMode.NONE       — обычная политическая карта (цвета стран).
## MapMode.ECONOMY    — раскраска по числу фабрик в провинции (белый → оранжевый).
## MapMode.POPULATION — раскраска по населению провинции (белый → зелёный).
func set_map_mode(mode: MapMode) -> void:
    current_map_mode = mode

    if mode == MapMode.NONE:
        material.set_shader_parameter("map_mode_active", false)
        return

    _apply_mode_gradient_colors()
    _rebuild_mode_texture()
    material.set_shader_parameter("map_mode_active", true)


## Переключить "только своя территория" для текущего режима (вызывается из
## чекбокса в ChooseMapPanel). Для MapMode.NONE ничего не делает — политическая
## карта чекбокс игнорирует.
func set_mode_only_own_country(value: bool) -> void:
    mode_only_own_country = value
    if current_map_mode != MapMode.NONE:
        _rebuild_mode_texture()


## У каждого режима свой градиент "низкое значение → высокое значение".
## Оба цвета — это те же уже существующие шейдерные параметры
## mode_color_low/mode_color_high, просто мы переустанавливаем их значения
## при каждом переключении режима (одновременно активен только один режим,
## так что отдельные uniform'ы под каждый режим не нужны).
func _apply_mode_gradient_colors() -> void:
    match current_map_mode:
        MapMode.ECONOMY:
            material.set_shader_parameter("mode_color_low",  Color(1.0, 1.0, 1.0))   # белый
            material.set_shader_parameter("mode_color_high", Color(1.0, 0.55, 0.0))  # оранжевый
        MapMode.POPULATION:
            material.set_shader_parameter("mode_color_low",  Color(1.0, 1.0, 1.0))   # белый
            material.set_shader_parameter("mode_color_high", Color(0.15, 0.75, 0.2)) # зелёный


## Возвращает имя поля в province_data, которым сейчас раскрашен режим —
## единая точка, которую нужно поменять/расширить, если добавится новый режим.
func _mode_field_name() -> String:
    match current_map_mode:
        MapMode.ECONOMY:
            return "factories"
        MapMode.POPULATION:
            return "population"
        _:
            return ""


## Полностью пересчитывает mode_texture по текущему полю активного режима
## (одна итерация по province_data + один update() в конце — как и в
## _paint_all_provinces_from_data, чтобы не тормозить на ~10000 провинций).
## Вызывается при входе в режим и когда точечное обновление
## (_update_mode_pixel) обнаруживает новый максимум.
func _rebuild_mode_texture() -> void:
    var field = _mode_field_name()
    if field == "":
        return

    mode_image.fill(Color(0, 0, 0, 0))

    var only_own = mode_only_own_country
    var target_country = settings.active_country

    # Считаем min/max поля режима. В обычном режиме min всегда 0 (как раньше:
    # белый = 0, а не "минимум по миру"). В режиме "только своя страна" и
    # минимум, и максимум берутся исключительно среди своих провинций —
    # поэтому белый цвет соответствует минимальному значению именно на своей
    # территории, а не нулю/минимуму по всему миру.
    var max_value: int = 1
    var min_value: int = 0

    if only_own:
        var first = true
        for key in ProvinceRegistry.province_data:
            var p_id = int(key)
            if p_id in IGNORE_IDS:
                continue
            var p = ProvinceRegistry.province_data[key]
            if p.get("owner", "") != target_country:
                continue
            var v = int(p.get(field, 0))
            if first:
                min_value = v
                max_value = v
                first = false
            else:
                if v > max_value:
                    max_value = v
                if v < min_value:
                    min_value = v
        if max_value <= min_value:
            max_value = min_value + 1  # избегаем деления на 0, если значение везде одинаковое
    else:
        for key in ProvinceRegistry.province_data:
            var p = ProvinceRegistry.province_data[key]
            var v = int(p.get(field, 0))
            if v > max_value:
                max_value = v

    _mode_max_value = max_value
    _mode_min_value = min_value

    for key in ProvinceRegistry.province_data:
        var p_id = int(key)
        if p_id in IGNORE_IDS:
            continue
        var p = ProvinceRegistry.province_data[key]
        var owner = p.get("owner", "")
        if owner == ProvinceRegistry.SEA_OWNER:
            continue  # море не участвует в раскраске режима, alpha=0 — шейдер оставит фон

        if only_own and owner != target_country:
            # чужая провинция в режиме "только своя страна" — не красим
            # градиентом, alpha остаётся 0, шейдер покажет обычный цвет страны
            continue

        var v = int(p.get(field, 0))
        var value = float(v - min_value) / float(max_value - min_value)  # 0..1
        value = clamp(value, 0.0, 1.0)

        var r = p_id & 0xFF
        var g = (p_id >> 8) & 0xFF
        # alpha=1 помечает "суша, участвует в раскраске текущего режима"
        mode_image.set_pixel(r, g, Color(value, 0, 0, 1))

    mode_texture.update(mode_image)


## Точечно обновляет ОДНУ провинцию в mode_texture (без полного перестроения) —
## используется, когда режим уже активен и в отдельной провинции поменялось
## значение поля текущего режима (постройка/разрушение завода, потери
## населения при ударе и т.п.). Если новое значение превышает текущий
## максимум _mode_max_value, шкала "0..1" для всех остальных провинций
## устарела — в этом случае проще перестроить всю текстуру целиком.
func _update_mode_pixel(p_id: int) -> void:
    var field = _mode_field_name()
    if field == "":
        return

    var p = ProvinceRegistry.province_data.get(p_id, {})
    var owner = p.get("owner", "")

    if mode_only_own_country and owner != settings.active_country:
        return  # чужая провинция в этом режиме не красится — трогать нечего

    var v = int(p.get(field, 0))

    # Новое значение вышло за пределы текущей отнормированной шкалы (выше
    # максимума, а в режиме "только своя страна" — ещё и ниже минимума) —
    # шкала устарела для всех провинций, проще перестроить текстуру целиком.
    if v > _mode_max_value or (mode_only_own_country and v < _mode_min_value):
        _rebuild_mode_texture()
        return

    var denom = _mode_max_value - _mode_min_value
    var value = 0.0
    if denom > 0:
        value = float(v - _mode_min_value) / float(denom)
    value = clamp(value, 0.0, 1.0)

    var r = p_id & 0xFF
    var g = (p_id >> 8) & 0xFF
    mode_image.set_pixel(r, g, Color(value, 0, 0, 1))
    mode_texture.update(mode_image)

func _build_province_centers():
    var img_size = tech_image.get_size()
    var sums: Dictionary = {}
    var counts: Dictionary = {}

    for y in img_size.y:
        for x in img_size.x:
            var px = tech_image.get_pixel(x, y)
            var p_id = _px_to_id(px)
            if p_id in IGNORE_IDS:
                continue
            if not sums.has(p_id):
                sums[p_id] = Vector2.ZERO
                counts[p_id] = 0
            sums[p_id] += Vector2(x, y)
            counts[p_id] += 1

    for p_id in sums:
        var avg_pixel = sums[p_id] / counts[p_id]
        var local_pos = avg_pixel
        if centered:
            local_pos -= Vector2(img_size) / 2.0
        province_centers[p_id] = local_pos
    # V-образные провинции
    settings.province_centers = province_centers


## Заполняет capital_texture по текущим "capital" всех стран (один проход,
## без отдельного texture.update() на каждую страну — только в конце).
func _init_capital_borders() -> void:
    capital_province_by_country.clear()
    for country in ProvinceRegistry.countries_data:
        var cap_id = int(ProvinceRegistry.countries_data[country].get("capital", 0))
        if cap_id <= 0:
            continue
        var r = cap_id & 0xFF
        var g = (cap_id >> 8) & 0xFF
        capital_image.set_pixel(r, g, Color(1, 1, 1, 1))
        capital_province_by_country[country] = cap_id

    capital_texture.update(capital_image)


## Снимает метку "столица" с указанной провинции в capital_image (без update()).
func _clear_capital_pixel(p_id: int) -> void:
    var r = p_id & 0xFF
    var g = (p_id >> 8) & 0xFF
    capital_image.set_pixel(r, g, Color(0, 0, 0, 0))


## Реакция на ProvinceRegistry.capital_changed — переставляем метку столицы
## в capital_texture: снимаем со старой провинции страны, ставим на новую.
## province_id == -1 → страна потеряла все провинции, просто снимаем метку.
func _on_capital_changed(country: String, province_id: int) -> void:
    if capital_province_by_country.has(country):
        _clear_capital_pixel(capital_province_by_country[country])
        capital_province_by_country.erase(country)

    if province_id >= 0:
        var r = province_id & 0xFF
        var g = (province_id >> 8) & 0xFF
        capital_image.set_pixel(r, g, Color(1, 1, 1, 1))
        capital_province_by_country[country] = province_id

    capital_texture.update(capital_image)
    
## RESET
## Удаляет все летящие БПЛА и ракеты (и игрока, и ИИ — они все добавляются
## как дети Map через add_child), плюс чистит линии-траектории.
func _clear_in_flight_projectiles() -> void:
    for child in get_children():
        if child is Sprite2D and child.get_script():
            var path = child.get_script().resource_path
            if path in ["res://scripts/uav_drone.gd", "res://scripts/missile.gd"]:
                child.queue_free()
    clear_uav_target_lines()
    if is_instance_valid(missile_lines_layer):
        missile_lines_layer.clear_line()
    if is_instance_valid(factory_labels_layer) and factory_labels_layer.has_method("clear"):
        factory_labels_layer.clear()

    # Если рестарт застал открытым режим прицеливания БПЛА/ракеты —
    # снимаем затемнение карты и разблокируем клики
    if uav_mode:
        exit_uav_mode()
    if missile_mode:
        exit_missile_mode()
    if distribute_mode:
        exit_distribute_mode()


## Закрывает вообще все меню/панели в CanvasLayer, кроме TopMenu.
## Работает "вслепую" по дереву — новое меню в будущем закроется само,
## без необходимости дописывать сюда ссылку на него.
func _close_all_menus() -> void:
    var canvas_layer = get_node_or_null("/root/Game/CanvasLayer")
    if not canvas_layer:
        return
    _close_menus_recursive(canvas_layer)


func _close_menus_recursive(node: Node) -> void:
    for child in node.get_children():
        if child is Container:
            # Контейнер сам не прячем — иначе .show() на его детях
            # потом ни на что не повлияет (родитель всё равно скрыт).
            # Спускаемся внутрь и прячем уже конкретные панели.
            _close_menus_recursive(child)
        elif child.has_method("hide"):
            child.hide()


func _reset_map_textures() -> void:
    data_image.fill(Color(0, 0, 0, 0))
    occup_image.fill(Color(0, 0, 0, 0))
    neg_image.fill(Color(0, 0, 0, 0))
    uav_image.fill(Color(0, 0, 0, 0))
    capital_image.fill(Color(0, 0, 0, 0))
    mode_image.fill(Color(0, 0, 0, 0))
    distribute_image.fill(Color(0, 0, 0, 0))
    data_texture.update(data_image)
    occup_texture.update(occup_image)
    neg_texture.update(neg_image)
    uav_texture.update(uav_image)
    capital_texture.update(capital_image)
    mode_texture.update(mode_image)
    distribute_texture.update(distribute_image)
    
## Перезапустить игру
func restart() -> void:
    _clear_in_flight_projectiles()
    _close_all_menus()

    ProvinceRegistry.reset()
    DivisionManager.reset()
    GameClock.reset()
    CombatManager.reset()
    DiplomacyManager.reset()
    AIManager.reset()

    var statistics_menu = get_node_or_null("/root/Game/CanvasLayer/StatisticsMenu")
    if statistics_menu:
        statistics_menu.reset()

    _reset_map_textures()
    _paint_all_provinces_from_data()
    _init_capital_borders()

    date._on_clock_day_passed({})
    date._update_speed_label(1)
    choose_map_panel.reset_to_default()

    settings.active_country = ""
    settings.can_draw = false
    blue.show()
