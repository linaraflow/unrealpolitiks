extends TextureRect


@export var settings: Resource

var province_data: Dictionary = {}
var owner_name
var last_clicked_province

# ─── ссылки на узлы меню, созданные в сцене ────────────────────────────────
@onready var _color_panel: Panel = $ColorPanel
@onready var _color_picker: ColorPicker = $ColorPanel/ColorPicker


@onready var CountryMenu = get_node("/root/Game/CanvasLayer/CountryMenu")
@onready var ProvinceMenu = get_node("/root/Game/CanvasLayer/ProvinceMenu")


func _ready() -> void:
    add_to_group("FlagRect1")
    mouse_filter = Control.MOUSE_FILTER_STOP
    gui_input.connect(_on_gui_input)
    _color_picker.color_changed.connect(_on_color_changed)
    _color_panel.visible = false

func update():
    last_clicked_province = settings.last_clicked_province_id
    owner_name = ProvinceRegistry.province_data[last_clicked_province].get("owner", "unknown")
    
    var flag_path = "res://assets/flags/" + owner_name + ".png"
    
    texture = load(flag_path)


func _on_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _toggle_color_menu()


func _toggle_color_menu() -> void:
    if owner_name == null or owner_name == "" or owner_name == "unknown":
        return

    if _color_panel.visible:
        _color_panel.visible = false
        return

    var idx = ProvinceRegistry.country_index.get(owner_name, 0)
    if idx < ProvinceRegistry.country_colors.size():
        _color_picker.color = ProvinceRegistry.country_colors[idx]

    _color_panel.visible = true


func _on_color_changed(new_color: Color) -> void:
    if owner_name == null or owner_name == "":
        return
    ProvinceRegistry.change_country_color(owner_name, new_color)


func _on_mouse_entered() -> void:
    modulate = Color(0.7, 0.7, 0.7)  # темнее


func _on_mouse_exited() -> void:
    modulate = Color(1, 1, 1)  # обратно нормальный
