extends Control

var settings = preload("res://new_resource.tres")

@onready var QuanLabel: Label = $VBoxContainer/QuanPanel/MarginContainer/HBoxContainer/Label

@onready var DistributeButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/DistributeButton
@onready var MergeButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/MergeButton
@onready var SplitButton: Button = $VBoxContainer/QuanPanel/MarginContainer/HBoxContainer/SplitButton

# ВАЖНО: путь ниже — предположение. Замени на реальный путь до DisbandButton
# в твоей сцене (та же HBoxContainer, где DistributeButton и MergeButton).
@onready var DisbandButton: Button = $VBoxContainer/MainPanel/MarginContainer/HBoxContainer/DisbandButton

@onready var DistributePanel: PanelContainer = $VBoxContainer/DistributePanel
@onready var NumTroops: Label = $VBoxContainer/DistributePanel/MarginContainer/VBoxContainer/HBoxContainer/NumProvinces
@onready var NumDivisions: Label = $VBoxContainer/DistributePanel/MarginContainer/VBoxContainer/HBoxContainer2/NumProvinces

# ВАЖНО: путь ниже — предположение. Замени на реальный путь до кнопки
# подтверждения в твоей сцене DistributePanel (например ConfirmButton).
@onready var ConfirmDistributeButton: Button = $VBoxContainer/DistributePanel/MarginContainer/VBoxContainer/ConfirmButton

@onready var DisbandPanel: PanelContainer = $VBoxContainer/DisbandPanel
@onready var DisbandLabel: Label = $VBoxContainer/DisbandPanel/MarginContainer/VBoxContainer/Label
@onready var DisbandSlider: HSlider = $VBoxContainer/DisbandPanel/MarginContainer/VBoxContainer/HSlider
@onready var ConfirmDisbandButton: Button = $VBoxContainer/DisbandPanel/MarginContainer/VBoxContainer/ConfirmButton

@onready var Map = get_node("/root/Game/Map")

# ─── DISTRIBUTE: состояние ────────────────────────────────────────────────────
var _distribute_active: bool = false
var _distribute_provinces: Array[int] = []   # порядок кликов = порядок присвоения

func _ready() -> void:
    SelectionManager.ControlDivisionsMenu = self
    DistributePanel.hide()
    DisbandPanel.hide()
    hide()

    SelectionManager.selection_changed.connect(_on_selection_changed)
    ProvinceRegistry.province_army_changed.connect(_on_army_changed)

    MergeButton.pressed.connect(_on_merge_button_pressed)
    DistributeButton.pressed.connect(_on_distribute_button_pressed)
    ConfirmDistributeButton.pressed.connect(_on_confirm_distribute_pressed)

    DisbandButton.pressed.connect(_on_disband_button_pressed)
    ConfirmDisbandButton.pressed.connect(_on_confirm_disband_pressed)
    DisbandSlider.value_changed.connect(_on_disband_slider_changed)

# ─── QUAN LABEL + СОСТОЯНИЕ КНОПОК ────────────────────────────────────────────

func _on_selection_changed() -> void:
    _refresh_ui()
    if _distribute_active:
        NumDivisions.text = str(SelectionManager.selected_divisions.size())

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

    # Закрываем Disband, если он был открыт
    if DisbandPanel.visible:
        DisbandPanel.hide()

    _distribute_active = true
    _distribute_provinces.clear()
    NumTroops.text = "0"
    NumDivisions.text = str(SelectionManager.selected_divisions.size())
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

# ─── DISBAND ──────────────────────────────────────────────────────────────────

func _on_disband_button_pressed() -> void:
    if DisbandPanel.visible:
        DisbandPanel.hide()
        return

    if not SelectionManager.has_selection():
        return

    # На всякий случай закрываем режим Distribute, если он был активен
    if _distribute_active:
        _cancel_distribute()

    var total: int = SelectionManager.get_selected_soldiers_total()
    if total <= 0:
        return

    DisbandSlider.min_value = 0
    DisbandSlider.max_value = total
    DisbandSlider.step = 1
    DisbandSlider.value = 0
    _update_disband_label(0)

    DisbandPanel.show()

func _on_disband_slider_changed(value: float) -> void:
    _update_disband_label(int(value))

func _update_disband_label(amount: int) -> void:
    DisbandLabel.text = ProvinceRegistry._format_number(str(amount), ".")

func _on_confirm_disband_pressed() -> void:
    var amount: int = int(DisbandSlider.value)
    if amount > 0 and SelectionManager.has_selection():
        DivisionManager.disband_from_divisions(SelectionManager.selected_divisions, amount)

    DisbandPanel.hide()
