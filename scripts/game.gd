extends Node2D

@onready var hud_panel: VBoxContainer = $CanvasLayer/VBoxContainer
@onready var CountryMenu: Control = $CanvasLayer/VBoxContainer/CountryMenu
@onready var ProvinceMenu: Control = $CanvasLayer/VBoxContainer/ProvinceMenu
@onready var DivisionMenu: Control = $CanvasLayer/VBoxContainer/DivisionMenu

@onready var StatisticMenu: Control = $CanvasLayer/StatisticsMenu

var _panel_visible: bool = true
var _shown_x: float
var _tween: Tween

func _ready() -> void:
    await get_tree().process_frame

    _shown_x = hud_panel.position.x
    _position_stat_menu()

    # Пересчитываем позицию StatisticMenu КАЖДЫЙ раз, когда реально
    # меняется размер hud_panel (смена разрешения, языка и т.п.),
    # а не только один раз при старте игры.
    hud_panel.resized.connect(_on_hud_panel_resized)

    hide_panel()
    hud_panel.hide()

func _on_hud_panel_resized() -> void:
    # Во время открытия/закрытия панели (твин) её реальный x не совпадает
    # с "открытой" позицией — пересчитываем только когда панель в базовом,
    # не анимированном состоянии, иначе поедет и твин, и вручную поставленная позиция.
    if _tween and _tween.is_running():
        return
    _shown_x = hud_panel.position.x
    if _panel_visible:
        _position_stat_menu()

func _position_stat_menu() -> void:
    StatisticMenu.position.x = hud_panel.position.x + hud_panel.size.x + 6

func _unhandled_input(event: InputEvent) -> void:
    if Input.is_action_just_pressed("hide_ui"):
        _toggle_panel()
        get_viewport().set_input_as_handled()

func _toggle_panel() -> void:
    if _panel_visible:
        hide_panel()
    else:
        show_panel()

func hide_panel() -> void:
    if not _panel_visible:
        return

    if _tween and _tween.is_running():
        _tween.kill()

    var shift := hud_panel.size.x + 6
    var stat_target_x := StatisticMenu.position.x - shift

    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_CUBIC)
    _tween.set_ease(Tween.EASE_OUT)
    _tween.set_parallel(true)

    var hide_x := -hud_panel.size.x
    _tween.tween_property(hud_panel, "position:x", hide_x, 0.35)
    _tween.tween_property(StatisticMenu, "position:x", stat_target_x, 0.35)
    _tween.chain().tween_callback(func(): hud_panel.visible = false)

    _panel_visible = false

func show_panel() -> void:
    if _panel_visible:
        return

    if _tween and _tween.is_running():
        _tween.kill()

    var shift := hud_panel.size.x + 6
    var stat_target_x := StatisticMenu.position.x + shift

    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_CUBIC)
    _tween.set_ease(Tween.EASE_OUT)
    _tween.set_parallel(true)

    hud_panel.visible = true
    hud_panel.position.x = -hud_panel.size.x
    _tween.tween_property(hud_panel, "position:x", _shown_x, 0.35)
    _tween.tween_property(StatisticMenu, "position:x", stat_target_x, 0.35)

    _panel_visible = true
