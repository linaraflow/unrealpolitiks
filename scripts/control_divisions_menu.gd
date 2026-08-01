extends Control

var settings = preload("res://new_resource.tres")

@onready var QuanLabel: Label = $VBoxContainer/QuanPanel/MarginContainer/HBoxContainer/Label

@onready var DistributeButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/DistributeButton
@onready var MergeButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/MergeButton
@onready var SplitButton: Button = $VBoxContainer/QuanPanel/MarginContainer/HBoxContainer/SplitButton

@onready var DistributePanel: PanelContainer = $VBoxContainer/DistributePanel
@onready var NumTroops: Label = $VBoxContainer/DistributePanel/MarginContainer/VBoxContainer/HBoxContainer/NumProvinces

# ВАЖНО: путь ниже — предположение. Замени на реальный путь до кнопки
# подтверждения в твоей сцене DistributePanel (например ConfirmButton).
@onready var ConfirmDistributeButton: Button = $VBoxContainer/DistributePanel/MarginContainer/VBoxContainer/ConfirmButton

@onready var Map = get_node("/root/Game/Map")

# ─── DISTRIBUTE: состояние ────────────────────────────────────────────────────
var _distribute_active: bool = false
var _distribute_provinces: Array[int] = []   # порядок кликов = порядок присвоения

func _ready() -> void:
    SelectionManager.ControlDivisionsMenu = self
    DistributePanel.hide()
    hide()

    SelectionManager.selection_changed.connect(_on_selection_changed)
    ProvinceRegistry.province_army_changed.connect(_on_army_changed)

    MergeButton.pressed.connect(_on_merge_button_pressed)
    DistributeButton.pressed.connect(_on_distribute_button_pressed)
    ConfirmDistributeButton.pressed.connect(_on_confirm_distribute_pressed)

# ─── QUAN LABEL + СОСТОЯНИЕ КНОПОК ────────────────────────────────────────────

func _on_selection_changed() -> void:
    _refresh_ui()

func _on_army_changed(_p_id: int, _division = null) -> void:
    # Реагируем только если это может касаться выделенных дивизий —
    # раз в изменение армий пересчитываем сумму (дешево, без process()).
    if SelectionManager.has_selection():
        _refresh_ui()

func _refresh_ui() -> void:
    QuanLabel.text = ProvinceRegistry._format_number(str(SelectionManager.get_selected_soldiers_total()), ".")
    MergeButton.disabled = not SelectionManager.can_merge_selected()
    DistributeButton.disabled = not SelectionManager.has_selection()

# ─── MERGE ────────────────────────────────────────────────────────────────────

func _on_merge_button_pressed() -> void:
    if not SelectionManager.can_merge_selected():
        return
    SelectionManager.merge_selected()

# ─── DISTRIBUTE ───────────────────────────────────────────────────────────────

func _on_distribute_button_pressed() -> void:
    if _distribute_active:
        _cancel_distribute()
        return

    if not SelectionManager.has_selection():
        return

    _distribute_active = true
    _distribute_provinces.clear()
    NumTroops.text = "0"
    DistributePanel.show()
    Map.enter_distribute_mode()

## Вызывается из map.gd при клике по своей провинции, когда активен distribute-режим
func on_distribute_province_clicked(p_id: int) -> void:
    if not _distribute_active:
        return

    if p_id in _distribute_provinces:
        _distribute_provinces.erase(p_id)
        Map.set_distribute_province_highlighted(p_id, false)
    else:
        _distribute_provinces.append(p_id)
        Map.set_distribute_province_highlighted(p_id, true)

    NumTroops.text = str(_distribute_provinces.size())

func _on_confirm_distribute_pressed() -> void:
    _apply_distribution()
    _finish_distribute(false)

func _cancel_distribute() -> void:
    _finish_distribute(true)

func _apply_distribution() -> void:
    var divisions = SelectionManager.selected_divisions.duplicate()
    var count: int = min(divisions.size(), _distribute_provinces.size())

    # Первые count дивизий (в порядке выделения) идут на первые count
    # выбранных провинций (в порядке кликов). Остальные дивизии не трогаем.
    for i in range(count):
        var div = divisions[i]
        if not is_instance_valid(div):
            continue
        var target_p_id: int = _distribute_provinces[i]
        var target_pos: Vector2 = Map.settings.province_centers.get(target_p_id, div.position)
        div.start_movement_to(target_p_id, target_pos)

func _finish_distribute(_cancelled: bool) -> void:
    for p_id in _distribute_provinces:
        Map.set_distribute_province_highlighted(p_id, false)
    _distribute_provinces.clear()
    _distribute_active = false
    Map.exit_distribute_mode()
    DistributePanel.hide()
