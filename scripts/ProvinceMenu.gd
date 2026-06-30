extends Control

@export var settings: Resource

@onready var owner_label = $Panel/VBoxContainer/OwnerLabel
@onready var name_label  = $Panel/VBoxContainer/NameLabel
@onready var population_label = $Panel/VBoxContainer/PopulationLabel
@onready var recruit_btn = $Panel/RecruitButton

func _ready():
    $Panel.add_to_group("ProvincePanel")
    GameClock.on_day_passed.connect(_on_day_passed)
    hide()

var current_province_id: int = -1

func _on_day_passed(_date: Dictionary) -> void:
    if visible and settings.last_clicked_province_id != -1:
        var data = ProvinceRegistry.province_data.get(str(settings.last_clicked_province_id), {})
        update_info(data)

func update_info(data: Dictionary):
    if data.has("id"):
        current_province_id = int(data["id"])
    var owner_name = data.get("owner", "unknown")
    owner_label.text = "Owner: " + owner_name
    name_label.text  = "Province: " + data.get("name", "unknown")
    population_label.text = "Population 👥: " + _format_population(int(data.get("population", 0)))
    var flag_path = "res://assets/flags/" + owner_name + ".png"
    recruit_btn.visible = owner_name == settings.active_country and data.get("against_occupation", "") == ""
    var style = StyleBoxTexture.new()
    style.texture = load(flag_path)

func _format_population(n: int) -> String:
    var s = str(n)
    var result = ""
    var count = 0
    for i in range(s.length() - 1, -1, -1):
        result = s[i] + result
        count += 1
        if count % 3 == 0 and i != 0:
            result = " " + result
    return result
