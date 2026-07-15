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

var _neg_enemy: String = ""
var divisions_hidden: bool = false

# Сохраняем локальные координаты последнего физического клика мыши
var _last_click_local_pos: Vector2 = Vector2.ZERO

@onready var CountryMenu          = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu")
@onready var CountryPanel         = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel")
@onready var ProvinceMenu         = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu")
@onready var DivisionMenu         = get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu")
@onready var FlagRect             = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel/HeaderRow/FlagRect")
@onready var ColorPanel           = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel/HeaderRow/FlagRect/ColorPanel")
@onready var recruit_slider_panel = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu/RecruitSliderPanel")

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

    # capital_texture (обводка столичных провинций)
    capital_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
    capital_image.fill(Color(0, 0, 0, 0))
    capital_texture = ImageTexture.create_from_image(capital_image)

    material.set_shader_parameter("tech_map",      tech_tex)
    material.set_shader_parameter("data_texture",  data_texture)
    material.set_shader_parameter("occup_texture", occup_texture)
    material.set_shader_parameter("neg_texture",   neg_texture)
    material.set_shader_parameter("capital_texture", capital_texture)
    material.set_shader_parameter("country_colors", ProvinceRegistry.country_colors)

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

    if event.button_index == MOUSE_BUTTON_LEFT:
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
            get_node("../CanvasLayer/BLUE").text = current_owner
            CountryMenu.show()
            return
        else:
            ProvinceMenu.show()


func _handle_right_click(p_id, px, province_info, current_owner):
    print("ПКМ на провинции: ", p_id, " owner: ", current_owner)
    print("Есть выделенная дивизия: ", SelectionManager.has_selection())

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

        # Пустой owner ("" — ничья/неосвоенная земля) красим индексом 0.
        # Убедись, что country_colors[0] в countries.json — это нужный
        # тебе нейтральный цвet, а не случайно первая настоящая страна.
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
