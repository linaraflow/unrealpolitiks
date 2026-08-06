extends Button
@export var settings: GameSettings

# Реальный ID страны (владелец провинции), НЕ подлежит переводу — используется
# для settings.active_country и т.д. Отдельно от text, который переводится
# через tr() и показывается игроку (см. set_country()).
var country_id: String = ""

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


## Единая точка установки страны на кнопке: id — идёт в логику (country_id),
## отображаемый text — переведённое название (или "Choose Country", если id пуст).
func set_country(id: String) -> void:
    country_id = id
    text = tr(id.to_upper()) if id != "" else tr("CHOOSE_COUNTRY")


func _on_pressed():
    if country_id != "" and ProvinceRegistry.province_data[settings.last_clicked_province_id].get("owner", "") != "sea":
        if settings:
            settings.active_country = country_id
            settings.can_draw = true
            hide()
            #get_parent().queue_free()
        GameClock.paused = false
        get_node("/root/Game/CanvasLayer/TopMenu/TopPanel/DatePanel/HBoxContainer/PauseButton").icon = load("res://assets/pause_opened.png")
        TopMenu.update(country_id)
        TopMenu.show()
        CountryPanel.update_info()
        DivisionMenu.show()
        DivisionMenu.update_info(settings.province_data[settings.last_clicked_province_id])
        ProvinceMenu.show()
        ProvinceMenu.update_info(ProvinceRegistry.province_data[settings.last_clicked_province_id])
        NotificationMenu.show()
