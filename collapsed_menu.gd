extends Control

var settings = preload("res://new_resource.tres")

@onready var country_name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/NameLabel
@onready var cause_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/NameLabel
@onready var date_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer3/NameLabel
@onready var days_in_power_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer4/NameLabel

@onready var Map = get_node("/root/Game/Map")

func _ready() -> void:
    hide()
    
    DiplomacyManager.player_regime_collapsed.connect(_show_menu)


func update(cause):
    country_name_label.text = settings.active_country
    cause_label.text = cause
    date_label.text = get_date_new(GameClock.get_date())
    days_in_power_label.text = ProvinceRegistry.get_days_in_power()


func _show_menu(country, old_ideology, new_ideology, cause):
    show()
    GameClock.lock_pause()
    update(cause)


func get_date_new(date_old):
    var month: String
    var month_num: int = date_old["month"]
    if month_num >= 1 and month_num <= 12:
        month = GameClock.MONTH_NAMES[month_num - 1]
    
    return month + " " + str(date_old["day"]) + ", " + str(date_old["year"])
    

func restart():
    Map.restart()
    hide()


func _on_restart_button_pressed() -> void:
    restart()


func _on_exit_button_pressed() -> void:
    get_tree().quit()
