extends Node

var settings = preload("res://new_resource.tres")
@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu")
@onready var ControlDivisionsMenu = get_node("/root/Game/CanvasLayer/ControlDivisionsMenu")

var _menu_visible_state: bool = false
var _menu_tween: Tween

var selected_divisions: Array[Node] = []

# чтобы UI (QuanLabel, кнопки) мог реагировать без опроса каждый кадр.
signal selection_changed

func on_division_clicked(division: Node) -> void:
    if not is_instance_valid(division): return
    if division.division_owner != settings.active_country and settings.can_select == false: return

    if division.is_selected:
        division.deselect()
        selected_divisions.erase(division)
        selection_changed.emit() 
    else:
        if not Input.is_key_pressed(KEY_SHIFT):
            for d in selected_divisions:
                if is_instance_valid(d):
                    d.deselect()
            selected_divisions.clear()
        _select_division(division)

    if ProvinceRegistry.province_data.has(settings.last_clicked_province_id):
        DivisionMenu.update_info(ProvinceRegistry.province_data[settings.last_clicked_province_id])

    _update_control_menu_visibility()

func _select_division(division: Node) -> void:
    if not is_instance_valid(division) or division.is_selected:
        return
    division.select()
    selected_divisions.append(division)
    selection_changed.emit()
    _update_control_menu_visibility()


func clear_selection() -> void:
    for d in selected_divisions:
        if is_instance_valid(d):
            d.deselect()
    selected_divisions.clear()
    selection_changed.emit()
    _update_control_menu_visibility()

func _update_control_menu_visibility() -> void:
    if not is_instance_valid(ControlDivisionsMenu):
        return
    var should_show = has_selection()
    if should_show == _menu_visible_state:
        return
    _menu_visible_state = should_show
    _animate_control_menu(should_show)

func _animate_control_menu(show_menu: bool) -> void:
    var menu = ControlDivisionsMenu
    if is_instance_valid(_menu_tween) and _menu_tween.is_valid():
        _menu_tween.kill()

    menu.pivot_offset = menu.size / 2.0
    _menu_tween = create_tween()
    _menu_tween.set_parallel(true)

    if show_menu:
        menu.visible = true
        menu.modulate.a = 0.0
        menu.scale = Vector2(0.9, 0.9)
        _menu_tween.tween_property(menu, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
        _menu_tween.tween_property(menu, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
    else:
        _menu_tween.tween_property(menu, "modulate:a", 0.0, 0.15).set_ease(Tween.EASE_IN)
        _menu_tween.tween_property(menu, "scale", Vector2(0.9, 0.9), 0.15).set_ease(Tween.EASE_IN)
        _menu_tween.chain().tween_callback(func(): menu.visible = false)

func move_selected_to(target_province_id: int, target_pos: Vector2) -> void:
    for div in selected_divisions:
        if is_instance_valid(div):
            div.start_movement_to(target_province_id, target_pos)

# Проверяем, может ли хотя бы одна выделенная дивизия двигаться в провинцию
# Дивизия может двигаться если: провинция принадлежит её владельцу ИЛИ владелец воюет с текущим хозяином
func can_move_to(target_province_id: int, target_owner: String) -> bool:
    for div in selected_divisions:
        if not is_instance_valid(div):
            continue
        var owner = div.division_owner
        if owner == target_owner:
            return true
        if target_owner == "" or target_owner == ProvinceRegistry.SEA_OWNER:
            return true
        if ProvinceRegistry.is_at_war(owner, target_owner):
            return true
        if not ProvinceRegistry.countries_data.has(owner) or not ProvinceRegistry.countries_data.has(target_owner):
            continue
        var owner_data = ProvinceRegistry.countries_data[div.division_owner]
        var province_owner_data = ProvinceRegistry.countries_data[target_owner]
        var check_control = div.division_owner in province_owner_data["control"] or target_owner in owner_data["control"]
        if check_control:
            return true
    return false

func get_selected_count() -> int:
    return selected_divisions.size()

func has_selection() -> bool:
    return selected_divisions.size() > 0

# НОВОЕ: суммарное количество солдат во всех выделенных дивизиях
func get_selected_soldiers_total() -> int:
    var total := 0
    for d in selected_divisions:
        if is_instance_valid(d):
            total += d.soldiers
    return total

# НОВОЕ: слияние разрешено только если ВСЕ выделенные дивизии
# стоят (не движутся) в одной и той же провинции и у одного владельца
func can_merge_selected() -> bool:
    if selected_divisions.size() < 2:
        return false

    var province_id: int = -1
    var owner_id: String = ""

    for d in selected_divisions:
        if not is_instance_valid(d):
            return false
        if d.is_moving:
            return false
        if province_id == -1:
            province_id = d.province_id
            owner_id = d.division_owner
        elif d.province_id != province_id or d.division_owner != owner_id:
            return false

    return true

# НОВОЕ: объединяет только ВЫДЕЛЕННЫЕ дивизии (не все дивизии в провинции)
func merge_selected() -> void:
    if not can_merge_selected():
        return

    var divs := selected_divisions.duplicate()
    var survivor = divs[0]

    DivisionManager.merge_specific_divisions(divs)

    # После слияния выделяем только выжившую (главную) дивизию
    for d in selected_divisions:
        if is_instance_valid(d) and d != survivor:
            d.deselect()
    selected_divisions.clear()
    if is_instance_valid(survivor):
        selected_divisions.append(survivor)
        if not survivor.is_selected:
            survivor.select()

    selection_changed.emit()
    _update_control_menu_visibility()
