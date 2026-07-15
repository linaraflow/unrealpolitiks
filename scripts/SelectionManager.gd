extends Node

var settings = preload("res://new_resource.tres")
@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu")

var selected_divisions: Array[Node] = []

func on_division_clicked(division: Node) -> void:
    if not is_instance_valid(division): return
    if division.division_owner != settings.active_country and settings.can_select == false: return

    if division.is_selected:
        division.deselect()
        selected_divisions.erase(division)
    else:
        if not Input.is_key_pressed(KEY_SHIFT):
            for d in selected_divisions:
                if is_instance_valid(d):
                    d.deselect()
            selected_divisions.clear()
        _select_division(division)

    if ProvinceRegistry.province_data.has(settings.last_clicked_province_id):
        DivisionMenu.update_info(ProvinceRegistry.province_data[settings.last_clicked_province_id])

func _select_division(division: Node) -> void:
    if not is_instance_valid(division) or division.is_selected:
        return
    division.select()
    selected_divisions.append(division)


func clear_selection() -> void:
    for d in selected_divisions:
        if is_instance_valid(d):
            d.deselect()
    selected_divisions.clear()

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
        if target_owner == "":
            return true
        if ProvinceRegistry.is_at_war(owner, target_owner):
            return true
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
