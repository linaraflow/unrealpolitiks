extends Button
@export var settings: GameSettings

@onready var ProvinceMenu = get_node("/root/Game/CanvasLayer/ProvinceMenu")
@onready var BalanceMenu = get_node("/root/Game/CanvasLayer/BalanceMenu")
@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/DivisionMenu")
@onready var recruit_btn = get_node("/root/Game/CanvasLayer/ProvinceMenu/Panel/RecruitButton")

func _ready():
    add_to_group("choose_button")
    # Загружаем JSON
    var file = FileAccess.open("res://scripts/countries.json", FileAccess.READ)
    var json = JSON.parse_string(file.get_as_text())
    file.close()
    

func _on_pressed():
    if text != "Choose Country":
        if settings:
            settings.active_country = text
            settings.can_draw = true
            hide()
            #get_parent().queue_free()
        GameClock.paused = false
        get_node("/root/Game/CanvasLayer/Date/PauseButton").icon = load("res://assets/pause_opened.png")
        
        DivisionMenu.show()
        DivisionMenu.update_info(settings.province_data[str(settings.last_clicked_province_id)])
        ProvinceMenu.show()
        BalanceMenu.show()
        recruit_btn.show()
