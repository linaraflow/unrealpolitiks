extends TextureRect


@export var settings: Resource

var province_data: Dictionary = {}
var owner_name
var last_clicked_province


@onready var CountryMenu = get_node("/root/Game/CanvasLayer/CountryMenu")
@onready var ProvinceMenu = get_node("/root/Game/CanvasLayer/ProvinceMenu")


func _ready() -> void:
    add_to_group("FlagRect1")

func update():
    last_clicked_province = settings.last_clicked_province_id
    owner_name = ProvinceRegistry.province_data[str(last_clicked_province)].get("owner", "unknown")
    
    var flag_path = "res://assets/flags/" + owner_name + ".png"
    
    texture = load(flag_path)
    




func _on_mouse_entered() -> void:
    modulate = Color(0.7, 0.7, 0.7)  # темнее


func _on_mouse_exited() -> void:
    modulate = Color(1, 1, 1)  # обратно нормальный
