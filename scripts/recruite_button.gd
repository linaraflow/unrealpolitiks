extends Button

@export var settings: Resource
@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/DivisionMenu")
@onready var recruit_slider_panel = get_node("/root/Game/CanvasLayer/ProvinceMenu/RecruitSliderPanel")

var _province_id: int = -1
var _local_pos: Vector2 = Vector2.ZERO

func _ready():
    pressed.connect(_on_pressed)

func _on_pressed():
    _province_id = settings.last_clicked_province_id
    _local_pos = settings.local_mouse
    
    if _province_id == -1:
        return
        
    var p_data = ProvinceRegistry.province_data.get(_province_id, {})
    var pop = p_data.get("population", 0)
    var owner = p_data.get("owner", "")
    var balance = ProvinceRegistry.countries_data[owner]["balance"]

    # Открываем меню-слайдер вместо прямого призыва
    recruit_slider_panel.open_menu(_province_id, _local_pos, pop, balance)

func update_army_info():
    var p_data = ProvinceRegistry.province_data.get(settings.last_clicked_province_id, {})
    # Обновляем инфу в ProvinceMenu и DivisionMenu
    get_parent().get_parent().update_info(p_data)
    DivisionMenu.update_info(p_data)
