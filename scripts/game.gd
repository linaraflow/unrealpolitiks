extends Node2D

@onready var hud_panel: VBoxContainer = $CanvasLayer/VBoxContainer

var _panel_visible: bool = true
var _shown_x: float
var _tween: Tween

func _ready() -> void:
    _shown_x = hud_panel.position.x

func _unhandled_input(event: InputEvent) -> void:
    if Input.is_action_just_pressed("hide_ui"):
        _toggle_panel()
        get_viewport().set_input_as_handled()

func _toggle_panel() -> void:
    if _tween and _tween.is_running():
        _tween.kill()

    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_CUBIC)
    _tween.set_ease(Tween.EASE_OUT)

    if _panel_visible:
        # прячем: едем влево за пределы экрана, потом выключаем visible
        var hide_x := -hud_panel.size.x
        _tween.tween_property(hud_panel, "position:x", hide_x, 0.35)
        _tween.tween_callback(func(): hud_panel.visible = false)
    else:
        # показываем: сразу ставим за экран и уже видимым, затем едем на место
        hud_panel.visible = true
        hud_panel.position.x = -hud_panel.size.x
        _tween.tween_property(hud_panel, "position:x", _shown_x, 0.35)

    _panel_visible = not _panel_visible


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
    pass
