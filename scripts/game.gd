extends Node2D

@onready var hud_panel: VBoxContainer = $CanvasLayer/VBoxContainer
@onready var CountryMenu: Control = $CanvasLayer/VBoxContainer/CountryMenu
@onready var ProvinceMenu: Control = $CanvasLayer/VBoxContainer/ProvinceMenu
@onready var DivisionMenu: Control = $CanvasLayer/VBoxContainer/DivisionMenu

var _panel_visible: bool = true
var _shown_x: float
var _tween: Tween

func _ready() -> void:
    hud_panel.hide()
    _shown_x = hud_panel.position.x

func _unhandled_input(event: InputEvent) -> void:
    if Input.is_action_just_pressed("hide_ui"):
        _toggle_panel()
        get_viewport().set_input_as_handled()

func _toggle_panel() -> void:
    if _panel_visible:
        hide_panel()
    else:
        show_panel()

## Прячет hud_panel (уезжает влево за экран). Можно звать откуда угодно
## (например, при клике по морю на карте) — если панель уже спрятана,
## ничего не делает.
func hide_panel() -> void:
    if not _panel_visible:
        return

    if _tween and _tween.is_running():
        _tween.kill()

    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_CUBIC)
    _tween.set_ease(Tween.EASE_OUT)

    var hide_x := -hud_panel.size.x
    _tween.tween_property(hud_panel, "position:x", hide_x, 0.35)
    _tween.tween_callback(func(): hud_panel.visible = false)

    _panel_visible = false

## Показывает hud_panel (выезжает обратно на место). Можно звать откуда
## угодно (например, при клике по суше на карте) — если панель уже
## видима, ничего не делает.
func show_panel() -> void:
    if _panel_visible:
        return

    if _tween and _tween.is_running():
        _tween.kill()

    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_CUBIC)
    _tween.set_ease(Tween.EASE_OUT)

    hud_panel.visible = true
    hud_panel.position.x = -hud_panel.size.x
    _tween.tween_property(hud_panel, "position:x", _shown_x, 0.35)

    _panel_visible = true
