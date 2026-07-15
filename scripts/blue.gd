extends Button
@export var settings: GameSettings

@onready var ProvinceMenu = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu")
@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu")
@onready var TopMenu = get_node("/root/Game/CanvasLayer/TopMenu")
@onready var recruit_btn = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu/Panel/RecruitButton")
@onready var CountryPanel = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel")
@onready var NotificationMenu = get_node("/root/Game/CanvasLayer/NotificationMenu")

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
        get_node("/root/Game/CanvasLayer/TopMenu/TopPanel/DatePanel/PauseButton").icon = load("res://assets/pause_opened.png")
        TopMenu.update(text)
        TopMenu.show()
        CountryPanel.update_info()
        DivisionMenu.show()
        DivisionMenu.update_info(settings.province_data[settings.last_clicked_province_id])
        ProvinceMenu.show()
        ProvinceMenu.update_info(ProvinceRegistry.province_data[settings.last_clicked_province_id])
        NotificationMenu.show()
